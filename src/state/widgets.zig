// Qt widget handles. Owned by Qt (parent-child ownership); Zig does not
// deinit these. Grouped here so callers don't have to thread six parameters
// through every function, and so the widget factory (`ui/factory.zig`) and
// the layout policy have a single type to construct.

const qt6 = @import("libqt6zig");

pub const Widgets = struct {
    main: qt6.QWidget,
    badge: qt6.QLabel,
    input: qt6.QLineEdit,
    list: qt6.QListView,
    model: qt6.QAbstractListModel,
    no_results: qt6.QLabel,
    focus_guard: qt6.QTimer,
};
