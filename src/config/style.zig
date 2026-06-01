// Qt Style Sheet (QSS) generation from a Theme. Pure function: theme in,
// QSS string out. Qt only sees the final string via `QWidget::setStyleSheet` in `ui/factory.zig`.

const std = @import("std");
const Theme = @import("theme.zig").Theme;

/// Builds a Qt Style Sheet string from the theme. Double braces `{{`/`}}`
/// are literal braces — `std.fmt` uses single `{`/`}` for interpolation.
pub fn generateQss(allocator: std.mem.Allocator, t: Theme) ![]const u8 {
    const qss =
        \\QWidget {{
        \\    background-color: {s};
        \\    color: {s};
        \\    font-family: '{s}';
        \\    font-size: {d}px;
        \\    font-weight: {s};
        \\}}
        \\QLineEdit {{
        \\    background-color: {s};
        \\    border: {d}px solid {s};
        \\    padding: {d}px;
        \\    border-radius: {d}px;
        \\    color: {s};
        \\}}
        \\QLineEdit::placeholder {{
        \\    color: {s};
        \\}}
        \\QListView {{
        \\    background-color: transparent;
        \\    border: none;
        \\    outline: none;
        \\}}
        \\QListView::item {{
        \\    padding: {d}px;
        \\    border-radius: {d}px;
        \\}}
        \\QListView::item:selected {{
        \\    background-color: {s};
        \\    color: {s};
        \\}}
        \\QListView::item:hover {{
        \\    background-color: {s};
        \\}}
    ;

    return std.fmt.allocPrint(allocator, qss, .{
        t.background_color,
        t.text_color,
        t.font_family,
        t.font_size,
        t.font_weight,
        t.input_background,
        t.border_width,
        t.border_color,
        t.input_padding,
        t.border_radius,
        t.text_color,
        t.placeholder_color,
        t.item_padding,
        t.border_radius,
        t.accent_color,
        t.selected_text_color,
        t.hover_color,
    });
}
