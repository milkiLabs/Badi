// XDG config directory resolution. Single place that knows the
// $XDG_CONFIG_HOME / ~/.config/badi convention.

const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const EnvMap = std.process.Environ.Map;

/// Returns the badi config dir (~/.config/badi/ or $XDG_CONFIG_HOME/badi/),
/// creating it if needed. Returns null if HOME is unset and XDG_CONFIG_HOME
/// is unset (the user has no config dir at all).
pub fn resolve(arena: std.mem.Allocator, env: *const EnvMap, io: Io) ?Dir {
    const xdg_config_home = env.get("XDG_CONFIG_HOME");
    const home = env.get("HOME");

    const config_dir_path = if (xdg_config_home) |xdg|
        std.fs.path.join(arena, &.{ xdg, "badi" }) catch return null
    else if (home) |h|
        std.fs.path.join(arena, &.{ h, ".config", "badi" }) catch return null
    else
        return null;

    return Dir.cwd().createDirPathOpen(io, config_dir_path, .{}) catch null;
}
