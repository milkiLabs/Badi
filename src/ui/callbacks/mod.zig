// Public surface of the callbacks module. The factory imports this and
// binds each function to the appropriate Qt signal.

pub const onTextChanged = @import("text.zig").onTextChanged;
pub const onKeyPress = @import("key.zig").onKeyPress;
pub const onItemDoubleClicked = @import("click.zig").onItemDoubleClicked;
pub const onStdinActivated = @import("piped.zig").onStdinActivated;
