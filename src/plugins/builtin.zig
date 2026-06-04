const std = @import("std");
const qt6 = @import("libqt6zig");
const api = @import("api.zig");
const state = @import("../state/mod.zig");
const config = @import("../config/mod.zig");
const core = @import("../core/mod.zig");
const url_util = @import("../utils/url.zig");
const mode_util = @import("util.zig");
const transitions = @import("transitions.zig");

const placeholder_token = "%s";
const https_prefix = "https://";
const emoji_trigger = ": ";

pub const apps = api.Mode{
    .id = "apps",
    .name = "Apps",
    .placeholder = "Search apps...",
    .has_list_source = true,
    .selection_source = .apps,
    .emptyText = appsEmptyText,
    .resultCount = visibleResultCount,
    .displayRow = appsDisplayRow,
    .filter = appsFilter,
    .launch = appsLaunch,
    .onTextChanged = appsTextChanged,
    .singleInstance = true,
};

pub const piped = api.Mode{
    .id = "piped",
    .name = "Piped",
    .placeholder = "Search...",
    .has_list_source = true,
    .selection_source = .piped,
    .emptyText = pipedEmptyText,
    .resultCount = visibleResultCount,
    .displayRow = pipedDisplayRow,
    .filter = pipedFilter,
    .launch = pipedLaunch,
    .isCancelable = alwaysTrueConst,
};

pub const action = api.Mode{
    .id = "action",
    .name = "Action",
    .placeholder = "Type to search or run...",
    .has_list_source = false,
    .badgeText = actionBadgeText,
    .resultCount = syntheticResultCount,
    .displayRow = actionDisplayRow,
    .filter = api.noFilter,
    .launch = actionLaunch,
    .canExitToDefault = alwaysTrueConst,
};

pub const url = api.Mode{
    .id = "url",
    .name = "URL",
    .placeholder = "Type a URL...",
    .has_list_source = false,
    .badgeText = urlBadgeText,
    .resultCount = syntheticResultCount,
    .displayRow = urlDisplayRow,
    .filter = api.noFilter,
    .launch = urlLaunch,
    .onTextChanged = urlTextChanged,
    .canExitToDefault = alwaysTrueConst,
};

pub const prompt = api.Mode{
    .id = "prompt",
    .name = "Prompt",
    .placeholder = "",
    .has_list_source = false,
    .badgeText = promptBadgeText,
    .resultCount = api.defaultResultCount,
    .displayRow = api.emptyDisplayRow,
    .filter = promptFilter,
    .launch = promptLaunch,
    .onTextChanged = promptTextChanged,
    .isCancelable = alwaysTrueConst,
};

pub const emoji = api.Mode{
    .id = "emoji",
    .name = "Emoji",
    .placeholder = "Search emojis...",
    .has_list_source = true,
    .selection_source = .emoji,
    .badgeText = emojiBadgeText,
    .emptyText = emojiEmptyText,
    .resultCount = visibleResultCount,
    .displayRow = emojiDisplayRow,
    .filter = emojiFilter,
    .launch = emojiLaunch,
    .beforeEnter = emojiBeforeEnter,
    .canExitToDefault = emojiCanExitToDefault,
    .isCancelable = emojiIsCancelable,
    .singleInstance = true,
};

pub const all = [_]*const api.Mode{
    &apps,
    &piped,
    &action,
    &url,
    &prompt,
    &emoji,
};

pub fn modeById(id: []const u8) ?*const api.Mode {
    for (all) |mode| {
        if (std.mem.eql(u8, mode.id, id)) return mode;
    }
    return null;
}

fn appPtr(app_opaque: *anyopaque) *state.AppState {
    return @ptrCast(@alignCast(app_opaque));
}

fn constAppPtr(app_opaque: *const anyopaque) *const state.AppState {
    return @ptrCast(@alignCast(app_opaque));
}

fn actionPtr(ctx: api.Context) *const config.Action {
    return @ptrCast(@alignCast(ctx.?));
}

fn promptPtr(ctx: api.Context) *const state.PromptConfig {
    return @ptrCast(@alignCast(ctx.?));
}

