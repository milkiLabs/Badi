const plugin = @import("../plugins/api.zig");

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

/// The currently active mode is an instance of a registered plugin plus
/// optional plugin-owned context. Adding a new native mode means registering
/// another `plugins.api.Mode`; it does not require extending this type.
pub const AppMode = plugin.ActiveMode;
