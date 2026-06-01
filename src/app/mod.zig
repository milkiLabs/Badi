// The composition root. Owns the entire app lifecycle: initialization,
// event loop, teardown. Three methods: `create`, `run`, `destroy`.
// `create` builds everything, `run` starts the event loop and returns
// the exit code, `destroy` releases resources.

const std = @import("std");
const builtin = @import("builtin");
const qt6 = @import("libqt6zig");
const config = @import("../config/mod.zig");
const state = @import("../state/mod.zig");
const ui = @import("../ui/mod.zig");

pub const cli = @import("cli.zig");
const startup = @import("startup.zig");
const exit_code = @import("exit_code.zig");

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
    single_instance_server: ?std.Io.net.Server,

    /// Builds the app. Loads theme + config, constructs widgets, wires
    /// signals, loads .desktop apps (in apps mode). Must be paired with
    /// `destroy`. The returned App is uninitialized for the event loop;
    /// call `run` for that.
    pub fn create(init: std.process.Init, settings: Settings) !App {
        const arena = init.arena.allocator();
        const gpa = init.gpa;

        // Check single instance if in apps or emoji mode.
        const mode = startup.resolveMode(init.io, settings);
        var single_instance_server: ?std.Io.net.Server = null;
        if (mode == .apps or mode == .emoji) {
            if (builtin.os.tag == .linux) {
                const uid = std.os.linux.getuid();
                var path_buf: [128]u8 = undefined;
                const path = try std.fmt.bufPrint(&path_buf, "\x00badi-single-instance-{}", .{uid});
                const addr = try std.Io.net.UnixAddress.init(path);
                single_instance_server = addr.listen(init.io, .{}) catch |err| switch (err) {
                    error.AddressInUse => return error.AlreadyRunning,
                    else => return err,
                };
            }
        }
        errdefer if (single_instance_server) |*server| server.deinit(init.io);

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

        // Signal wiring.
        ui.factory.wireSignals(widgets, .{
            .on_text_changed = ui.callbacks.onTextChanged,
            .on_key_press = ui.callbacks.onKeyPress,
            .on_model_row_count = ui.model.onModelRowCount,
            .on_model_data = ui.model.onModelData,
            .on_item_double_clicked = ui.callbacks.onItemDoubleClicked,
            .on_stdin_activated = ui.callbacks.onStdinActivated,
        });

        // AppState: load data. The global pointer is NOT set here —
        // `app_state` is a local that gets moved into `self.state` when
        // create returns, which would dangle the global. `run` sets it
        // once `self` is in its final location.
        var app_state = try startup.buildState(gpa, init.io, init.environ_map, widgets, settings);
        errdefer app_state.deinit();

        return .{
            .arena = arena,
            .gpa = gpa,
            .io = init.io,
            .env = init.environ_map,
            .settings = settings,
            .state = app_state,
            .argv = argv,
            .qapp = qapp,
            .single_instance_server = single_instance_server,
        };
    }

    /// Resolves the actual mode (stdin check), shows the window, starts
    /// the event loop, and returns the process exit code.
    pub fn run(self: *App) u8 {
        // Set the global now that `self` is in its final stack frame.
        // Qt callbacks read app state through this pointer.
        state.global.set(&self.state);

        self.state.mode = startup.resolveMode(self.io, self.settings);
        startup.prepareInitialFrame(&self.state, self.arena, self.settings);
        self.state.ui.main.Show();
        _ = qt6.QApplication.Exec();
        return exit_code.resolve(&self.state);
    }

    /// Releases resources in reverse order of allocation. The state is
    /// deinit'd first (frees Zig-owned data), then the QApplication
    /// (which frees all Qt-owned widgets), then the qt6 init buffer.
    pub fn destroy(self: *App) void {
        if (self.single_instance_server) |*server| {
            server.deinit(self.io);
        }
        self.state.deinit();
        self.qapp.Delete();
        qt6.deinit(self.gpa, self.argv);
    }
};
