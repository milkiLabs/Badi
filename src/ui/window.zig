const std = @import("std");
const qt6 = @import("libqt6zig");
const context = @import("../context.zig");

const display_role = qt6.qnamespace_enums.ItemDataRole.DisplayRole;

pub const Selection = struct {
    data: []const u8,
};

pub fn onModelRowCount(_: qt6.QAbstractListModel, parent: qt6.QModelIndex) callconv(.c) i32 {
    if (parent.IsValid()) return 0;

    const app = context.state();
    return switch (app.mode) {
        .prefix => if (prefixQuery().len == 0) 0 else 1,
        else => @intCast(app.visible_indices.items.len),
    };
}

pub fn onModelData(_: qt6.QAbstractListModel, index: qt6.QModelIndex, role: i32) callconv(.c) qt6.QVariant {
    if (role != display_role or !index.IsValid()) return qt6.QVariant.New();

    const row = index.Row();
    if (row < 0) return qt6.QVariant.New();

    const app = context.state();
    switch (app.mode) {
        .apps => {
            const source_index = sourceIndexFromModelRow(row) orelse return qt6.QVariant.New();
            return qt6.QVariant.New24(app.apps()[source_index].name);
        },
        .piped => {
            const source_index = sourceIndexFromModelRow(row) orelse return qt6.QVariant.New();
            return qt6.QVariant.New24(app.piped_items.items[source_index]);
        },
        .prefix => |cfg| {
            const query = prefixQuery();
            if (row != 0 or query.len == 0) return qt6.QVariant.New();
            const display_text = std.fmt.allocPrint(app.allocator, "Run {s}: {s}", .{ cfg.name, query }) catch return qt6.QVariant.New();
            defer app.allocator.free(display_text);
            return qt6.QVariant.New24(display_text);
        },
    }
}

/// Recomputes the filtered source rows and asks Qt's model-view layer to repaint.
pub fn filterList(query: []const u8) void {
    const app = context.state();

    app.ui.model.BeginResetModel();

    app.current_query.clearRetainingCapacity();
    app.current_query.appendSlice(app.allocator, query) catch {};
    app.visible_indices.clearRetainingCapacity();
    app.selected_index = null;

    switch (app.mode) {
        .apps => {
            for (app.apps(), 0..) |entry, source_index| {
                if (matches(entry.name, query)) {
                    app.visible_indices.append(app.allocator, source_index) catch break;
                }
            }
        },
        .piped => {
            for (app.piped_items.items, 0..) |line, source_index| {
                if (matches(line, query)) {
                    app.visible_indices.append(app.allocator, source_index) catch break;
                }
            }
        },
        .prefix => {},
    }

    const has_results = switch (app.mode) {
        .prefix => query.len > 0,
        else => app.visible_indices.items.len > 0,
    };

    if (has_results) {
        app.selected_index = 0;
        app.ui.no_results.Hide();
    } else {
        app.ui.no_results.Show();
    }

    app.ui.model.EndResetModel();
    if (has_results) selectModelRow(0);
}

pub fn selectRelative(direction: i32) void {
    const app = context.state();
    const len = resultCount();
    if (len == 0) return;

    const current = currentModelRow() orelse 0;
    const next = if (direction < 0) blk: {
        if (current == 0) return;
        break :blk current - 1;
    } else blk: {
        if (current + 1 >= len) return;
        break :blk current + 1;
    };

    selectModelRow(next);
    app.selected_index = next;
}

pub fn appendPipedItem(line: []const u8) !void {
    const app = context.state();
    errdefer app.allocator.free(line);
    try app.piped_items.append(app.allocator, line);

    if (app.mode != .piped) return;

    const query = app.ui.input.Text(app.allocator);
    defer app.allocator.free(query);
    if (!matches(line, query)) return;

    try app.visible_indices.append(app.allocator, app.piped_items.items.len - 1);
    if (app.selected_index == null) app.selected_index = 0;
}

pub fn renderPipedAppendBatch() void {
    const app = context.state();
    if (app.mode != .piped) return;

    app.ui.model.BeginResetModel();
    app.ui.model.EndResetModel();

    if (app.visible_indices.items.len == 0) {
        app.ui.no_results.Show();
        return;
    }

    app.ui.no_results.Hide();
    selectModelRow(app.selected_index orelse 0);
}

pub fn syncSelectionFromIndex(index: qt6.QModelIndex) void {
    if (!index.IsValid()) return;

    const row = index.Row();
    if (row < 0) return;

    const app = context.state();
    const selected: usize = @intCast(row);
    if (selected < resultCount()) {
        app.selected_index = selected;
    }
}

pub fn currentSelection() ?Selection {
    const app = context.state();
    const current_index = app.ui.list.CurrentIndex();
    defer current_index.Delete();
    syncSelectionFromIndex(current_index);

    switch (app.mode) {
        .apps => {
            const source_index = selectedSourceIndex() orelse return null;
            return .{ .data = app.apps()[source_index].exec };
        },
        .piped => {
            const source_index = selectedSourceIndex() orelse return null;
            return .{ .data = app.piped_items.items[source_index] };
        },
        .prefix => return null,
    }
}

pub fn resetToMainList() void {
    const app = context.state();
    if (app.mode == .prefix) return;
    filterList("");
    selectModelRow(0);
}

fn selectModelRow(row: usize) void {
    const app = context.state();
    if (row >= resultCount()) return;

    const parent = qt6.QModelIndex.New3();
    defer parent.Delete();
    const index = app.ui.model.Index(@intCast(row), 0, parent);
    defer index.Delete();

    app.ui.list.SetCurrentIndex(index);
    app.ui.list.ScrollTo(index, qt6.qabstractitemview_enums.ScrollHint.EnsureVisible);
}

fn currentModelRow() ?usize {
    const app = context.state();
    const index = app.ui.list.CurrentIndex();
    defer index.Delete();

    if (!index.IsValid()) return app.selected_index;
    const row = index.Row();
    if (row < 0) return app.selected_index;
    return @intCast(row);
}

fn selectedSourceIndex() ?usize {
    const app = context.state();
    const selected = app.selected_index orelse currentModelRow() orelse return null;
    return sourceIndexFromModelRow(@intCast(selected));
}

fn sourceIndexFromModelRow(row: i32) ?usize {
    if (row < 0) return null;

    const app = context.state();
    const selected: usize = @intCast(row);
    if (selected >= app.visible_indices.items.len) return null;
    return app.visible_indices.items[selected];
}

fn resultCount() usize {
    const app = context.state();
    return switch (app.mode) {
        .prefix => if (prefixQuery().len == 0) 0 else 1,
        else => app.visible_indices.items.len,
    };
}

fn prefixQuery() []const u8 {
    const app = context.state();
    return app.current_query.items;
}

fn matches(text: []const u8, query: []const u8) bool {
    return query.len == 0 or std.ascii.indexOfIgnoreCase(text, query) != null;
}
