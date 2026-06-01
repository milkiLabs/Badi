// Startup sequencing: build the AppState (loading desktop apps if needed),
// resolve the actual initial mode (prompt / piped / apps), and prepare
// the first frame of the window. Lives separately from `App.create` so
// the create function stays a "wire everything together" function.

const std = @import("std");
const qt6 = @import("libqt6zig");
const config = @import("../config/mod.zig");
const core = @import("../core/mod.zig");
const state = @import("../state/mod.zig");
const ui = @import("../ui/mod.zig");
const App = @import("mod.zig");

/// Constructs the AppState. Loads user-configured prefix actions and the
/// .desktop file list (in apps mode) synchronously, so the window is
/// responsive the moment it appears.
pub fn buildState(
    gpa: std.mem.Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    widgets: state.Widgets,
    settings: App.Settings,
) !state.AppState {
    var app_state: state.AppState = .{
        .allocator = gpa,
        .io = io,
        .ui = widgets,
        .single_instance_server = null,
        .mode = .apps, // refined in resolveMode at run time
        .exit_code = null,
        .app_list = null,
        .emojis = null,
        .piped_items = .empty,
        .stdin_pending = .empty,
        .prefixes = .empty,
        .current_query = .empty,
        .visible_indices = .empty,
        .selected_index = null,
        .stdin_eof = false,
    };
    errdefer app_state.deinit();

    // Load user actions via a scratch arena so the parsed JSON buffer is
    // freed before run. We duplicate the slices into the long-lived gpa
    // because AppState.prefixes owns them for the whole process.
    {
        var scratch = std.heap.ArenaAllocator.init(gpa);
        defer scratch.deinit();
        const cfg = config.loadActions(scratch.allocator(), env, io) catch config.Config{};
        try app_state.prefixes.ensureTotalCapacity(gpa, cfg.actions.len);
        for (cfg.actions) |action| {
            try app_state.prefixes.append(gpa, .{
                .trigger = try gpa.dupe(u8, action.trigger),
                .name = try gpa.dupe(u8, action.name),
                .icon = try gpa.dupe(u8, action.icon),
                .action = try gpa.dupe(u8, action.action),
            });
        }
    }

    // Load .desktop apps now so the window is fully populated on first show.
    if (settings.prompt == null) {
        app_state.app_list = try core.desktop.loadDesktopApps(gpa, io, env);
    }

    // Load emojis in any non-prompt mode so the ": " trigger is instant.
    // The slab is binary and pre-resolved at compile time; load is just an
    // allocation of the entry slice.
    if (settings.prompt == null) {
        app_state.emojis = try core.emoji.loadEmojis(gpa);
    }

    return app_state;
}

/// Resolves the actual initial mode. If --prompt or --emoji was given,
/// those modes win unconditionally. Otherwise, stdin's stat() determines
/// piped vs apps. A real named pipe is the only signal for piped mode;
/// character devices (terminal, /dev/null) fall through to apps.
pub fn resolveMode(
    io: std.Io,
    settings: App.Settings,
) state.AppMode {
    if (settings.prompt) |cfg| return .{ .prompt = cfg };
    if (settings.emoji) |cfg| return .{ .emoji = cfg };

    const stdin = std.Io.File.stdin();
    const stat = stdin.stat(io) catch return .apps;
    if (stat.kind == .named_pipe) return .piped;
    return .apps;
}

/// Wires the QSocketNotifier for piped mode and applies the initial
/// filter. Idempotent for the same mode; safe to call only after
/// `resolveMode` has set the actual mode.
pub fn prepareInitialFrame(app: *state.AppState, arena: std.mem.Allocator, settings: App.Settings) void {
    // In piped mode, watch stdin for incoming data.
    if (app.mode == .piped) {
        const stdin = std.Io.File.stdin();
        const notifier = qt6.QSocketNotifier.New4(
            stdin.handle,
            qt6.qsocketnotifier_enums.Type.Read,
            app.ui.main,
        );
        // Notifier is a Qt child of main_widget — freed when main is.
        notifier.OnActivated(ui.callbacks.onStdinActivated);
    }

    // Title + (prompt-mode) prefilled text + focus.
    ui.factory.configureInitialFrame(app.ui, arena, settings);

    // First paint: apps/emoji show all items, piped shows the "waiting"
    // status, prompt has nothing to show.
    switch (app.mode) {
        .apps, .emoji => ui.view.applyFilter(app, ""),
        .piped => ui.status.updateNoResults(app),
        .prefix, .url, .prompt => {},
    }
}
