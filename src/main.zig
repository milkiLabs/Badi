const std = @import("std");
const config = @import("config.zig");
const qt6 = @import("libqt6zig");
const context = @import("context.zig");
const desktop = @import("core/desktop.zig");
const window = @import("ui/window.zig");
const callbacks = @import("ui/callbacks.zig");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    // 1. Initialize Qt Library Context
    const argv = try qt6.init(allocator, init.minimal.args);
    defer qt6.deinit(allocator, argv);
    var argc: i32 = @intCast(argv.len);
    const qapp = qt6.QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    // 2. Create Main Window
    const main_widget = qt6.QWidget.New2();
    defer main_widget.Delete();

    // Load Theme & Apply
    const theme = config.loadTheme(init.arena.allocator(), init.environ_map, init.io) catch config.Theme{};
    const qss = config.generateQss(init.arena.allocator(), theme) catch null;
    if (qss) |s| main_widget.SetStyleSheet(s);

    // Load Config (actions/prefixes)
    const cfg = config.loadConfig(init.arena.allocator(), init.environ_map, init.io) catch config.Config{};
    var prefixes: std.ArrayList(context.Action) = .empty;
    errdefer prefixes.deinit(allocator);
    for (cfg.actions) |action| {
        try prefixes.append(allocator, .{
            .trigger = action.trigger,
            .name = action.name,
            .icon = action.icon,
            .action = action.action,
        });
    }

    // Make the window a floating, centered, frameless dialog (works well on Wayland/Tiling window managers)
    const window_flags = qt6.qnamespace_enums.WindowType.Dialog | qt6.qnamespace_enums.WindowType.FramelessWindowHint;
    main_widget.SetWindowFlags(window_flags);
    main_widget.SetFixedSize2(@intCast(theme.window_width), @intCast(theme.window_height));

    // 4. Create UI Elements
    const input = qt6.QLineEdit.New4("", main_widget);
    input.SetPlaceholderText("Search apps...");
    input.OnTextChanged(callbacks.onTextChanged);

    const badge = qt6.QLabel.New5("", main_widget);
    badge.Hide();

    const list = qt6.QListWidget.New(main_widget);
    list.SetUniformItemSizes(true);
    const no_results = qt6.QLabel.New5("No apps found", main_widget);

    // 5. Layout Engine
    const input_layout = qt6.QHBoxLayout.New2();
    input_layout.AddWidget(badge);
    input_layout.AddWidget(input);

    const layout = qt6.QVBoxLayout.New2();
    layout.AddLayout(input_layout);
    layout.AddWidget(list);
    layout.AddWidget(no_results);

    layout.SetContentsMargins(@intCast(theme.window_padding), @intCast(theme.window_padding), @intCast(theme.window_padding), @intCast(theme.window_padding));
    layout.SetSpacing(@intCast(theme.item_spacing));

    main_widget.SetLayout(layout);

    const stdin = std.Io.File.stdin();
    // A real pipe is the only signal for piped mode.  Sway's `exec` connects
    // stdin to /dev/null (a character device), so checking for named_pipe
    // alone correctly falls back to apps mode for keybinding launches.
    const stdin_stat = stdin.stat(init.io) catch null;
    const is_piped = stdin_stat != null and stdin_stat.?.kind == .named_pipe;

    var app_list: ?desktop.DesktopAppList = null;
    errdefer if (app_list) |*list_| list_.deinit();
    var piped_items: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (piped_items.items) |item| allocator.free(item);
        piped_items.deinit(allocator);
    }
    var stdin_pending: std.ArrayList(u8) = .empty;
    errdefer stdin_pending.deinit(allocator);
    var visible_indices: std.ArrayList(usize) = .empty;
    errdefer visible_indices.deinit(allocator);

    // Load data now so the window is responsive the moment it appears.
    if (!is_piped) {
        app_list = try desktop.loadDesktopApps(allocator, init.io, init.environ_map);
    }

    // 6. Connect State
    var app_state: context.AppState = .{
        .allocator = allocator,
        .io = init.io,
        .ui = .{
            .main = main_widget,
            .badge = badge,
            .input = input,
            .list = list,
            .no_results = no_results,
        },
        .mode = if (is_piped) .piped else .apps,
        .exit_code = null,
        .app_list = app_list,
        .piped_items = piped_items,
        .stdin_pending = stdin_pending,
        .prefixes = prefixes,
        .visible_indices = visible_indices,
        .selected_index = null,
    };
    // Register the state so callbacks can reach it via context.state().
    context.setActive(&app_state);
    defer app_state.deinit();

    // 7. Event Connections
    list.OnItemDoubleClicked(callbacks.onItemDoubleClicked);
    input.OnKeyPressEvent(callbacks.onKeyPress);

    // 8. Display
    input.SetFocus();
    if (is_piped) {
        // Piped: show immediately, stream lines via QSocketNotifier.
        no_results.SetText("Waiting for input...");
        no_results.Show();
        main_widget.Show();

        // Async stdin: lets the GUI stay responsive while waiting for piped input — fires onStdinActivated when data arrives.
        const notifier = qt6.QSocketNotifier.New4(stdin.handle, qt6.qsocketnotifier_enums.Type.Read, main_widget);
        notifier.OnActivated(callbacks.onStdinActivated);
    } else {
        // Apps: data already loaded — populate list, then show.
        window.filterList("");
        no_results.Hide();
        main_widget.Show();
    }

    _ = qt6.QApplication.Exec();

    // Cancelling piped mode returns 1 to scripts; selection sets exit_code to 0.
    return app_state.exit_code orelse if (app_state.mode == .piped) 1 else 0;
}
