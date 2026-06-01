// Pure filter step: takes a source slice, a query, and a comptime accessor,
// writes the top-N source indices into an output buffer, sorted by score
// descending.
// This is the testable core of "what rows should the user see?";
// `ui/view.zig` wraps it with the model reset and selection.

const std = @import("std");
const search = @import("search.zig");

/// Fills `out_indices` with indices into `source`, in display order
/// (best match first). Returns the number of indices written.
///
/// - `comptime T`: the source element type.
/// - `comptime getText`: a compile-time accessor that returns the
///   searchable string for a given element. For `[]const u8` sources,
///   use `struct { fn f(s: []const u8) []const u8 { return s; } }.f`.
/// - `query`: empty → source order (up to `out_indices.len` items).
/// - `out_indices`: caller-owned; only the first `return` slots are written.
/// - `scratch`: caller-owned scratch space for scoring. Must be at least
///   `@min(source.len, out_indices.len)` elements; `source.len` is ideal
///   to avoid missing high-scoring items that appear late in the source.
///
/// The output is capped at `out_indices.len` — no hidden limit. The
/// function performs zero heap allocations.
pub fn filter(
    comptime T: type,
    comptime getText: fn (T) []const u8,
    source: []const T,
    query: []const u8,
    out_indices: []usize,
    scratch: []search.ScoredItem,
) usize {
    if (source.len == 0) return 0;
    const cap = out_indices.len;

    if (query.len == 0) {
        // Empty query: source order, no scoring.
        const n = @min(source.len, cap);
        for (0..n) |i| out_indices[i] = i;
        return n;
    }

    const n_scored = search.searchMapped(T, getText, source, query, scratch);
    const n = @min(n_scored, cap);
    for (scratch[0..n], 0..) |item, i| out_indices[i] = item.index;
    return n;
}

test "filter returns source order for empty query" {
    const items = [_][]const u8{ "alpha", "beta", "gamma" };
    var out: [10]usize = undefined;
    var scratch: [3]search.ScoredItem = undefined;
    const n = filter([]const u8, struct {
        fn f(s: []const u8) []const u8 {
            return s;
        }
    }.f, &items, "", &out, &scratch);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqual(@as(usize, 0), out[0]);
    try std.testing.expectEqual(@as(usize, 1), out[1]);
    try std.testing.expectEqual(@as(usize, 2), out[2]);
}

test "filter sorts by score for non-empty query" {
    const items = [_][]const u8{ "zzz", "alpine", "alpha" };
    var out: [10]usize = undefined;
    var scratch: [3]search.ScoredItem = undefined;
    const n = filter([]const u8, struct {
        fn f(s: []const u8) []const u8 {
            return s;
        }
    }.f, &items, "alp", &out, &scratch);
    try std.testing.expectEqual(@as(usize, 2), n);
    // Both "alpine" and "alpha" match "alp" at position 0 (score 10000).
    // Ties break by source order (lower index first): alpine=1, alpha=2.
    try std.testing.expectEqual(@as(usize, 1), out[0]);
    try std.testing.expectEqual(@as(usize, 2), out[1]);
}

test "filter respects output cap" {
    const items = [_][]const u8{ "alpha", "alph", "alp" };
    var out: [1]usize = undefined;
    var scratch: [3]search.ScoredItem = undefined;
    const n = filter([]const u8, struct {
        fn f(s: []const u8) []const u8 {
            return s;
        }
    }.f, &items, "alp", &out, &scratch);
    try std.testing.expectEqual(@as(usize, 1), n);
}

test "filter on empty source returns zero" {
    var out: [10]usize = undefined;
    var scratch: [1]search.ScoredItem = undefined;
    const n = filter([]const u8, struct {
        fn f(s: []const u8) []const u8 {
            return s;
        }
    }.f, &.{}, "anything", &out, &scratch);
    try std.testing.expectEqual(@as(usize, 0), n);
}
