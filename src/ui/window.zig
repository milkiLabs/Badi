const std = @import("std");
const qt6 = @import("libqt6zig");
const context = @import("../context.zig");

const max_rendered_rows = 128;

pub const Selection = struct {
    data: []const u8,
};

/// Recomputes the filtered source rows and renders only the selectable window.
pub fn filterList(query: []const u8) void {
    const app = context.state();

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
        .prefix => |cfg| {
            renderPrefixRow(cfg, query);
            return;
        },
    }

    if (app.visible_indices.items.len == 0) {
        clearRenderedRows();
        app.ui.no_results.Show();
        return;
    }

    app.selected_index = 0;
    renderVisibleRows();
    app.ui.no_results.Hide();
}

pub fn selectRelative(direction: i32) void {
    const app = context.state();
    if (app.visible_indices.items.len == 0) return;

    const current = app.selected_index orelse 0;
    const next = if (direction < 0) blk: {
        if (current == 0) return;
        break :blk current - 1;
    } else blk: {
        if (current + 1 >= app.visible_indices.items.len) return;
        break :blk current + 1;
    };

    app.selected_index = next;
    renderVisibleRows();
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
    if (app.mode != .piped or app.visible_indices.items.len == 0) return;
    if (app.selected_index == null) app.selected_index = 0;
    renderVisibleRows();
    app.ui.no_results.Hide();
}

pub fn syncSelectionFromRenderedRow(row: i32) void {
    if (row < 0) return;
    const app = context.state();
    const rendered_start = renderedStart();
    const selected = rendered_start + @as(usize, @intCast(row));
    if (selected < app.visible_indices.items.len) {
        app.selected_index = selected;
    }
}

pub fn currentSelection() ?Selection {
    const app = context.state();
    syncSelectionFromRenderedRow(app.ui.list.CurrentRow());

    switch (app.mode) {
        .apps => {
            const source_index = selectedSourceIndex() orelse return null;
            const entry = app.apps()[source_index];
            return .{ .data = entry.exec };
        },
        .piped => {
            const source_index = selectedSourceIndex() orelse return null;
            const line = app.piped_items.items[source_index];
            return .{ .data = line };
        },
        .prefix => return null,
    }
}

pub fn resetToMainList() void {
    const app = context.state();
    if (app.mode == .prefix) return;
    filterList("");
}

fn renderVisibleRows() void {
    const app = context.state();
    const selected = app.selected_index orelse 0;
    const start = renderedStart();
    const end = @min(app.visible_indices.items.len, start + max_rendered_rows);

    app.ui.list.SetUpdatesEnabled(false);
    defer app.ui.list.SetUpdatesEnabled(true);

    app.ui.list.Clear();
    for (app.visible_indices.items[start..end]) |source_index| {
        switch (app.mode) {
            .apps => {
                const entry = app.apps()[source_index];
                addListItem(entry.name);
            },
            .piped => addListItem(app.piped_items.items[source_index]),
            .prefix => {},
        }
    }

    if (selected >= start and selected < end) {
        app.ui.list.SetCurrentRow(@intCast(selected - start));
    }
}

fn renderPrefixRow(cfg: context.Action, query: []const u8) void {
    const app = context.state();

    clearRenderedRows();
    if (query.len == 0) {
        app.ui.no_results.Show();
        return;
    }

    const display_text = std.fmt.allocPrint(app.allocator, "Run {s}: {s}", .{ cfg.name, query }) catch return;
    defer app.allocator.free(display_text);
    addListItem(display_text);
    app.ui.list.SetCurrentRow(0);
    app.ui.no_results.Hide();
}

fn renderedStart() usize {
    const app = context.state();
    const selected = app.selected_index orelse 0;
    const len = app.visible_indices.items.len;
    if (len <= max_rendered_rows or selected < max_rendered_rows) return 0;
    return @min(selected - max_rendered_rows + 1, len - max_rendered_rows);
}

fn selectedSourceIndex() ?usize {
    const app = context.state();
    const selected = app.selected_index orelse return null;
    if (selected >= app.visible_indices.items.len) return null;
    return app.visible_indices.items[selected];
}

fn matches(text: []const u8, query: []const u8) bool {
    return query.len == 0 or std.ascii.indexOfIgnoreCase(text, query) != null;
}

fn clearRenderedRows() void {
    const app = context.state();
    app.ui.list.Clear();
}

fn addListItem(label: []const u8) void {
    const app = context.state();
    app.ui.list.AddItem2(qt6.QListWidgetItem.New2(label));
}
