const std = @import("std");

test {
    std.testing.refAllDecls(@import("core/desktop.zig"));
    std.testing.refAllDecls(@import("core/exec.zig"));
}