fn emojiPtr(ctx: api.Context) *const state.EmojiConfig {
    return @ptrCast(@alignCast(ctx.?));
}

fn alwaysTrueConst(_: *const anyopaque, _: api.Context) bool {
    return true;
}

fn visibleResultCount(app_opaque: *const anyopaque, _: api.Context) usize {
    return constAppPtr(app_opaque).visible_indices.items.len;
}

fn syntheticResultCount(app_opaque: *const anyopaque, _: api.Context) usize {
    return if (constAppPtr(app_opaque).current_query.items.len > 0) 1 else 0;
}

fn appsEmptyText(_: *const anyopaque, _: api.Context) []const u8 {
    return "No apps found";
}

fn pipedEmptyText(app_opaque: *const anyopaque, _: api.Context) []const u8 {
    const app = constAppPtr(app_opaque);
    if (!app.stdin_eof) return "Waiting for input...";
    if (app.piped_items.items.len == 0) return "No input";
    return "No results";
}

fn emojiEmptyText(_: *const anyopaque, _: api.Context) []const u8 {
    return "No emoji found";
}

fn actionBadgeText(app_opaque: *anyopaque, ctx: api.Context) ?[]const u8 {
    const app = appPtr(app_opaque);
    const cfg = actionPtr(ctx);
    return std.fmt.allocPrint(app.allocator, "{s} {s}", .{ cfg.icon, cfg.name }) catch null;
}

fn urlBadgeText(_: *anyopaque, _: api.Context) ?[]const u8 {
    return "🌐 Browser";
}

fn promptBadgeText(_: *anyopaque, ctx: api.Context) ?[]const u8 {
    const cfg = promptPtr(ctx);
    return if (cfg.label.len > 0) cfg.label else null;
}

fn emojiBadgeText(_: *anyopaque, _: api.Context) ?[]const u8 {
    return "😀 Emoji";
}

fn appsDisplayRow(app_opaque: *anyopaque, _: api.Context, row: i32) qt6.QVariant {
    const app = appPtr(app_opaque);
    const src = sourceIndexFromRow(app, row) orelse return qt6.QVariant.New();
    return qt6.QVariant.New24(app.apps()[src].name);
}

fn pipedDisplayRow(app_opaque: *anyopaque, _: api.Context, row: i32) qt6.QVariant {
    const app = appPtr(app_opaque);
    const src = sourceIndexFromRow(app, row) orelse return qt6.QVariant.New();
    return qt6.QVariant.New24(app.piped_items.items[src]);
}

fn emojiDisplayRow(app_opaque: *anyopaque, _: api.Context, row: i32) qt6.QVariant {
    const app = appPtr(app_opaque);
    const src = sourceIndexFromRow(app, row) orelse return qt6.QVariant.New();
    const e = app.emojiEntries()[src];
    const text = std.fmt.allocPrint(app.allocator, "{s}  {s}", .{ e.glyph, e.name }) catch return qt6.QVariant.New();
    defer app.allocator.free(text);
    return qt6.QVariant.New24(text);
}

fn actionDisplayRow(app_opaque: *anyopaque, ctx: api.Context, row: i32) qt6.QVariant {
    const app = appPtr(app_opaque);
    if (row != 0 or app.current_query.items.len == 0) return qt6.QVariant.New();
    const cfg = actionPtr(ctx);
    const text = std.fmt.allocPrint(app.allocator, "Run {s}: {s}", .{ cfg.name, app.current_query.items }) catch return qt6.QVariant.New();
    defer app.allocator.free(text);
    return qt6.QVariant.New24(text);
}

fn urlDisplayRow(app_opaque: *anyopaque, _: api.Context, row: i32) qt6.QVariant {
    const app = appPtr(app_opaque);
    if (row != 0 or app.current_query.items.len == 0) return qt6.QVariant.New();
    const text = std.fmt.allocPrint(app.allocator, "Open in browser: {s}", .{app.current_query.items}) catch return qt6.QVariant.New();
    defer app.allocator.free(text);
    return qt6.QVariant.New24(text);
}

