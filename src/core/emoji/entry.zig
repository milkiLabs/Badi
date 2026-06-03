// Emoji entry. One record from the binary slab. The struct holds byte
// slices that point into the @embedFile'd blob — no string allocation at
// runtime. Only the slice of entries is owned by the caller.

const std = @import("std");

/// A single emoji. All slices point at read-only memory owned by the
/// embedded binary blob; do not free them.
pub const EmojiEntry = struct {
    /// The glyph itself (e.g. "😀"). UTF-8, may be a multi-codepoint
    /// sequence (ZWJ, regional indicators, etc.).
    glyph: []const u8,
    /// Human-readable name from the Unicode CLDR (e.g. "grinning face").
    name: []const u8,
    /// Joined searchable text: "<name> <kw1> <kw2> ...", lowercase ASCII.
    /// Used by `core.filter.filter` to match user queries via the same
    /// substring/multi-token/acronym scoring used for app names.
    keywords: []const u8,
};

/// Comptime accessor for `core.filter.filter`. The full joined haystack
/// is searched so user queries match against the name and any keyword.
pub fn searchableOf(e: EmojiEntry) []const u8 {
    return e.keywords;
}
