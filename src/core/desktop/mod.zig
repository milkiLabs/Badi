// Public surface of the desktop module.

pub const DesktopEntry = @import("entry.zig").DesktopEntry;
pub const DesktopAppList = @import("entry.zig").DesktopAppList;
pub const nameOf = @import("entry.zig").nameOf;
pub const loadDesktopApps = @import("loader.zig").load;
pub const parseDesktopFile = @import("parser.zig").parse;
