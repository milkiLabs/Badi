// Emoji mode: the user has selected an emoji. Routes the glyph to the
// configured action:
//   .copy      — clipboard (wl-copy → stdout fallback)
//   .print     — write the glyph to stdout (dmenu-style), exit 0
//   .type_keys — synthesize keystrokes via wtype (→ wl-copy fallback)
//
// The window is closed after each action so the WM can route the glyph
// (clipboard or keystrokes) to the previously-focused app. `exit_code`
// is set based on what actually succeeded, never before.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../state/mod.zig");
const util = @import("util.zig");

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
    util.writeStdout(app, "{s}", .{glyph});
    app.exit_code = code;
    _ = app.ui.main.Close();
}

/// Synthesizes the glyph as keystrokes via `wtype`. Badi is itself
/// focused while running, so we close it first; the WM restores
/// focus to whatever app was focused before Badi opened (the
/// terminal, the text editor, etc.), and wtype types the glyph there.
///
/// If `wtype` is not installed, falls back to the clipboard. The
/// `exit_code` is set only after a real action succeeds — a bare
/// "close + exit 0" would lie when neither tool is available.
fn typeKeysAndExit(app: *state.AppState, glyph: []const u8) void {
    // Close first so focus is restored to the previously-focused app
    // before wtype types there.
    _ = app.ui.main.Close();

    if (qt6.QProcess.StartDetached22(app.allocator, "wtype", &.{ "--", glyph })) {
        app.exit_code = 0;
        return;
    }

    if (qt6.QProcess.StartDetached22(app.allocator, "wl-copy", &.{glyph})) {
        app.exit_code = 0;
        return;
    }

    std.log.warn("emoji: neither wtype nor wl-copy available — glyph discarded", .{});
    app.exit_code = 1;
}
