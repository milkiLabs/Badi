// Public surface of the config module.

pub const Action = @import("actions.zig").Action;
pub const Config = @import("actions.zig").Config;
pub const Theme = @import("theme.zig").Theme;

pub const loadActions = @import("actions.zig").load;
pub const loadTheme = @import("theme.zig").load;
pub const generateQss = @import("style.zig").generateQss;
pub const resolveConfigDir = @import("paths.zig").resolve;
