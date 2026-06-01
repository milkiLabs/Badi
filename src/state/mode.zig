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

pub const AppMode = union(enum) {
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

    /// True if this mode backs the list widget with a real source slice
    /// (apps or piped items). Prefix/url/prompt are synthetic single-row.
    pub fn hasListSource(self: AppMode) bool {
        return switch (self) {
            .apps, .piped => true,
            .prefix, .url, .prompt => false,
        };
    }

    /// True if the mode shows a badge (prefix/url/prompt with a label).
    pub fn hasBadge(self: AppMode) bool {
        return switch (self) {
            .prefix, .url => true,
            .prompt => |cfg| cfg.label.len > 0,
            .apps, .piped => false,
        };
    }
};
