// Public surface of the emoji module.

pub const EmojiEntry = @import("entry.zig").EmojiEntry;
pub const EmojiData = @import("loader.zig").EmojiData;
pub const nameOf = @import("entry.zig").nameOf;
pub const searchableOf = @import("entry.zig").searchableOf;
pub const loadEmojis = @import("loader.zig").loadEmojis;
