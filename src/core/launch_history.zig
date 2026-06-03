const std = @import("std");

const EnvMap = std.process.Environ.Map;
const max_history_file_size: usize = 1024 * 1024;

pub const History = struct {
    allocator: std.mem.Allocator,
    launch_counts: std.StringHashMapUnmanaged(u32) = .empty,

    pub fn empty(allocator: std.mem.Allocator) History {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *History) void {
        var it = self.launch_counts.keyIterator();
        while (it.next()) |key| self.allocator.free(key.*);
        self.launch_counts.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn count(self: *const History, app_id: []const u8) u32 {
        return self.launch_counts.get(app_id) orelse 0;
    }

    pub fn boost(self: *const History, app_id: []const u8) i64 {
        return launchBoost(self.count(app_id));
    }

    pub fn increment(self: *History, app_id: []const u8) !void {
        const gop = try self.launch_counts.getOrPut(self.allocator, app_id);
        if (gop.found_existing) {
            gop.value_ptr.* = std.math.add(u32, gop.value_ptr.*, 1) catch std.math.maxInt(u32);
            return;
        }

        gop.key_ptr.* = try self.allocator.dupe(u8, app_id);
        gop.value_ptr.* = 1;
    }
};

/// Frequency signal used by app ranking. This intentionally grows slowly:
/// it breaks relevance ties and nudges vague matches without letting history
/// overpower a clearly better textual match.
pub fn launchBoost(count: u32) i64 {
    if (count == 0) return 0;
    return @intCast(std.math.log2_int(u32, count));
}

pub fn load(allocator: std.mem.Allocator, env: *const EnvMap, io: std.Io) History {
    var history = History.empty(allocator);
    errdefer history.deinit();

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var dir = dataDir(arena, env, io) orelse return history;
    defer dir.close(io);

    const content = dir.readFileAlloc(io, "history.json", arena, .limited(max_history_file_size)) catch return history;
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, content, .{ .ignore_unknown_fields = true }) catch return history;
    if (root != .object) return history;
    const counts_value = root.object.get("launch_counts") orelse return history;
    if (counts_value != .object) return history;

    var it = counts_value.object.iterator();
    while (it.next()) |entry| {
        const parsed = parseCount(entry.value_ptr.*) orelse continue;
        const key = allocator.dupe(u8, entry.key_ptr.*) catch continue;
        history.launch_counts.put(allocator, key, parsed) catch {
            allocator.free(key);
            continue;
        };
    }

    return history;
}

pub fn recordLaunch(history: *History, env: *const EnvMap, io: std.Io, app_id: []const u8) !void {
    try history.increment(app_id);
    try save(history, env, io);
}

pub fn save(history: *const History, env: *const EnvMap, io: std.Io) !void {
    var arena_state = std.heap.ArenaAllocator.init(history.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var dir = dataDir(arena, env, io) orelse return;
    defer dir.close(io);

    var counts = std.json.Value{ .object = .empty };
    var it = history.launch_counts.iterator();
    while (it.next()) |entry| {
        try counts.object.put(arena, entry.key_ptr.*, .{ .integer = entry.value_ptr.* });
    }

    var root = std.json.Value{ .object = .empty };
    try root.object.put(arena, "launch_counts", counts);

    const json = try std.json.Stringify.valueAlloc(arena, root, .{ .whitespace = .indent_4 });
    const file = try dir.createFile(io, "history.json", .{});
    defer file.close(io);
    try file.writePositionalAll(io, json, 0);
}

fn parseCount(value: std.json.Value) ?u32 {
    return switch (value) {
        .integer => |n| if (n > 0 and n <= std.math.maxInt(u32)) @intCast(n) else null,
        else => null,
    };
}

fn dataDir(arena: std.mem.Allocator, env: *const EnvMap, io: std.Io) ?std.Io.Dir {
    const xdg_data_home = env.get("XDG_DATA_HOME");
    const home = env.get("HOME");

    const path = if (xdg_data_home) |xdg|
        std.fs.path.join(arena, &.{ xdg, "badi" }) catch return null
    else if (home) |h|
        std.fs.path.join(arena, &.{ h, ".local", "share", "badi" }) catch return null
    else
        return null;

    return std.Io.Dir.cwd().createDirPathOpen(io, path, .{}) catch null;
}

test "launch boost grows logarithmically" {
    try std.testing.expectEqual(@as(i64, 0), launchBoost(0));
    try std.testing.expectEqual(@as(i64, 0), launchBoost(1));
    try std.testing.expectEqual(@as(i64, 1), launchBoost(2));
    try std.testing.expectEqual(@as(i64, 1), launchBoost(3));
    try std.testing.expectEqual(@as(i64, 2), launchBoost(4));
    try std.testing.expectEqual(@as(i64, 3), launchBoost(8));
}

test "history increments counts" {
    var history = History.empty(std.testing.allocator);
    defer history.deinit();

    try history.increment("firefox.desktop");
    try history.increment("firefox.desktop");
    try history.increment("terminal.desktop");

    try std.testing.expectEqual(@as(u32, 2), history.count("firefox.desktop"));
    try std.testing.expectEqual(@as(u32, 1), history.count("terminal.desktop"));
    try std.testing.expectEqual(@as(u32, 0), history.count("missing.desktop"));
}
