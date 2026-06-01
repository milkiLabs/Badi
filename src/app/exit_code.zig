// Exit code resolution. After the Qt event loop exits, this is the single
// place that decides the process exit code based on the final AppState.

const state = @import("../state/mod.zig");

/// Returns the process exit code. If the user selected something, the
/// mode's launch function set `exit_code` to 0. Otherwise, we fall back
/// to a sensible default per mode: piped/prompt/emoji without a selection
/// → 1 (cancelled); apps/prefix/url without a selection → 0 (window
/// closed normally). Emoji is grouped with piped/prompt because the user
/// explicitly invoked a sub-mode — closing without picking is a cancel.
pub fn resolve(app: *const state.AppState) u8 {
    if (app.exit_code) |code| return code;
    return switch (app.mode) {
        .piped, .prompt, .emoji => 1,
        .apps, .prefix, .url => 0,
    };
}
