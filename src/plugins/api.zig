const qt6 = @import("libqt6zig");

pub const Context = ?*const anyopaque;

pub const TextResult = enum {
    handled,
    continue_filter,
};

pub const SelectionSource = enum {
    none,
    apps,
    piped,
    emoji,
};

pub const Mode = struct {
    id: []const u8,
    name: []const u8,
    placeholder: []const u8,
    has_list_source: bool,
    selection_source: SelectionSource = .none,

    badgeText: ?*const fn (app: *anyopaque, ctx: Context) ?[]const u8 = null,
    emptyText: ?*const fn (app: *const anyopaque, ctx: Context) []const u8 = null,
    resultCount: *const fn (app: *const anyopaque, ctx: Context) usize,
    displayRow: *const fn (app: *anyopaque, ctx: Context, row: i32) qt6.QVariant,
    filter: *const fn (app: *anyopaque, ctx: Context, query: []const u8) void,
    launch: *const fn (app: *anyopaque, ctx: Context) void,
    onTextChanged: ?*const fn (app: *anyopaque, ctx: Context, query: []const u8) TextResult = null,
    beforeEnter: ?*const fn (app: *anyopaque, ctx: Context) bool = null,
    canExitToDefault: ?*const fn (app: *const anyopaque, ctx: Context) bool = null,
    isCancelable: ?*const fn (app: *const anyopaque, ctx: Context) bool = null,
    singleInstance: bool = false,
};

pub const ActiveMode = struct {
    plugin: *const Mode,
    ctx: Context = null,
};

pub const Trigger = struct {
    text: []const u8,
    mode: ActiveMode,
};

pub const Registry = struct {
    modes: []const *const Mode,
    triggers: []const Trigger,
};

pub fn defaultResultCount(_: *const anyopaque, _: Context) usize {
    return 0;
}

pub fn emptyDisplayRow(_: *anyopaque, _: Context, _: i32) qt6.QVariant {
    return qt6.QVariant.New();
}

pub fn noFilter(_: *anyopaque, _: Context, _: []const u8) void {}

pub fn noLaunch(_: *anyopaque, _: Context) void {}
