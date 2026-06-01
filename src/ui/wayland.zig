const qt6 = @import("libqt6zig");

extern "C" fn badi_is_wayland_session() bool;
extern "C" fn badi_layer_shell_setup(qwindow_ptr: ?*anyopaque, width: i32, height: i32) void;

pub fn isWayland() bool {
    return badi_is_wayland_session();
}

pub fn setup(widget: qt6.QWidget) void {
    if (!isWayland()) return;

    // Force creation of the platform window handle (QWindow) before the widget is shown.
    widget.CreateWinId();

    const width = widget.Width();
    const height = widget.Height();

    const qwin = widget.WindowHandle();
    badi_layer_shell_setup(@ptrCast(qwin.ptr), width, height);
}