fn sourceIndexFromRow(app: *state.AppState, row: i32) ?usize {
    if (row < 0) return null;
    const idx: usize = @intCast(row);
    if (idx >= app.visible_indices.items.len) return null;
    return app.visible_indices.items[idx];
}

fn appsFilter(app_opaque: *anyopaque, _: api.Context, query: []const u8) void {
    const app = appPtr(app_opaque);
    const source = app.apps();
    if (source.len == 0) return;

    app.visible_indices.ensureTotalCapacity(app.allocator, source.len) catch return;

    const scratch = app.allocator.alloc(core.search.ScoredItem, source.len) catch return;
    defer app.allocator.free(scratch);

    const n = if (query.len == 0) rankAppsByHistory(app, source, scratch) else core.search.searchMappedBoosted(
        core.desktop.DesktopEntry,
        core.desktop.nameOf,
        appHistoryBoost,
        &app.launch_history,
        source,
        query,
        scratch,
    );

    for (scratch[0..n]) |item| {
        app.visible_indices.appendAssumeCapacity(item.index);
    }
}

fn rankAppsByHistory(app: *state.AppState, source: []const core.desktop.DesktopEntry, out: []core.search.ScoredItem) usize {
    const n = @min(source.len, out.len);
    for (source[0..n], 0..) |entry, i| {
        out[i] = .{ .index = i, .score = app.launch_history.boost(core.desktop.idOf(entry)) };
    }
    core.search.sortScored(out[0..n]);
    return n;
}

fn appHistoryBoost(ctx: *const anyopaque, entry: core.desktop.DesktopEntry) i64 {
    const history: *const core.launch_history.History = @ptrCast(@alignCast(ctx));
    return history.boost(core.desktop.idOf(entry));
}

fn pipedFilter(app_opaque: *anyopaque, _: api.Context, query: []const u8) void {
    const app = appPtr(app_opaque);
    const source = app.piped_items.items;
    if (source.len == 0) return;

    app.visible_indices.ensureTotalCapacity(app.allocator, source.len) catch return;

    if (query.len == 0) {
        for (0..source.len) |i| app.visible_indices.appendAssumeCapacity(i);
        return;
    }

    app.piped_visible_scores.ensureTotalCapacity(app.allocator, source.len) catch return;

    const scratch = app.allocator.alloc(core.search.ScoredItem, source.len) catch return;
    defer app.allocator.free(scratch);

    const n = core.search.searchMapped([]const u8, identityStr, source, query, scratch);
    for (scratch[0..n]) |item| {
        app.visible_indices.appendAssumeCapacity(item.index);
        app.piped_visible_scores.appendAssumeCapacity(item.score);
    }
}

fn emojiFilter(app_opaque: *anyopaque, _: api.Context, query: []const u8) void {
    const app = appPtr(app_opaque);
    fillFor(core.emoji.EmojiEntry, core.emoji.searchableOf, app.emojiEntries(), app, query);
}

fn identityStr(s: []const u8) []const u8 {
    return s;
}

fn fillFor(
    comptime T: type,
    comptime getText: fn (T) []const u8,
    source: []const T,
    app: *state.AppState,
    query: []const u8,
) void {
    if (source.len == 0) return;
    app.visible_indices.ensureTotalCapacity(app.allocator, source.len) catch return;
    if (query.len == 0) {
        for (0..source.len) |i| app.visible_indices.appendAssumeCapacity(i);
        return;
    }
    const scratch = app.allocator.alloc(core.search.ScoredItem, source.len) catch return;
    defer app.allocator.free(scratch);
    const out = app.visible_indices.allocatedSlice();
    const n = core.filter.filter(T, getText, source, query, out, scratch);
    app.visible_indices.items.len = n;
}

fn appsLaunch(app_opaque: *anyopaque, _: api.Context) void {
    const app = appPtr(app_opaque);
    const selection = app.currentSelectionData() orelse return;
    var command = core.exec.parseExec(app.allocator, selection.data) catch |err| {
        std.log.warn("failed parsing desktop Exec command '{s}': {}", .{ selection.data, err });
        return;
    };
    defer command.deinit();
    mode_util.launchDetached(app, command.program(), command.args());
    if (app.exit_code == 0) app.launched_app_id = selection.app_id;
}

