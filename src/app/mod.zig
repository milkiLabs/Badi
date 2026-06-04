// The composition root. Owns the entire app lifecycle: initialization,
// event loop, teardown. Three methods: `create`, `run`, `destroy`.
// `create` builds everything, `run` starts the event loop and returns
// the exit code, `destroy` releases resources.

const std = @import("std");
const qt6 = @import("libqt6zig");
const config = @import("../config/mod.zig");
const state = @import("../state/mod.zig");
const ui = @import("../ui/mod.zig");

pub const cli = @import("cli.zig");
const startup = @import("startup.zig");
const exit_code = @import("exit_code.zig");
const single_instance = @import("single_instance.zig");

pub const Settings = cli.Settings;

pub const App = struct {
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    settings: Settings,
    state: state.AppState,
    argv: [][:0]u8,
    qapp: qt6.QApplication,

    /// Builds the app. Loads theme + config, constructs widgets, wires
    /// signals, loads .desktop apps (in apps mode). Must be paired with
    /// `destroy`. The returned App is uninitialized for the event loop;
    /// call `run` for that.
    pub fn create(init: std.process.Init, settings: Settings) !App {
        const arena = init.arena.allocator();
        const gpa = init.gpa;

        // Qt init.
        const argv = try qt6.init(gpa, init.minimal.args);
        errdefer qt6.deinit(gpa, argv);
        var argc: i32 = @intCast(argv.len);
        const qapp = qt6.QApplication.New(arena, &argc, argv);
        errdefer qapp.Delete();

        // Theme + widgets.
        const theme = config.loadTheme(arena, init.environ_map, init.io) catch config.Theme{};
        const widgets = ui.factory.build(arena, theme, settings.prompt);
        errdefer widgets.main.Delete();
        ui.factory.applyTheme(widgets.main, theme, arena);

        // Signal wiring. The stdin notifier is wired separately in
        // `prepareInitialFrame` (only in piped mode).
        ui.factory.wireSignals(widgets, .{
            .on_text_changed = ui.callbacks.onTextChanged,
            .on_key_press = ui.callbacks.onKeyPress,
            .on_model_row_count = ui.model.onModelRowCount,
            .on_model_data = ui.model.onModelData,
            .on_item_double_clicked = ui.callbacks.onItemDoubleClicked,
        });

        // AppState: resolves the initial mode, loads user actions, and
        // loads the .desktop data for non-prompt modes. Emoji entries are
        // loaded only if emoji mode is entered. The global pointer is NOT
        // set here — `app_state` is a local that
        // gets moved into `self.state` when create returns, which would
        // dangle the global. `run` sets it once `self` is in its final
        // location.
        var app_state = try startup.buildState(gpa, init.io, init.environ_map, widgets, settings);
        errdefer app_state.deinit();

        // Single-instance: bind the socket so a previous instance can be
        // told to close. Only meaningful in apps or emoji mode. The mode
        // is read from app_state so we resolve it exactly once.
        if (single_instance.enabled(&app_state)) {
            app_state.single_instance_server = try single_instance.listenReplacingExisting(init.io);
        }

        return .{
            .arena = arena,
            .gpa = gpa,
            .io = init.io,
            .env = init.environ_map,
            .settings = settings,
            .state = app_state,
            .argv = argv,
            .qapp = qapp,
        };
    }

    /// Shows the window, starts the event loop, and returns the process
    /// exit code. The initial mode is resolved once in `buildState`
    /// (called from `create`) and is not re-resolved here.
    pub fn run(self: *App) u8 {
        // Set the global now that `self` is in its final stack frame.
        // Qt callbacks read app state through this pointer.
        state.global.set(&self.state);

        // `buildState` was called against a local `app_state` on
        // `App.create`'s stack frame; the initial mode's `ctx` was
        // left null for `--prompt` and `--emoji` (or dangles, for
        // any other take-against-local site). Re-seat against the
        // final stable location now that `self.state` is in place.
        self.fixupModeCtx();

        if (self.state.single_instance_server) |*server| {
            const notifier = qt6.QSocketNotifier.New4(
                server.socket.handle,
                qt6.qsocketnotifier_enums.Type.Read,
                self.state.ui.main,
            );
            notifier.OnActivated(ui.callbacks.onReplacementRequested);
        }
        startup.prepareInitialFrame(&self.state, self.arena, self.settings);
        ui.wayland.setup(self.state.ui.main);
        self.state.ui.main.Show();
        _ = qt6.QApplication.Exec();
        return exit_code.resolve(&self.state);
    }

    /// Re-seats the initial mode's `ctx` pointer against the final
    /// stable `AppState` location. Called once from `run`, after the
    /// global pointer is set. Only the two CLI-driven initial modes
    /// (`--prompt`, `--emoji`) need this — other modes (apps, piped,
    /// action via trigger) either have no ctx or take it against the
    /// heap-stable `registered_triggers[i].mode.ctx` (which points at
    /// `prefixes.items[i]`, a heap entry).
    fn fixupModeCtx(self: *App) void {
        if (std.mem.eql(u8, self.state.mode.plugin.id, "emoji")) {
            self.state.mode.ctx = @ptrCast(&self.state.emoji_cli_context);
        } else if (std.mem.eql(u8, self.state.mode.plugin.id, "prompt")) {
            self.state.mode.ctx = @ptrCast(&self.state.prompt_context);
        }
    }

    /// Releases resources in reverse order of allocation. The state is
    /// deinit'd first (frees Zig-owned data), then the QApplication
    /// (which frees all Qt-owned widgets), then the qt6 init buffer.
    pub fn destroy(self: *App) void {
        self.state.deinit();
        self.qapp.Delete();
        qt6.deinit(self.gpa, self.argv);
    }
};
