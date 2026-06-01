// Emoji mode: the user has selected an emoji. Routes the glyph to the
// configured action:
//   .copy      — clipboard (wl-copy → stdout fallback)
//   .print     — write the glyph to stdout (dmenu-style), exit 0
//   .type_keys — synthesize keystrokes via wtype
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

/// Copies the glyph to the system clipboard via `wl-copy` (from
/// wl-clipboard). The Wayland data-device protocol is pull-based — the
/// source app must stay alive to serve pastes — but `wl-copy` runs as
/// a daemon and persists after Badi exits. If `wl-copy` is not
/// installed, falls back to writing the glyph to stdout so the picker
/// is still useful in a pipeline.
fn copyToClipboard(app: *state.AppState, glyph: []const u8) void {
    if (qt6.QProcess.StartDetached22(app.allocator, "wl-copy", &.{glyph})) {
        app.exit_code = 0;
        _ = app.ui.main.Close();
        return;
    }
    writeStdoutAndExit(app, glyph, 0);
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

/// Synthesizes the glyph as keystrokes via `wtype`. Badi is itself
/// focused while running, so we close it first; the WM restores
/// focus to whatever app was focused before Badi opened (the
/// terminal, the text editor, etc.), and wtype types the glyph there.
///
/// If `wtype` is not installed, falls back to the clipboard.
fn typeKeysAndExit(app: *state.AppState, glyph: []const u8) void {
    app.exit_code = 0;
    _ = app.ui.main.Close();

    if (!qt6.QProcess.StartDetached22(app.allocator, "wtype", &.{ "--", glyph })) {
        copyToClipboard(app, glyph);
    }
}
