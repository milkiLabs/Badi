const std = @import("std");

pub const ScoredItem = struct {
    index: usize,
    score: i64,
};

pub const max_results = 50;

/// Score `query` against `candidate`.
/// Returns >= 0 if it matches (higher = better), -1 if no match.
pub fn score(query: []const u8, candidate: []const u8) i64 {
    if (query.len == 0 or candidate.len == 0) return -1;

    var qbuf: [128]u8 = undefined;
    var cbuf: [256]u8 = undefined;
    const q = normalize(query, &qbuf) orelse return -1;
    const c = normalize(candidate, &cbuf) orelse return -1;
    if (q.len == 0) return -1;

    // Direct substring match (single token)
    if (std.mem.indexOf(u8, c, q)) |pos| {
        return @as(i64, @intCast(10000 - pos));
    }

    // Multi-token: each space-separated piece must appear in order
    if (tokenScore(q, c)) |s| return s;

    // Acronym: query is prefix of the first-letter acronym
    if (acronymScore(q, c)) |s| return s;

    return -1;
}

/// Score all items, return up to `out.len` sorted by score descending.
pub fn search(items: []const []const u8, query: []const u8, out: []ScoredItem) usize {
    std.debug.assert(query.len > 0);

    var count: usize = 0;
    for (items, 0..) |item, i| {
        const s = score(query, item);
        if (s >= 0) {
            if (count < out.len) {
                out[count] = .{ .index = i, .score = s };
                count += 1;
            }
        }
    }

    std.mem.sort(ScoredItem, out[0..count], {}, struct {
        fn desc(_: void, a: ScoredItem, b: ScoredItem) bool {
            if (a.score != b.score) return a.score > b.score;
            return a.index < b.index;
        }
    }.desc);

    return count;
}

/// Like `search` but maps each item to a searchable string via a comptime getter,
/// avoiding intermediate allocations for heterogeneous collections (e.g. DesktopEntry[]).
pub fn searchMapped(
    comptime T: type,
    comptime getText: fn (T) []const u8,
    items: []const T,
    query: []const u8,
    out: []ScoredItem,
) usize {
    std.debug.assert(query.len > 0);

    var count: usize = 0;
    for (items, 0..) |item, i| {
        const s = score(query, getText(item));
        if (s >= 0) {
            if (count < out.len) {
                out[count] = .{ .index = i, .score = s };
                count += 1;
            }
        }
    }

    std.mem.sort(ScoredItem, out[0..count], {}, struct {
        fn desc(_: void, a: ScoredItem, b: ScoredItem) bool {
            if (a.score != b.score) return a.score > b.score;
            return a.index < b.index;
        }
    }.desc);

    return count;
}

// --- Internals ---

fn normalize(text: []const u8, buf: []u8) ?[]const u8 {
    if (text.len > buf.len) return null;
    for (text, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    return buf[0..text.len];
}

/// Multi-token: split query on whitespace, each token must appear as a
/// substring after the previous token's position.
fn tokenScore(q: []const u8, c: []const u8) ?i64 {
    var total_pos: i64 = 0;
    var search_start: usize = 0;
    var first_pos: ?usize = null;

    var i: usize = 0;
    while (i < q.len) {
        while (i < q.len and isSpace(q[i])) : (i += 1) {}
        if (i >= q.len) break;
        const tok_start = i;
        while (i < q.len and !isSpace(q[i])) : (i += 1) {}
        const token = q[tok_start..i];

        const pos = std.mem.indexOf(u8, c[search_start..], token) orelse return null;
        const abs_pos = search_start + pos;
        if (first_pos == null) first_pos = abs_pos;
        total_pos += @as(i64, @intCast(abs_pos));
        search_start = abs_pos + 1;
    }

    // Single-token case already handled by the direct substring check above,
    // so if we get here with one token, the query must have been split on a
    // non-space separator (unlikely for our tokenizer). Return early anyway.
    // For multi-token: score drops as positions increase and spread grows.
    const first = @as(i64, @intCast(first_pos orelse return null));
    const spread = total_pos - first;
    return 9000 - first - spread;
}

/// Acronym match: build first-letter acronym of candidate, check if query
/// is a prefix of it.
fn acronymScore(q: []const u8, c: []const u8) ?i64 {
    var buf: [128]u8 = undefined;
    var len: usize = 0;
    var boundary = true;
    for (c) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            if (boundary and len < buf.len) {
                buf[len] = ch;
                len += 1;
            }
            boundary = false;
        } else {
            boundary = true;
        }
    }
    const acr = buf[0..len];
    if (acr.len >= q.len and std.mem.eql(u8, acr[0..q.len], q)) {
        return 5000;
    }
    return null;
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// --- Tests ---

