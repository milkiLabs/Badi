// Central application state.
//
// Why a global pointer? libqt6zig callbacks use the C ABI, which means no
// closures or captured variables. The only way for a callback to access
// application state is through a global. `setActive()` is called once at
// startup, and `state()` returns the pointer from anywhere in the codebase.
//
// Both `ui/` and `core/` read from this, but neither imports the other.

const std = @import("std");
const qt6 = @import("libqt6zig");
const config = @import("config.zig");
const desktop = @import("core/desktop.zig");

// Re-export core types so callers only need to import this file.
pub const DesktopEntry = desktop.DesktopEntry;
pub const DesktopAppList = desktop.DesktopAppList;
pub const Action = config.Action;

/// The three modes Badi can operate in.
/// `prefix` carries the active action config; the others carry no data.
pub const AppMode = union(enum) {
    apps: void,
    piped: void,
    prefix: Action,
};

/// All mutable application state. Widgets are stored as opaque Qt handles —
/// the actual objects live in C++ land and are freed by Qt's parent-child
/// ownership, not by Zig.
pub const AppState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    // Qt widget handles — owned by Qt, freed when main_widget is deleted.
    ui: struct {
        main: qt6.QWidget,
        badge: qt6.QLabel,
        input: qt6.QLineEdit,
        list: qt6.QListView,
        model: qt6.QAbstractListModel,
        no_results: qt6.QLabel,
    },

    mode: AppMode,
    exit_code: ?u8, // set by selection, returned from main()
    app_list: ?DesktopAppList,
    piped_items: std.ArrayList([]const u8), // owned strings from stdin
    stdin_pending: std.ArrayList(u8), // raw bytes awaiting a newline
    prefixes: std.ArrayList(Action),
    current_query: std.ArrayList(u8),
    visible_indices: std.ArrayList(usize), // filtered source rows currently selectable
    selected_index: ?usize, // index into visible_indices, not the Qt row
    stdin_eof: bool, // true once stdin signals EOF (pipe closed)

    pub fn apps(self: *const AppState) []const DesktopEntry {
        if (self.app_list) |list| return list.entries;
        return &[_]DesktopEntry{};
    }

    pub const Selection = struct {
        data: []const u8,
    };

    /// Resolves the current selection's data from the already-synced selected_index.
    /// Does not touch Qt widgets — pure data lookup using visible_indices.
    pub fn currentSelectionData(self: *const AppState) ?Selection {
        const selected = self.selected_index orelse return null;
        if (selected >= self.visible_indices.items.len) return null;
        const source_index = self.visible_indices.items[selected];

        return switch (self.mode) {
            .apps => .{ .data = self.apps()[source_index].exec },
            .piped => .{ .data = self.piped_items.items[source_index] },
            .prefix => null,
        };
    }

    pub fn deinit(self: *AppState) void {
        if (self.app_list) |*list| list.deinit();
        for (self.piped_items.items) |item| self.allocator.free(item);
        self.piped_items.deinit(self.allocator);
        self.stdin_pending.deinit(self.allocator);
        self.prefixes.deinit(self.allocator);
        self.current_query.deinit(self.allocator);
        self.visible_indices.deinit(self.allocator);
        active_state = null;
    }
};

// Global state pointer — the C ABI bridge.
var active_state: ?*AppState = null;

pub fn setActive(app_state: *AppState) void {
    active_state = app_state;
}

pub fn state() *AppState {
    return active_state.?;
}
