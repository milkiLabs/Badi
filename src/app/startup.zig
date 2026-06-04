// Startup sequencing: build the AppState (loading desktop apps if needed),
// resolve the actual initial mode (prompt / piped / apps), and prepare
// the first frame of the window. Lives separately from `App.create` so
// the create function stays a "wire everything together" function.

const std = @import("std");
const qt6 = @import("libqt6zig");
const config = @import("../config/mod.zig");
const core = @import("../core/mod.zig");
const state = @import("../state/mod.zig");
const plugin = @import("../plugins/api.zig");
const builtin = @import("../plugins/builtin.zig");
const ui = @import("../ui/mod.zig");
const App = @import("mod.zig");

/// Constructs the AppState on the heap and returns the pointer.
/// Heap-allocating (rather than returning by value) gives the state
/// a stable address for the whole process — needed because the
/// `ActiveMode.ctx` pointer for prefix/emoji modes points into the
/// state itself (`&prefixes.items[i]`, `&emoji_cli_context`, etc.)
/// and those pointers must remain valid for the duration of the
/// event loop.
///
/// The caller owns the returned pointer and must call `deinit` then
/// `gpa.destroy` (in `App.destroy`).
pub fn buildState(
    gpa: std.mem.Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    widgets: state.Widgets,
    settings: App.Settings,
) !*state.AppState {
    const app_state = try gpa.create(state.AppState);
    errdefer gpa.destroy(app_state);

    // Default contexts for the modes that need per-instance state. The
    // prompt_context is only used when --prompt was given; emoji_cli
    // is only used when --emoji was given; emoji_trigger is used for
    // mid-session ": " entry (always allocated, never read unless
    // the trigger fires).
    app_state.* = .{
        .allocator = gpa,
        .io = io,
        .env = env,
        .ui = widgets,
        .single_instance_server = null,
        .mode = .{ .plugin = &builtin.apps, .ctx = null },
        .exit_code = null,
        .app_list = null,
        .launch_history = core.launch_history.load(gpa, env, io),
        .launched_app_id = null,
        .emojis = null,
        .emojis_loaded = false,
        .prefixes = .empty,
        .registered_triggers = .empty,
        .prompt_context = settings.prompt orelse .{
            .label = "",
            .default_value = "",
            .password = false,
            .allow_empty = false,
        },
        .emoji_cli_context = if (settings.emoji) |cfg| cfg else .{ .entry = .cli },
        .emoji_trigger_context = .{ .entry = .trigger },
        .piped_items = .empty,
        .stdin_pending = .empty,
        .current_query = .empty,
        .visible_indices = .empty,
        .piped_visible_scores = .empty,
        .selected_index = null,
        .stdin_eof = false,
        .setting_text = false,
    };
    errdefer app_state.deinit();

    // Load user actions via a scratch arena so the parsed JSON buffer is
    // freed before run. We duplicate the slices into the long-lived gpa
    // because AppState.prefixes owns them for the whole process. We also
    // build the plugin-style registered_triggers list next to them: each
    // entry points at the heap-owned `config.Action` (lifetime is the
    // process lifetime, so the pointer stays valid).
    {
        var scratch = std.heap.ArenaAllocator.init(gpa);
        defer scratch.deinit();
        const cfg = config.loadActions(scratch.allocator(), env, io) catch config.Config{};
        try app_state.prefixes.ensureTotalCapacity(gpa, cfg.actions.len);
        try app_state.registered_triggers.ensureTotalCapacity(gpa, cfg.actions.len);
        for (cfg.actions) |action| {
            const owned: config.Action = .{
                .trigger = try gpa.dupe(u8, action.trigger),
                .name = try gpa.dupe(u8, action.name),
                .icon = try gpa.dupe(u8, action.icon),
                .action = try gpa.dupe(u8, action.action),
            };
            try app_state.prefixes.append(gpa, owned);
            // The ctx pointer points at the heap-owned ArrayList entry,
            // which lives as long as the AppState itself.
            const stable: *const config.Action = &app_state.prefixes.items[app_state.prefixes.items.len - 1];
            try app_state.registered_triggers.append(gpa, .{
                .text = owned.trigger,
                .mode = .{ .plugin = &builtin.action, .ctx = @ptrCast(stable) },
            });
        }
    }

    // Resolve the actual initial mode. If --prompt or --emoji was given,
    // those modes win unconditionally. Otherwise, stdin's stat() determines
    // piped vs apps. A real named pipe is the only signal for piped mode;
    // character devices (terminal, /dev/null) fall through to apps.
    app_state.mode = resolveInitialMode(io, settings, app_state);

    // Load .desktop apps now so the window is fully populated on first show.
    if (settings.prompt == null) {
        app_state.app_list = try core.desktop.loadDesktopApps(gpa, io, env);
    }

    return app_state;
}

/// Resolves the actual initial mode. If --prompt or --emoji was given,
/// those modes win unconditionally. Otherwise, stdin's stat() determines
/// piped vs apps. A real named pipe is the only signal for piped mode;
/// character devices (terminal, /dev/null) fall through to apps.
///
/// For `--prompt` and `--emoji`, the returned `ActiveMode.ctx` points at
/// the corresponding per-instance state field on `app_state` (which is
/// stable since the AppState is heap-allocated).
pub fn resolveInitialMode(
    io: std.Io,
    settings: App.Settings,
    app_state: *state.AppState,
) plugin.ActiveMode {
    if (settings.prompt != null) return .{
        .plugin = builtin.modeById("prompt").?,
        .ctx = @ptrCast(&app_state.prompt_context),
    };
    if (settings.emoji != null) return .{
        .plugin = builtin.modeById("emoji").?,
        .ctx = @ptrCast(&app_state.emoji_cli_context),
    };

    const stdin = std.Io.File.stdin();
    const stat = stdin.stat(io) catch return .{ .plugin = builtin.modeById("apps").? };
    if (stat.kind == .named_pipe) return .{ .plugin = builtin.modeById("piped").? };
    return .{ .plugin = builtin.modeById("apps").? };
}

/// Wires the QSocketNotifier for piped mode and applies the initial
/// filter. Requires `app.mode` to be set (done by `buildState`).
pub fn prepareInitialFrame(app: *state.AppState, arena: std.mem.Allocator, settings: App.Settings) void {
    // In piped mode, watch stdin for incoming data.
    if (std.mem.eql(u8, app.mode.plugin.id, "piped")) {
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
    // status, prompt has nothing to show. Explicit --emoji is an actual
    // emoji request, so its `beforeEnter` hook (lazy-load emojis) runs
    // before the initial filter.
    if (std.mem.eql(u8, app.mode.plugin.id, "emoji")) {
        if (app.mode.plugin.beforeEnter) |f| {
            _ = f(app, app.mode.ctx);
        }
        ui.view.applyFilter(app, "");
    } else if (std.mem.eql(u8, app.mode.plugin.id, "apps")) {
        ui.view.applyFilter(app, "");
    } else if (std.mem.eql(u8, app.mode.plugin.id, "piped")) {
        ui.status.updateNoResults(app);
    } else {
        // prefix/url/prompt — nothing to do for first paint
    }
}
