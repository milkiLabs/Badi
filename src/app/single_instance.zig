const std = @import("std");
const builtin = @import("builtin");
const state = @import("../state/mod.zig");

const replace_retry_count = 50;
const replace_retry_delay =
    std.Io.Duration.fromMilliseconds(20);

pub fn enabled(app: *state.AppState) bool {
    if (builtin.os.tag != .linux) return false;
    return app.singleInstanceEnabled();
}

pub fn listenReplacingExisting(io: std.Io) !std.Io.net.Server {
    var path_buf: [128]u8 = undefined;
    const addr = try address(&path_buf);

    var requested_replace = false;
    for (0..replace_retry_count) |attempt| {
        return addr.listen(io, .{}) catch |err| switch (err) {
            error.AddressInUse => {
                if (!requested_replace) {
                    try requestExistingInstanceClose(io, &addr);
                    requested_replace = true;
                }

                if (attempt + 1 == replace_retry_count) return error.AlreadyRunning;
                try std.Io.sleep(io, replace_retry_delay, .awake);
                continue;
            },
            else => return err,
        };
    }

    return error.AlreadyRunning;
}

fn requestExistingInstanceClose(io: std.Io, addr: *const std.Io.net.UnixAddress) !void {
    const stream = try addr.connect(io);
    defer stream.close(io);
}

fn address(path_buf: *[128]u8) !std.Io.net.UnixAddress {
    const uid = std.os.linux.getuid();
    const path = try std.fmt.bufPrint(path_buf, "\x00badi-single-instance-{}", .{uid});
    return std.Io.net.UnixAddress.init(path);
}
