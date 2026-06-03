// Badi's operating mode. One variant per behavior; the variant's payload
// carries the data that mode needs. Each variant is implemented by a file
// in `modes/` (launch behavior), `ui/model.zig` (render), and
// `ui/callbacks/` (text/key input handling). Adding a new mode = add a
// variant here + add a `modes/<name>.zig` + add cases to the small
// dispatch switches in ui/model.zig, ui/view.zig, and ui/status.zig.

const config = @import("../config/mod.zig");

/// Configuration for the free-form text prompt (--prompt mode).
/// `default_value` is pre-filled and selected; `password` masks input;
/// `allow_empty` permits Enter on an empty input.
pub const PromptConfig = struct {
    label: []const u8,
    default_value: []const u8,
    password: bool,
    allow_empty: bool,
};

/// What to do with the selected emoji when Enter is pressed in emoji mode.
pub const EmojiAction = enum {
    /// Copy the glyph to the system clipboard (default).
    copy,
    /// Write the glyph to stdout — dmenu-style. Exit code 0 on select, 1 on cancel.
    print,
    /// Synthesize keystrokes into the focused window via wtype / xdotool.
    type_keys,
};

/// How the user entered emoji mode. Determines the exit behavior on
/// Escape / Ctrl-W / Backspace:
///   .cli     — entered via `--emoji` flag: like piped/prompt, Esc closes
///              the window with exit code 1 (no answer).
///   .trigger — entered via the `": "` mid-session trigger: Esc/backspace
///              returns to apps mode (the original mid-session behavior).
pub const EmojiEntry = enum {
    cli,
    trigger,
};

/// Configuration for emoji mode (--emoji). `action` defaults to copy
/// when unset, matching rofimoji / wofi-emoji. `entry` records how
/// the user got into emoji mode and is set by the CLI parser or by
/// the mid-session trigger helper.
pub const EmojiConfig = struct {
    action: EmojiAction = .copy,
    entry: EmojiEntry = .trigger,
};

pub const AppMode = union(enum(u8)) {
    /// Default: scan .desktop files, search and launch.
    apps: void,
    /// stdin is a pipe: stream lines, filter, print selection to stdout.
    piped: void,
    /// User typed a configured trigger (e.g. "g "): run a shell template.
    prefix: config.Action,
    /// User typed something that looks like a URL: open with xdg-open.
    url: void,
    /// --prompt was passed: free-form input, written to stdout.
    prompt: PromptConfig,
    /// --emoji was passed (or ": " trigger from apps): emoji palette.
    emoji: EmojiConfig,

    /// True if this mode backs the list widget with a real source slice
    /// (apps, piped, or emoji items). Prefix/url/prompt are synthetic single-row.
    pub fn hasListSource(self: AppMode) bool {
        return switch (self) {
            .apps, .piped, .emoji => true,
            .prefix, .url, .prompt => false,
        };
    }

    /// True if the mode shows a badge (prefix/url/emoji/prompt with a label).
    pub fn hasBadge(self: AppMode) bool {
        return switch (self) {
            .prefix, .url, .emoji => true,
            .prompt => |cfg| cfg.label.len > 0,
            .apps, .piped => false,
        };
    }
};
