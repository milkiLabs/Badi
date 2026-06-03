// Single-instance replacement callback. A second launcher process connects
// to this instance's abstract Unix socket; the old instance accepts the
// connection and closes so the new process can bind and show.

const qt6 = @import("libqt6zig");
const state = @import("../../state/mod.zig");

pub fn onReplacementRequested(notifier: qt6.QSocketNotifier, _: qt6.QSocketDescriptor, _: i32) callconv(.c) void {
    notifier.SetEnabled(false);

    const app = state.global.assertGet();
    if (app.single_instance_server) |*server| {
        const stream = server.accept(app.io) catch {
            notifier.SetEnabled(true);
            return;
        };
        stream.close(app.io);
    }

    app.exit_code = 0;
    _ = app.ui.main.Close();
}
