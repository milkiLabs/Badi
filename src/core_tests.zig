// Test runner. `refAllDecls` causes Zig to discover every `test "..."`
// in the imported module, so adding a test anywhere in the imported
// tree automatically runs it as part of `zig build test`.
//
// Only pure-logic modules are included here. Modules that pull in
// libqt6zig (modes/, ui/) need a Qt-initialized test binary and are
// exercised manually instead.

const std = @import("std");

test {
    // Core (pure logic, no Qt)
    std.testing.refAllDecls(@import("core/mod.zig"));
    std.testing.refAllDecls(@import("core/desktop/mod.zig"));
    std.testing.refAllDecls(@import("core/emoji/mod.zig"));

    // Config (pure logic, filesystem-dependent)
    std.testing.refAllDecls(@import("config/mod.zig"));

    // State (types + global, no Qt widgets)
    std.testing.refAllDecls(@import("state/mod.zig"));

    // Utilities
    std.testing.refAllDecls(@import("utils/url.zig"));
}
