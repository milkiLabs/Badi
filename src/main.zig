const std = @import("std");
const config = @import("config.zig");
const qt6 = @import("libqt6zig");
const context = @import("context.zig");
const desktop = @import("core/desktop.zig");
const window = @import("ui/window.zig");
const callbacks = @import("ui/callbacks.zig");

/// Height of the prompt-mode window. Narrower than the launcher because there
/// is no list to show — just the input row with its badge.
const prompt_window_height: u32 = 80;

/// Walks argv looking for `--prompt` and the related flags. Returns the
/// parsed `PromptConfig` if `--prompt` is present, otherwise null. The
/// `--prompt` value may be attached as the next arg (e.g. `--prompt "Name: "`)
/// or omitted for a no-label prompt. Returned string slices are borrowed
/// from `args` and live for the duration of the process.
fn parsePromptArgs(args: []const [:0]const u8) !?context.PromptConfig {
    var i: usize = 0;
    var has_prompt = false;
    var label: []const u8 = "";
    var default_value: []const u8 = "";
    var password = false;
    var allow_empty = false;

    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--prompt")) {
            has_prompt = true;
            // Optional inline label: the next arg, only if it doesn't start with "-"
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                label = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, a, "--default")) {
            if (i + 1 >= args.len) return error.MissingValueForDefault;
            default_value = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--password")) {
            password = true;
        } else if (std.mem.eql(u8, a, "--allow-empty")) {
            allow_empty = true;
        }
    }

    if (!has_prompt) return null;
    return context.PromptConfig{
        .label = label,
        .default_value = default_value,
        .password = password,
        .allow_empty = allow_empty,
    };
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    // 1. Initialize Qt Library Context
    const argv = try qt6.init(allocator, init.minimal.args);
    defer qt6.deinit(allocator, argv);
    var argc: i32 = @intCast(argv.len);
    const qapp = qt6.QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    // Parse CLI flags before building UI so we know which mode to enter.
    // Materialize the args slice into the arena first — `init.minimal.args`
    // is a `process.Args` (an iterator-like struct), not a slice.
    const args_slice = try init.minimal.args.toSlice(init.arena.allocator());
    const prompt_cfg_opt = try parsePromptArgs(args_slice);
    const is_prompt = prompt_cfg_opt != null;
    const prompt_cfg = prompt_cfg_opt orelse context.PromptConfig{
        .label = "",
        .default_value = "",
        .password = false,
        .allow_empty = false,
    };

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
    const window_height = if (is_prompt) prompt_window_height else theme.window_height;
    main_widget.SetFixedSize2(@intCast(theme.window_width), @intCast(window_height));

    // 4. Create UI Elements
    const input = qt6.QLineEdit.New4("", main_widget);
    // Placeholder adapts to the mode: prompt mode shows a hint when no label
    // is set, launcher mode shows the standard search prompt.
    const initial_placeholder: []const u8 = if (is_prompt)
        (if (prompt_cfg.label.len == 0) "Type and press Enter…" else "")
    else
        "Search apps...";
    input.SetPlaceholderText(initial_placeholder);
    input.OnTextChanged(callbacks.onTextChanged);

    if (is_prompt and prompt_cfg.password) {
        input.SetEchoMode(qt6.qlineedit_enums.EchoMode.Password);
    }

    const badge = qt6.QLabel.New5("", main_widget);
    if (is_prompt and prompt_cfg.label.len > 0) {
        badge.SetText(prompt_cfg.label);
        badge.Show();
    } else {
        badge.Hide();
    }

    const list = qt6.QListView.New(main_widget);
    list.SetUniformItemSizes(true);
    list.SetSelectionMode(qt6.qabstractitemview_enums.SelectionMode.SingleSelection);
    list.SetSelectionBehavior(qt6.qabstractitemview_enums.SelectionBehavior.SelectRows);
    list.SetEditTriggers(qt6.qabstractitemview_enums.EditTrigger.NoEditTriggers);
    const model = qt6.QAbstractListModel.New2(main_widget);
    list.SetModel(model);
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

    // Hide list/empty-label chrome in prompt mode — layout treats hidden
    // children as zero-size, so the window collapses to just the input row.
    if (is_prompt) {
        list.Hide();
        no_results.Hide();
    }

    const stdin = std.Io.File.stdin();
    // A real pipe is the only signal for piped mode.  Sway's `exec` connects
    // stdin to /dev/null (a character device), so checking for named_pipe
    // alone correctly falls back to apps mode for keybinding launches.
    // `--prompt` overrides piped detection: scripts that pipe data can still
    // invoke a prompt by passing the flag — stdin is ignored in prompt mode.
    const stdin_stat = stdin.stat(init.io) catch null;
    const is_piped = !is_prompt and stdin_stat != null and stdin_stat.?.kind == .named_pipe;

    var app_list: ?desktop.DesktopAppList = null;
    const piped_items: std.ArrayList([]const u8) = .empty;
    const stdin_pending: std.ArrayList(u8) = .empty;
    const current_query: std.ArrayList(u8) = .empty;
    const visible_indices: std.ArrayList(usize) = .empty;

    // Load data now so the window is responsive the moment it appears.
    if (!is_piped and !is_prompt) {
        app_list = try desktop.loadDesktopApps(allocator, init.io, init.environ_map);
    }

    // 6. Connect State
    const initial_mode: context.AppMode = if (is_prompt)
        .{ .prompt = prompt_cfg }
    else if (is_piped)
        .piped
    else
        .apps;
    var app_state: context.AppState = .{
        .allocator = allocator,
        .io = init.io,
        .ui = .{
            .main = main_widget,
            .badge = badge,
            .input = input,
            .list = list,
            .model = model,
            .no_results = no_results,
        },
        .mode = initial_mode,
        .exit_code = null,
        .app_list = app_list,
        .piped_items = piped_items,
        .stdin_pending = stdin_pending,
        .prefixes = prefixes,
        .current_query = current_query,
        .visible_indices = visible_indices,
        .selected_index = null,
        .stdin_eof = false,
    };
    // Register the state so callbacks can reach it via context.state().
    context.setActive(&app_state);
    defer app_state.deinit();

    // 7. Event Connections
    model.OnRowCount(window.onModelRowCount);
    model.OnData(window.onModelData);
    list.OnDoubleClicked(callbacks.onItemDoubleClicked);
    input.OnKeyPressEvent(callbacks.onKeyPress);

    // 8. Display
    if (is_prompt) {
        // Window title: a distinct identity in the WM taskbar. A label adds
        // a " — <label>" suffix when present.
        if (prompt_cfg.label.len > 0) {
            const title = std.fmt.allocPrint(init.arena.allocator(), "Badi — {s}", .{prompt_cfg.label}) catch "Badi";
            main_widget.SetWindowTitle(title);
        } else {
            main_widget.SetWindowTitle("Badi");
        }

        // Pre-fill and select-all so the user can accept with Enter or type
        // to overwrite. Skipped if no default — cursor just lands at start.
        if (prompt_cfg.default_value.len > 0) {
            input.SetText(prompt_cfg.default_value);
            input.SelectAll();
        }
    }

    input.SetFocus();
    if (is_piped) {
        // Piped: show immediately, stream lines via QSocketNotifier.
        window.updateNoResults(&app_state);
        main_widget.Show();

        // Async stdin: lets the GUI stay responsive while waiting for piped input — fires onStdinActivated when data arrives.
        const notifier = qt6.QSocketNotifier.New4(stdin.handle, qt6.qsocketnotifier_enums.Type.Read, main_widget);
        notifier.OnActivated(callbacks.onStdinActivated);
    } else if (is_prompt) {
        // Prompt: window is configured, no list to populate, no stdin to read.
        window.updateNoResults(&app_state);
        main_widget.Show();
    } else {
        // Apps: data already loaded — populate list, then show.
        window.filterList("");
        main_widget.Show();
    }

    _ = qt6.QApplication.Exec();

    // Cancelling piped or prompt mode returns 1 to scripts; selection sets
    // exit_code to 0 in the relevant branch.
    return app_state.exit_code orelse switch (app_state.mode) {
        .piped, .prompt => 1,
        .apps, .prefix => 0,
    };
}
