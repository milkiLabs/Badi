// The single mutable state container. Lives in the gpa; deinit frees the
// owned lists. Widget handles are NOT owned by this struct — Qt owns them.
//
// Fields are grouped by concern:
//   - Core: allocator, io, ui
//   - Mode: which mode is active, the final exit code
//   - Source: the data being filtered (apps / piped lines)
//   - Piped state: incremental stdin buffering
//   - Filter state: the current query, visible rows, selection

const std = @import("std");
const config = @import("../config/mod.zig");
const desktop = @import("../core/desktop/mod.zig");
const emoji = @import("../core/emoji/mod.zig");
const Widgets = @import("widgets.zig").Widgets;
const mode_mod = @import("mode.zig");

const AppMode = mode_mod.AppMode;
const PromptConfig = mode_mod.PromptConfig;
const EmojiConfig = mode_mod.EmojiConfig;
const EmojiAction = mode_mod.EmojiAction;

pub const AppState = struct {
    // Core
    allocator: std.mem.Allocator,
    io: std.Io,
    ui: Widgets,
    single_instance_server: ?std.Io.net.Server,

    // Mode
    mode: AppMode,
    exit_code: ?u8,

    // Source data
    app_list: ?desktop.DesktopAppList,
    emojis: ?emoji.EmojiData,
    prefixes: std.ArrayList(config.Action),

    // Piped state
    piped_items: std.ArrayList([]const u8),
    stdin_pending: std.ArrayList(u8),
    stdin_eof: bool,

    // Filter state
    current_query: std.ArrayList(u8),
    visible_indices: std.ArrayList(usize),
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
        if (self.emojis) |data| return data.entries;
        return &.{};
    }

    /// Number of rows the model exposes right now. Single source of truth
    /// for `view.resultCount`, `view.computeHasResults`, and the Qt model
    /// row-count callback — three callers that used to switch on `app.mode`
    /// independently.
    pub fn resultCount(self: *const AppState) usize {
        return switch (self.mode) {
            .prefix, .url => if (self.current_query.items.len > 0) 1 else 0,
            .prompt => 0,
            .apps, .piped, .emoji => self.visible_indices.items.len,
        };
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
    };

    /// Resolves the current selection's data from the already-synced
    /// selected_index. Pure data lookup — does not touch Qt widgets.
    /// Returns null in `prefix`, `url`, and `prompt` modes: those read the
    /// answer directly from the input field at launch time.
    pub fn currentSelectionData(self: *const AppState) ?Selection {
        const selected = self.selected_index orelse return null;
        if (selected >= self.visible_indices.items.len) return null;
        const source_index = self.visible_indices.items[selected];
        return switch (self.mode) {
            .apps => .{ .data = self.apps()[source_index].exec },
            .piped => .{ .data = self.piped_items.items[source_index] },
            .emoji => .{ .data = self.emojiEntries()[source_index].glyph },
            .prefix, .url, .prompt => null,
        };
    }

    pub fn deinit(self: *AppState) void {
        if (self.single_instance_server) |*server| server.deinit(self.io);
        if (self.app_list) |*list| list.deinit();
        if (self.emojis) |*data| data.deinit(self.allocator);
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
        self.current_query.deinit(self.allocator);
        self.visible_indices.deinit(self.allocator);
    }
};
