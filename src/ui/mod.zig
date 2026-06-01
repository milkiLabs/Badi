// Public surface of the UI module. Importers should `@import("ui")`,
// not reach into individual files.

pub const Widgets = @import("../state/widgets.zig").Widgets;
pub const factory = @import("factory.zig");
pub const model = @import("model.zig");
pub const view = @import("view.zig");
pub const status = @import("status.zig");
pub const piped_view = @import("piped_view.zig");
pub const callbacks = @import("callbacks/mod.zig");
pub const wayland = @import("wayland.zig");
