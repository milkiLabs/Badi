// XDG conventions for desktop app discovery: env var parsing, dir
// enumeration, and TryExec PATH lookup. All env interactions for the
// desktop loader live here.

const std = @import("std");
const EnvMap = std.process.Environ.Map;

/// Builds the ordered list of XDG application directories: XDG_DATA_HOME
/// (or ~/.local/share) followed by XDG_DATA_DIRS (or the default). Each
/// returned slice points into `path_storage`; the caller owns that buffer.
pub fn dataDirs(
    allocator: std.mem.Allocator,
    env: *const EnvMap,
    path_storage: *std.ArrayList([]const u8),
) !void {
    // XDG_DATA_HOME takes priority; fall back to ~/.local/share.
    if (env.get("XDG_DATA_HOME")) |xdh| {
        const path = try std.fmt.allocPrint(allocator, "{s}/applications", .{xdh});
        try path_storage.append(allocator, path);
    } else if (env.get("HOME")) |home| {
        const path = try std.fmt.allocPrint(allocator, "{s}/.local/share/applications", .{home});
        try path_storage.append(allocator, path);
    }

    // System-wide dirs from XDG_DATA_DIRS.
    const dirs_raw = env.get("XDG_DATA_DIRS") orelse "/usr/local/share:/usr/share";
    var dirs = std.mem.splitScalar(u8, dirs_raw, ':');
    while (dirs.next()) |dir| {
        if (dir.len == 0) continue;
        const path = try std.fmt.allocPrint(allocator, "{s}/applications", .{dir});
        try path_storage.append(allocator, path);
    }
}

/// Checks if a TryExec binary exists on PATH or as an absolute/relative
/// path. Empty TryExec means "always available" per the XDG spec.
pub fn tryExecAvailable(allocator: std.mem.Allocator, io: std.Io, env: *const EnvMap, try_exec: []const u8) bool {
    if (try_exec.len == 0) return true;

    // Absolute or relative path with slash — check directly.
    if (std.mem.indexOfScalar(u8, try_exec, '/') != null) {
        std.Io.Dir.cwd().access(io, try_exec, .{ .execute = true }) catch return false;
        return true;
    }

    // Bare filename — search PATH.
    const path_var = env.get("PATH") orelse "/usr/local/bin:/usr/bin:/bin";
    var paths = std.mem.splitScalar(u8, path_var, ':');
    while (paths.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = std.fs.path.join(allocator, &.{ dir, try_exec }) catch return false;
        defer allocator.free(candidate);
        std.Io.Dir.cwd().access(io, candidate, .{ .execute = true }) catch continue;
        return true;
    }

    return false;
}
