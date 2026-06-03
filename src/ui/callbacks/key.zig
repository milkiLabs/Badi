// Key-press callback. Maps the four-arrow-keys + Enter + Escape + Ctrl-W
// + Backspace set onto the active mode. Mode-aware Backspace/Ctrl-W
// exits prefix/url mode when the input is empty.

const std = @import("std");
const qt6 = @import("libqt6zig");
const state = @import("../../state/mod.zig");
const modes = @import("../../modes/mod.zig");
const view = @import("../view.zig");
const helpers = @import("helpers.zig");

const qk = qt6.qnamespace_enums.Key;
const km = qt6.qnamespace_enums.KeyboardModifier;

pub fn onKeyPress(self: qt6.QLineEdit, event: qt6.QKeyEvent) callconv(.c) void {
    const app = state.global.assertGet();
    const key = event.Key();
    const ctrl = (event.Modifiers() & km.ControlModifier) != 0;

    if (key == qk.Key_Escape) {
        if (canExitToApps(app.mode)) {
            helpers.exitToApps(app);
        } else if (isCancelable(app.mode)) {
            // Escape cancels the prompt/emoji/pipe — exit code 1 signals "no answer".
            app.exit_code = 1;
            _ = app.ui.main.Close();
        } else {
            _ = app.ui.main.Close();
        }
        event.Accept();
    } else if (key == qk.Key_Return or key == qk.Key_Enter) {
        modes.dispatch(app);
        event.Accept();
    } else if (key == qk.Key_Up) {
        view.selectRelative(app, -1);
        event.Accept();
    } else if (key == qk.Key_Down) {
        view.selectRelative(app, 1);
        event.Accept();
    } else if (ctrl and key == qk.Key_W) {
        if (tryExitOnEmpty(self, app)) {
            event.Accept();
            return;
        }
        self.CursorWordBackward(true);
        self.Del();
        event.Accept();
    } else if (key == qk.Key_Backspace) {
        if (tryExitOnEmpty(self, app)) {
            event.Accept();
            return;
        }
        self.SuperKeyPressEvent(event);
    } else {
        self.SuperKeyPressEvent(event);
    }
}

/// True if the current mode is one of the "back to apps" mid-session modes
/// (prefix/url/emoji entered via the ": " trigger). Used by Escape,
/// Backspace, and Ctrl-W to decide whether to drop back to apps or close
/// the window. Emoji mode entered via --emoji does not count — Esc
/// closes the app (see `isCancelable`).
fn canExitToApps(mode: state.AppMode) bool {
    return switch (mode) {
        .prefix, .url => true,
        .emoji => |cfg| cfg.entry == .trigger,
        else => false,
    };
}

/// True if the current mode is canceled by Esc/Backspace/Ctrl-W with
/// exit code 1. Currently prompt, piped, and emoji-launched-via-CLI.
fn isCancelable(mode: state.AppMode) bool {
    return switch (mode) {
        .prompt, .piped => true,
        .emoji => |cfg| cfg.entry == .cli,
        else => false,
    };
}

/// Returns true and frees the temporary buffer if the input field is empty.
fn inputIsEmpty(self: qt6.QLineEdit, app: *state.AppState) bool {
    const text = self.Text(app.allocator);
    defer app.allocator.free(text);
    return text.len == 0;
}

/// Shared by Ctrl+W and Backspace: if the input is empty, exit to apps
/// (when the mode allows it) and report the event as handled. The caller
/// still has to `event.Accept()` in both branches — this only reports
/// whether the key was consumed.
fn tryExitOnEmpty(self: qt6.QLineEdit, app: *state.AppState) bool {
    if (!inputIsEmpty(self, app)) return false;
    if (canExitToApps(app.mode)) helpers.exitToApps(app);
    return true;
}