fn pipedLaunch(app_opaque: *anyopaque, _: api.Context) void {
    const app = appPtr(app_opaque);
    const selection = app.currentSelectionData() orelse return;
    mode_util.writeStdout(app, "{s}\n", .{selection.data});
    app.exit_code = 0;
    _ = app.ui.main.Close();
}

fn actionLaunch(app_opaque: *anyopaque, ctx: api.Context) void {
    const app = appPtr(app_opaque);
    const cfg = actionPtr(ctx);
    const text_ptr = app.ui.input.Text(app.allocator);
    defer app.allocator.free(text_ptr);
    if (text_ptr.len == 0) return;

    const quoted_query = core.exec.quoteShellArg(app.allocator, text_ptr) catch return;
    defer app.allocator.free(quoted_query);

    const final_cmd = compose(app.allocator, cfg.action, quoted_query) catch return;
    defer app.allocator.free(final_cmd);

    mode_util.launchDetached(app, "sh", &.{ "-c", final_cmd });
}

fn compose(allocator: std.mem.Allocator, template: []const u8, quoted_query: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, template, placeholder_token)) |idx| {
        return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
            template[0..idx],
            quoted_query,
            template[idx + placeholder_token.len ..],
        });
    }
    return std.fmt.allocPrint(allocator, "{s} {s}", .{ template, quoted_query });
}

fn urlLaunch(app_opaque: *anyopaque, _: api.Context) void {
    const app = appPtr(app_opaque);
    const text_ptr = app.ui.input.Text(app.allocator);
    defer app.allocator.free(text_ptr);
    if (text_ptr.len == 0) return;

    const target = blk: {
        if (hasScheme(text_ptr)) break :blk text_ptr;
        const buf = app.allocator.alloc(u8, https_prefix.len + text_ptr.len) catch return;
        @memcpy(buf[0..https_prefix.len], https_prefix);
        @memcpy(buf[https_prefix.len..], text_ptr);
        break :blk buf;
    };
    defer if (!hasScheme(text_ptr)) app.allocator.free(target);

    mode_util.launchDetached(app, "xdg-open", &.{target});
}

fn hasScheme(text: []const u8) bool {
    return std.mem.startsWith(u8, text, "http://") or std.mem.startsWith(u8, text, "https://");
}

fn promptLaunch(app_opaque: *anyopaque, ctx: api.Context) void {
    const app = appPtr(app_opaque);
    const cfg = promptPtr(ctx);
    const text_ptr = app.ui.input.Text(app.allocator);
    defer app.allocator.free(text_ptr);
    if (text_ptr.len == 0 and !cfg.allow_empty) return;
    mode_util.writeStdout(app, "{s}\n", .{text_ptr});
    app.exit_code = 0;
    _ = app.ui.main.Close();
}

fn emojiLaunch(app_opaque: *anyopaque, ctx: api.Context) void {
    const app = appPtr(app_opaque);
    const cfg = emojiPtr(ctx);
    const selection = app.currentSelectionData() orelse return;
    const glyph = selection.data;
    if (glyph.len == 0) return;

    switch (cfg.action) {
        .copy => copyToClipboard(app, glyph),
        .print => writeStdoutAndExit(app, glyph, 0),
        .type_keys => typeKeysAndExit(app, glyph),
    }
}

fn copyToClipboard(app: *state.AppState, glyph: []const u8) void {
    if (qt6.QProcess.StartDetached22(app.allocator, "wl-copy", &.{glyph})) {
        app.exit_code = 0;
        _ = app.ui.main.Close();
        return;
    }
    writeStdoutAndExit(app, glyph, 0);
}

fn writeStdoutAndExit(app: *state.AppState, glyph: []const u8, code: u8) void {
    mode_util.writeStdout(app, "{s}", .{glyph});
    app.exit_code = code;
    _ = app.ui.main.Close();
}

