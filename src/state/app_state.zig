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

pub const AppMode = mode_mod.AppMode;
pub const PromptConfig = mode_mod.PromptConfig;
pub const EmojiConfig = mode_mod.EmojiConfig;
pub const EmojiAction = mode_mod.EmojiAction;

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
