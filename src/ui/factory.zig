// UI factory: build the widget tree, lay it out, and connect the C-ABI
// signal callbacks. This is the only place that calls Qt widget
// constructors — the rest of the app treats `state.Widgets` as an opaque
// handle bundle.

const std = @import("std");
const qt6 = @import("libqt6zig");
const config = @import("../config/mod.zig");
const state = @import("../state/mod.zig");
const Widgets = state.Widgets;

const prompt_window_height: u32 = 80;

/// Bundles all C-ABI callback functions so `wireSignals` has a single
/// argument instead of six. The optional `on_stdin_activated` is wired
/// only in piped mode (the notifier is created in `app/startup.zig`).
pub const SignalCallbacks = struct {
    on_text_changed: *const fn (qt6.QLineEdit, [*:0]const u8) callconv(.c) void,
    on_key_press: *const fn (qt6.QLineEdit, qt6.QKeyEvent) callconv(.c) void,
    on_model_row_count: *const fn (qt6.QAbstractListModel, qt6.QModelIndex) callconv(.c) i32,
    on_model_data: *const fn (qt6.QAbstractListModel, qt6.QModelIndex, i32) callconv(.c) qt6.QVariant,
    on_item_double_clicked: *const fn (qt6.QListView, qt6.QModelIndex) callconv(.c) void,
    on_stdin_activated: ?*const fn (qt6.QSocketNotifier, qt6.QSocketDescriptor, i32) callconv(.c) void = null,
};

/// Applies the theme QSS to the main widget. No-op on failure.
pub fn applyTheme(widget: qt6.QWidget, theme: config.Theme, arena: std.mem.Allocator) void {
    if (config.generateQss(arena, theme)) |qss| {
        widget.SetStyleSheet(qss);
    } else |_| {}
}

/// Builds the widget tree. Returns the populated Widgets bundle. The
/// widgets are owned by Qt (parent-child ownership) — do not deinit them
/// from Zig. `prompt` is the PromptConfig if --prompt was given; passing
/// it triggers prompt-mode chrome (smaller window, hidden list, password
/// echo if requested).
pub fn build(arena: std.mem.Allocator, theme: config.Theme, prompt: ?state.PromptConfig) Widgets {
    _ = arena;
    const is_prompt = prompt != null;
    const main = qt6.QWidget.New2();

    const wayland = @import("wayland.zig");

    // Window flags: floating, centered, frameless, and kept above normal
    // windows while open. On Wayland the compositor has final say, but
    // this is the portable Qt request.
    const flags = if (wayland.isWayland())
        qt6.qnamespace_enums.WindowType.FramelessWindowHint
    else
        qt6.qnamespace_enums.WindowType.Dialog |
            qt6.qnamespace_enums.WindowType.FramelessWindowHint |
            qt6.qnamespace_enums.WindowType.WindowStaysOnTopHint;
    main.SetWindowFlags(flags);

    const window_height: u32 = if (is_prompt) prompt_window_height else theme.window_height;
    main.SetFixedSize2(@intCast(theme.window_width), @intCast(window_height));

    // Input row: badge (hidden by default) + line edit.
    const input = qt6.QLineEdit.New4("", main);
    input.SetPlaceholderText(if (is_prompt) "Type and press Enter…" else "Search apps...");
    if (prompt) |cfg| if (cfg.password) {
        input.SetEchoMode(qt6.qlineedit_enums.EchoMode.Password);
    };

    const badge = qt6.QLabel.New5("", main);
    if (prompt) |cfg| if (cfg.label.len > 0) {
        badge.SetText(cfg.label);
        badge.Show();
    } else {
        badge.Hide();
    };

    // List and model.
    const list = qt6.QListView.New(main);
    list.SetUniformItemSizes(true);
    list.SetSelectionMode(qt6.qabstractitemview_enums.SelectionMode.SingleSelection);
    list.SetSelectionBehavior(qt6.qabstractitemview_enums.SelectionBehavior.SelectRows);
    list.SetEditTriggers(qt6.qabstractitemview_enums.EditTrigger.NoEditTriggers);

    const model = qt6.QAbstractListModel.New2(main);
    list.SetModel(model);

    const no_results = qt6.QLabel.New5("No apps found", main);

    // Layout: input row on top, list in the middle, status label below.
    // Hidden children take zero space, so prompt mode collapses naturally.
    const input_layout = qt6.QHBoxLayout.New2();
    input_layout.AddWidget(badge);
    input_layout.AddWidget(input);

    const layout = qt6.QVBoxLayout.New2();
    layout.AddLayout(input_layout);
    layout.AddWidget(list);
    layout.AddWidget(no_results);
    layout.SetContentsMargins(
        @intCast(theme.window_padding),
        @intCast(theme.window_padding),
        @intCast(theme.window_padding),
        @intCast(theme.window_padding),
    );
    layout.SetSpacing(@intCast(theme.item_spacing));
    main.SetLayout(layout);

    if (is_prompt) {
        list.Hide();
        no_results.Hide();
    }

    return .{
        .main = main,
        .badge = badge,
        .input = input,
        .list = list,
        .model = model,
        .no_results = no_results,
    };
}

/// Connects all C-ABI signals to their handlers. Call exactly once.
pub fn wireSignals(widgets: Widgets, cbs: SignalCallbacks) void {
    widgets.model.OnRowCount(cbs.on_model_row_count);
    widgets.model.OnData(cbs.on_model_data);
    widgets.list.OnDoubleClicked(cbs.on_item_double_clicked);
    widgets.input.OnTextChanged(cbs.on_text_changed);
    widgets.input.OnKeyPressEvent(cbs.on_key_press);
}

/// Sets the window title and (in prompt mode) pre-fills the input. Call
/// after building, before showing.
pub fn configureInitialFrame(widgets: Widgets, arena: std.mem.Allocator, settings: anytype) void {
    const prompt: ?state.PromptConfig = settings.prompt;
    if (prompt) |cfg| {
        const title = if (cfg.label.len > 0)
            std.fmt.allocPrint(arena, "Badi — {s}", .{cfg.label}) catch "Badi"
        else
            "Badi";
        widgets.main.SetWindowTitle(title);
        if (cfg.default_value.len > 0) {
            widgets.input.SetText(cfg.default_value);
            widgets.input.SelectAll();
        }
    } else if (settings.emoji != null) {
        widgets.main.SetWindowTitle("Badi — Emoji");
    } else {
        widgets.main.SetWindowTitle("Badi");
    }
    widgets.input.SetFocus();
}
