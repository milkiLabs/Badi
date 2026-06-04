// The single mutable state container. Lives in the gpa; deinit frees the
// owned lists. Widget handles are NOT owned by this struct — Qt owns them.
//
// Fields are grouped by concern:
//   - Core: allocator, io, ui
//   - Mode: which mode is active, the final exit code
//   - Source: the data being filtered (apps / piped lines / emoji)
//   - Piped state: incremental stdin buffering
//   - Filter state: the current query, visible rows, piped scores, selection

const std = @import("std");
const config = @import("../config/mod.zig");
const core = @import("../core/mod.zig");
const desktop = @import("../core/desktop/mod.zig");
const emoji = @import("../core/emoji/mod.zig");
const plugin = @import("../plugins/api.zig");
const Widgets = @import("widgets.zig").Widgets;
const mode_mod = @import("mode.zig");

const AppMode = mode_mod.AppMode;
const PromptConfig = mode_mod.PromptConfig;
const EmojiConfig = mode_mod.EmojiConfig;

pub const AppState = struct {
    // Core
    allocator: std.mem.Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    ui: Widgets,
    single_instance_server: ?std.Io.net.Server,

    // Mode
    mode: AppMode,
    exit_code: ?u8,

    // Source data
    app_list: ?desktop.DesktopAppList,
    launch_history: core.launch_history.History,
    launched_app_id: ?[]const u8,
    emojis: ?emoji.EmojiData,
    emojis_loaded: bool,
    prefixes: std.ArrayList(config.Action),
    registered_triggers: std.ArrayList(plugin.Trigger),
    prompt_context: PromptConfig,
    emoji_cli_context: EmojiConfig,
    emoji_trigger_context: EmojiConfig,

    // Piped state
    piped_items: std.ArrayList([]const u8),
    stdin_pending: std.ArrayList(u8),
    stdin_eof: bool,

    // Filter state
    current_query: std.ArrayList(u8),
    visible_indices: std.ArrayList(usize),
    piped_visible_scores: std.ArrayList(i64),
    selected_index: ?usize,

    /// Re-entrancy guard for `setInputText`. A `SetText` call that we issue
    /// programmatically (e.g. from `enterPrefixMode`) fires the
    /// `textChanged` signal synchronously. The handler would re-run mode
    /// detection and re-filter, which is wasted work — the helper has
    /// already done both. Wrap programmatic writes in `setInputText` and
    /// the handler short-circuits while the guard is set.
    setting_text: bool,

    /// Returns the loaded desktop apps, or an empty slice if not loaded.
    pub fn apps(self: *const AppState) []const desktop.DesktopEntry {
        if (self.app_list) |list| return list.entries;
        return &.{};
    }

    /// Returns the loaded emoji set, or an empty slice if not loaded.
    pub fn emojiEntries(self: *const AppState) []const emoji.EmojiEntry {
        if (self.emojis_loaded) {
            const data = self.emojis orelse return &.{};
            return data.entries;
        }
        return &.{};
    }

    /// Allocates the emoji entry slice the first time emoji mode is
    /// requested. The embedded slab itself remains compile-time data; this
    /// only pays for the process-owned index over that slab.
    pub fn ensureEmojisLoaded(self: *AppState) !void {
        if (self.emojis_loaded) return;
        self.emojis = try emoji.loadEmojis(self.allocator);
        self.emojis_loaded = true;
    }

    /// Number of rows the model exposes right now. Single source of truth
    /// for `view.resultCount`, `view.computeHasResults`, and the Qt model
    /// row-count callback — three callers that used to switch on `app.mode`
    /// independently.
    pub fn resultCount(self: *const AppState) usize {
        return self.mode.plugin.resultCount(self, self.mode.ctx);
    }

    pub fn badgeText(self: *AppState) ?[]const u8 {
        const callback = self.mode.plugin.badgeText orelse return null;
        return callback(self, self.mode.ctx);
    }

    pub fn emptyText(self: *const AppState) []const u8 {
        const callback = self.mode.plugin.emptyText orelse return "No results";
        return callback(self, self.mode.ctx);
    }

    pub fn canExitToDefault(self: *const AppState) bool {
        const callback = self.mode.plugin.canExitToDefault orelse return false;
        return callback(self, self.mode.ctx);
    }

    pub fn isCancelable(self: *const AppState) bool {
        const callback = self.mode.plugin.isCancelable orelse return false;
        return callback(self, self.mode.ctx);
    }

    pub fn singleInstanceEnabled(self: *const AppState) bool {
        return self.mode.plugin.singleInstance;
    }

    /// Sets the input field text without triggering a `textChanged` re-entry.
    /// Use this for programmatic writes that the user did not type — the
    /// caller is responsible for any state changes the new text implies
    /// (mode switch, re-filter, etc.).
    pub fn setInputText(self: *AppState, text: []const u8) void {
        self.setting_text = true;
        defer self.setting_text = false;
        self.ui.input.SetText(text);
    }

    pub const Selection = struct {
        data: []const u8,
        app_id: ?[]const u8 = null,
    };

    /// Resolves the current selection's data from the already-synced
    /// selected_index. Pure data lookup — does not touch Qt widgets.
    /// Returns null in `prefix`, `url`, and `prompt` modes: those read the
    /// answer directly from the input field at launch time.
    pub fn currentSelectionData(self: *const AppState) ?Selection {
        const selected = self.selected_index orelse return null;
        if (selected >= self.visible_indices.items.len) return null;
        const source_index = self.visible_indices.items[selected];
        return switch (self.mode.plugin.selection_source) {
            .apps => .{ .data = self.apps()[source_index].exec, .app_id = desktop.idOf(self.apps()[source_index]) },
            .piped => .{ .data = self.piped_items.items[source_index] },
            .emoji => .{ .data = self.emojiEntries()[source_index].glyph },
            .none => null,
        };
    }

    pub fn deinit(self: *AppState) void {
        if (self.single_instance_server) |*server| server.deinit(self.io);
        self.launch_history.deinit();
        if (self.app_list) |*list| list.deinit();
        if (self.emojis_loaded) {
            if (self.emojis) |*data| data.deinit(self.allocator);
        }
        for (self.piped_items.items) |item| self.allocator.free(item);
        self.piped_items.deinit(self.allocator);
        self.stdin_pending.deinit(self.allocator);
        for (self.prefixes.items) |p| {
            self.allocator.free(p.trigger);
            self.allocator.free(p.name);
            self.allocator.free(p.icon);
            self.allocator.free(p.action);
        }
        self.prefixes.deinit(self.allocator);
        self.registered_triggers.deinit(self.allocator);
        self.current_query.deinit(self.allocator);
        self.visible_indices.deinit(self.allocator);
        self.piped_visible_scores.deinit(self.allocator);
    }
};
