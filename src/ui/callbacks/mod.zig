// Public surface of the callbacks module. The factory imports this and
// binds each function to the appropriate Qt signal.

pub const onTextChanged = @import("text.zig").onTextChanged;
pub const onKeyPress = @import("key.zig").onKeyPress;
pub const onInputFocusOut = @import("focus.zig").onInputFocusOut;
pub const onFocusGuardTimeout = @import("focus.zig").onFocusGuardTimeout;
pub const onItemDoubleClicked = @import("click.zig").onItemDoubleClicked;
pub const onStdinActivated = @import("piped.zig").onStdinActivated;
pub const onReplacementRequested = @import("replacement.zig").onReplacementRequested;
