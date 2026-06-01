// Emoji mode: the user has selected an emoji. Routes the glyph to the
// configured action:
//   .copy      — clipboard (wl-copy → xclip → stdout fallback)
//   .print     — write the glyph to stdout (dmenu-style), exit 0
//   .type_keys — synthesize keystrokes via wtype (Wayland) or xdotool
//                (X11); falls back to clipboard if neither is available
//
// All actions close the window on success. Failure paths are silent —
// we don't want an emoji picker to nag the user about a broken tool.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../state/mod.zig");

const stdout_buf_size: usize = 8192;

pub fn launch(app: *state.AppState) void {
    const selection = app.currentSelectionData() orelse return;
    const glyph = selection.data;
    if (glyph.len == 0) return;

    switch (app.mode.emoji.action) {
        .copy => copyToClipboard(app, glyph),
        .print => writeStdoutAndExit(app, glyph, 0),
        .type_keys => typeKeysAndExit(app, glyph),
    }
}

/// Copies the glyph to the system clipboard. Prefers `wl-copy` (Wayland),
/// falls back to `xclip -selection clipboard` (X11), then to stdout as a
/// last resort. Each external tool is spawned detached so Badi can exit
/// without waiting; both wl-copy and xclip keep a daemon alive to serve
/// the clipboard after their parent exits.
fn copyToClipboard(app: *state.AppState, glyph: []const u8) void {
    // wl-copy accepts the string as a positional argument — no stdin dance.
    if (qt6.QProcess.StartDetached22(app.allocator, "wl-copy", &.{glyph})) {
        app.exit_code = 0;
        _ = app.ui.main.Close();
        return;
    }
    // xclip on X11 wants stdin; we use a small synchronous child so we
    // can write the glyph and wait for the copy to complete before the
    // helper exits and the clipboard data evaporates.
    if (copyWithXclip(app, glyph)) return;
    writeStdoutAndExit(app, glyph, 0);
}

fn copyWithXclip(app: *state.AppState, glyph: []const u8) bool {
    var child = std.process.spawnPath(app.io, .cwd(), .{
        .argv = &.{ "xclip", "-selection", "clipboard", "-in" },
        .stdin = .pipe,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return false;

    const stdin = child.stdin orelse return false;
    var wbuf: [256]u8 = undefined;
    var w = stdin.writer(app.io, &wbuf);
    w.interface.writeAll(glyph) catch {};
    w.interface.flush() catch {};
    stdin.close(app.io);

    _ = child.wait(app.io) catch {};
    app.exit_code = 0;
    _ = app.ui.main.Close();
    return true;
}

/// Writes the glyph to stdout (no trailing newline — dmenu convention is
/// to print exactly the selected value). Closes the window with the
/// given exit code.
fn writeStdoutAndExit(app: *state.AppState, glyph: []const u8, code: u8) void {
    const stdout = std.Io.File.stdout();
    var buf: [stdout_buf_size]u8 = undefined;
    var writer = stdout.writer(app.io, &buf);
    writer.interface.writeAll(glyph) catch {};
    writer.interface.flush() catch {};
    app.exit_code = code;
    _ = app.ui.main.Close();
}

/// Detects the display server and synthesizes the glyph into the focused
/// window. Best-effort: Wayland uses wtype (only available on compositors
/// that support the virtual-keyboard protocol), X11 uses xdotool. If
/// neither is available, falls back to the clipboard so the user still
/// gets the emoji.
fn typeKeysAndExit(app: *state.AppState, glyph: []const u8) void {
    var env_map = std.process.Environ.Map.init(app.allocator);
    defer env_map.deinit();

    const wayland = env_map.get("WAYLAND_DISPLAY") != null;
    const ok = if (wayland)
        qt6.QProcess.StartDetached22(app.allocator, "wtype", &.{ "--", glyph })
    else
        qt6.QProcess.StartDetached22(app.allocator, "xdotool", &.{ "type", "--clearmodifiers", "--", glyph });

    if (!ok) {
        copyToClipboard(app, glyph);
        return;
    }
    app.exit_code = 0;
    _ = app.ui.main.Close();
}