fn typeKeysAndExit(app: *state.AppState, glyph: []const u8) void {
    _ = app.ui.main.Close();
    if (qt6.QProcess.StartDetached22(app.allocator, "wtype", &.{ "--", glyph })) {
        app.exit_code = 0;
        return;
    }
    if (qt6.QProcess.StartDetached22(app.allocator, "wl-copy", &.{glyph})) {
        app.exit_code = 0;
        return;
    }
    std.log.warn("emoji: neither wtype nor wl-copy available — glyph discarded", .{});
    app.exit_code = 1;
}

fn promptTextChanged(app_opaque: *anyopaque, _: api.Context, query: []const u8) api.TextResult {
    promptFilter(app_opaque, null, query);
    return .handled;
}

fn promptFilter(app_opaque: *anyopaque, _: api.Context, query: []const u8) void {
    const app = appPtr(app_opaque);
    app.current_query.clearRetainingCapacity();
    app.current_query.appendSlice(app.allocator, query) catch {};
}

fn urlTextChanged(app_opaque: *anyopaque, _: api.Context, query: []const u8) api.TextResult {
    const app = appPtr(app_opaque);
    if (!url_util.isUrl(query)) {
        transitions.enterMode(app, .{ .plugin = &apps }, .{});
    }
    return .continue_filter;
}

fn emojiBeforeEnter(app_opaque: *anyopaque, _: api.Context) bool {
    const app = appPtr(app_opaque);
    app.ensureEmojisLoaded() catch |err| {
        std.log.err("failed to load emoji data: {}", .{err});
        return false;
    };
    return true;
}

fn emojiCanExitToDefault(app_opaque: *const anyopaque, ctx: api.Context) bool {
    _ = constAppPtr(app_opaque);
    return emojiPtr(ctx).entry == .trigger;
}

fn emojiIsCancelable(app_opaque: *const anyopaque, ctx: api.Context) bool {
    _ = constAppPtr(app_opaque);
    return emojiPtr(ctx).entry == .cli;
}

fn appsTextChanged(app_opaque: *anyopaque, _: api.Context, query: []const u8) api.TextResult {
    const app = appPtr(app_opaque);

    // Hardcoded ": " emoji trigger (cheap, no allocation).
    if (std.mem.eql(u8, query, emoji_trigger)) {
        transitions.enterMode(app, .{
            .plugin = &emoji,
            .ctx = &app.emoji_trigger_context,
        }, .{ .re_filter = true });
        return .handled;
    }

    // User-configured prefix triggers.
    for (app.registered_triggers.items) |trigger| {
        if (transitions.matchesTrigger(query, trigger.text)) {
            transitions.enterMode(app, trigger.mode, .{
                .clear_input = true,
                .re_filter = true,
            });
            return .handled;
        }
    }

    // URL auto-detect.
    if (url_util.isUrl(query)) {
        transitions.enterMode(app, .{ .plugin = &url }, .{});
        return .continue_filter;
    }

    return .continue_filter;
}

// --- Public transition wrappers used by ui/callbacks/helpers.zig ---

/// Resets the app to apps mode: hide the badge, restore the apps
/// placeholder, re-filter with an empty query. Used when leaving
/// prefix/url/emoji mode (backspace to empty input, Escape, Ctrl-W).
pub fn exitToApps(app: *state.AppState) void {
    transitions.enterMode(app, .{ .plugin = &apps }, .{ .re_filter = true });
}

/// Enters a prefix action mode (one of the configured triggers in
/// `app.registered_triggers`). The mode's badge text is whatever its
/// `badgeText` handler returns.
pub fn enterActionMode(app: *state.AppState, active: api.ActiveMode) void {
    transitions.enterMode(app, active, .{
        .clear_input = true,
        .re_filter = true,
    });
}

/// Enters URL mode (auto-detected from typed text).
pub fn enterUrlMode(app: *state.AppState) void {
    transitions.enterMode(app, .{ .plugin = &url }, .{});
}

/// Enters emoji mode via the mid-session ": " trigger. The plugin's
/// `beforeEnter` hook handles the lazy load and aborts on failure.
pub fn enterEmojiModeTrigger(app: *state.AppState) void {
    transitions.enterMode(app, .{
        .plugin = &emoji,
        .ctx = &app.emoji_trigger_context,
    }, .{ .re_filter = true });
}
