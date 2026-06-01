// Types for desktop app discovery. `DesktopEntry` is a single loaded
// application. `DesktopAppList` is an owned, allocator-backed slice of
// entries with a `deinit` that frees all owned strings.

const std = @import("std");

/// A single desktop application: display name + Exec string. Both strings
/// are owned by the parent `DesktopAppList`'s allocator.
pub const DesktopEntry = struct {
    name: []const u8,
    exec: []const u8,

    pub fn deinit(self: DesktopEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.exec);
    }
};

/// Owned list of desktop entries. Use `empty(allocator)` to construct an
/// empty list (e.g. in tests), or get a populated one from
/// `core.desktop.loadDesktopApps`.
pub const DesktopAppList = struct {
    allocator: std.mem.Allocator,
    entries: []DesktopEntry,

    pub fn empty(allocator: std.mem.Allocator) DesktopAppList {
        return .{ .allocator = allocator, .entries = &.{} };
    }

    pub fn deinit(self: *DesktopAppList) void {
        for (self.entries) |entry| entry.deinit(self.allocator);
        self.allocator.free(self.entries);
        self.entries = &.{};
    }
};

test "DesktopAppList.empty round-trips" {
    const list = DesktopAppList.empty(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), list.entries.len);
}

/// Comptime accessor for `core.filter.filter`: the searchable name of a
/// DesktopEntry. Lives next to the type so anyone filtering on
/// DesktopEntry[] can `@import` it without reaching into UI.
pub fn nameOf(e: DesktopEntry) []const u8 {
    return e.name;
}
