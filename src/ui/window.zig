const std = @import("std");
const qt6 = @import("libqt6zig");
const context = @import("../context.zig");

/// Rebuilds the backing Qt rows when the list is stale.
pub fn rebuildList() void {
    const app = context.state();
    app.ui.list.Clear();

    app.ui.list.SetUpdatesEnabled(false);
    defer app.ui.list.SetUpdatesEnabled(true);

    switch (app.mode) {
        .apps => {
            for (app.apps()) |entry| addListItem(entry.name, entry.exec);
        },
        .piped => {
            for (app.piped_items.items) |line| addListItem(line, line);
        },
        .prefix => {},
    }

    app.list_dirty = false;
}

/// Filters existing rows in place instead of rebuilding them on every keypress.
pub fn filterList(query: []const u8) void {
    const app = context.state();

    // Suppress per-row repaints; Qt will repaint once after we re-enable.
    app.ui.list.SetUpdatesEnabled(false);
    defer app.ui.list.SetUpdatesEnabled(true);

    var shown: i32 = 0;
    switch (app.mode) {
        .apps => {
            if (app.list_dirty) rebuildList();
            for (app.apps(), 0..) |entry, row| {
                if (setRowVisible(@intCast(row), entry.name, query)) shown += 1;
            }
        },
        .piped => {
            if (app.list_dirty) rebuildList();
            for (app.piped_items.items, 0..) |line, row| {
                if (setRowVisible(@intCast(row), line, query)) shown += 1;
            }
        },
        .prefix => |cfg| shown = updatePrefixRow(cfg, query),
    }

    if (shown == 0) {
        app.ui.no_results.Show();
        return;
    }

    selectFirstVisible();
    app.ui.no_results.Hide();
}

pub fn selectRelative(direction: i32) void {
    const app = context.state();
    const count = app.ui.list.Count();
    if (count == 0) return;

    var row = app.ui.list.CurrentRow();
    if (row < 0) row = if (direction >= 0) -1 else count;

    var next = row + direction;
    while (next >= 0 and next < count) : (next += direction) {
        if (!app.ui.list.IsRowHidden(next)) {
            app.ui.list.SetCurrentRow(next);
            return;
        }
    }
}

/// Shows or hides a row based on whether text matches the query.
fn setRowVisible(row: i32, text: []const u8, query: []const u8) bool {
    const app = context.state();
    const visible = query.len == 0 or std.ascii.indexOfIgnoreCase(text, query) != null;
    app.ui.list.SetRowHidden(@intCast(row), !visible);
    return visible;
}

pub fn appendPipedItem(line: []const u8) !void {
    const app = context.state();
    errdefer app.allocator.free(line);
    try app.piped_items.append(app.allocator, line);

    if (app.mode != .piped) return;
    if (app.list_dirty) rebuildList();

    addListItem(line, line);

    // Hide "no results" — we have at least one item.
    app.ui.no_results.Hide();
}

fn updatePrefixRow(cfg: context.Action, query: []const u8) i32 {
    const app = context.state();
    app.ui.list.Clear();

    if (query.len == 0) return 0;

    const item = qt6.QListWidgetItem.New();
    const display_text = std.fmt.allocPrint(app.allocator, "Run {s}: {s}", .{ cfg.name, query }) catch return 0;
    defer app.allocator.free(display_text);
    item.SetText(display_text);
    app.ui.list.AddItem2(item);
    return 1;
}

fn selectFirstVisible() void {
    const app = context.state();
    const count = app.ui.list.Count();
    var row: i32 = 0;
    while (row < count) : (row += 1) {
        if (!app.ui.list.IsRowHidden(row)) {
            app.ui.list.SetCurrentRow(row);
            return;
        }
    }
}

fn addListItem(label: []const u8, data: []const u8) void {
    const app = context.state();
    const item = qt6.QListWidgetItem.New();
    item.SetText(label);

    const variant = qt6.QVariant.New24(data);
    defer variant.Delete();
    item.SetData(context.UserRole, variant);

    app.ui.list.AddItem2(item);
}

pub fn resetToMainList() void {
    const app = context.state();
    if (app.mode == .prefix) return;

    if (app.list_dirty) {
        rebuildList();
    } else {
        filterList("");
    }
}