test "exact match" {
    try std.testing.expectEqual(10000, score("firefox", "firefox"));
}

test "case insensitive" {
    try std.testing.expectEqual(10000, score("Firefox", "firefox"));
    try std.testing.expectEqual(10000, score("FIREFOX", "Firefox"));
}

test "prefix match beats later position" {
    const prefix = score("fire", "firefox");
    const later = score("fox", "firefox");
    try std.testing.expect(prefix > later);
}

test "contains match at various positions" {
    try std.testing.expectEqual(10000, score("fire", "firefox"));
    try std.testing.expectEqual(9999, score("iref", "firefox")); // pos 1
    try std.testing.expectEqual(9997, score("efox", "firefox")); // pos 3
}

test "no match returns -1" {
    try std.testing.expectEqual(@as(i64, -1), score("xyz", "firefox"));
    try std.testing.expectEqual(@as(i64, -1), score("zzz", "abc"));
}

test "empty query returns -1" {
    try std.testing.expectEqual(@as(i64, -1), score("", "firefox"));
}

test "empty candidate returns -1" {
    try std.testing.expectEqual(@as(i64, -1), score("fire", ""));
}

test "multi-token matching" {
    const s = score("web cam", "web camera");
    try std.testing.expect(s >= 0);
    try std.testing.expect(s > score("cam web", "web camera"));
}

test "multi-token out of order" {
    try std.testing.expectEqual(@as(i64, -1), score("cam web", "web camera"));
}

test "acronym match" {
    try std.testing.expectEqual(5000, score("gm", "google maps"));
    try std.testing.expectEqual(5000, score("wc", "word counter"));
    try std.testing.expectEqual(5000, score("ff", "fast fox"));
}

test "acronym longer than query" {
    // "g" matches "google maps" as a substring (pos 0), which is stronger than acronym
    try std.testing.expectEqual(10000, score("g", "google maps"));
}

test "search returns sorted by score" {
    const items = [_][]const u8{ "aaa", "bbb file", "aaa file" };
    var buf: [max_results]ScoredItem = undefined;
    const n = search(&items, "aaa", &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(usize, 0), buf[0].index); // "aaa" at pos 0
    try std.testing.expectEqual(@as(usize, 2), buf[1].index); // "aaa file" at pos 0 too, but higher index
}

test "search caps at max_results" {
    var items: [60][]const u8 = undefined;
    for (&items) |*item| item.* = "test item";
    var buf: [max_results]ScoredItem = undefined;
    const n = search(&items, "test", &buf);
    try std.testing.expect(n <= max_results);
}

test "summit matches summits path" {
    const path = "/media/Maind/كتب/Summitt's Fundamentals of Operative Dentistry A Contemporary Approach - Chapter 7.pdf";
    try std.testing.expect(score("summit", path) >= 0);
}

test "dental matches dental path" {
    const path = "/media/Maind/Dental_books/operative/Summitt's Fundamentals of Operative Dentistry.pdf";
    try std.testing.expect(score("dental", path) >= 0);
}

test "single-token direct match takes priority" {
    // "ff" matches "fast fox" via acronym, but also appears as substring in "coffee"
    const sub = score("ff", "coffee");
    const acr = score("ff", "fast fox");
    try std.testing.expect(sub >= 0);
    try std.testing.expectEqual(5000, acr);
}
