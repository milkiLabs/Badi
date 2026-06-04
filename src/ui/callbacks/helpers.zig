// Shared helpers for the callback modules. The mode-transition
// implementations live in `plugins/builtin.zig` (next to the static
// mode values they reference). This file re-exports them so the
// `key.zig` callback can import a single module.

pub const builtin = @import("../../plugins/builtin.zig");

pub const exitToApps = builtin.exitToApps;
pub const enterActionMode = builtin.enterActionMode;
pub const enterUrlMode = builtin.enterUrlMode;
pub const enterEmojiModeTrigger = builtin.enterEmojiModeTrigger;
