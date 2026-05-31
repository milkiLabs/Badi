// Fuzzy search with hierarchical scoring.
//
// Provides typo-tolerant, relevance-ranked search for app names and piped
// input lines. Adapted from the QueryRanker algorithm in the milki launcher.
//
// Scoring hierarchy (highest to lowest):
//   Exact > Prefix > Word prefix > Contains > Acronym > Token > Typo > Subsequence
//
// Pure Zig — no Qt dependencies.

const std = @import("std");

pub const ScoredItem = struct {
    index: usize,
    score: i32,
};

const Score = i32;

const exact_match: Score = 10_000;
const prefix_match: Score = 9_000;
const word_prefix_match: Score = 8_500;
const contains_match: Score = 7_500;
const acronym_match: Score = 7_000;
const token_match: Score = 6_700;
const typo_match: Score = 5_900;
const subsequence_match: Score = 5_400;

const prefix_quality_max: Score = 100;
const typo_distance_penalty: Score = 160;
const min_subsequence_length = 2;
const min_typo_length = 3;
const long_query_min_length = 6;
pub const max_results = 50;

const TokenPos = struct {
    start: usize,
    end: usize,
};

// --- Public API ---

/// Returns the fuzzy match score for `query` against `candidate`.
/// Returns -1 if no match.
pub fn score(query: []const u8, candidate: []const u8) Score {
    if (query.len == 0 or candidate.len == 0) return -1;

    var q_buf: [128]u8 = undefined;
    const q = normalize(query, &q_buf) orelse return -1;
    var c_buf: [256]u8 = undefined;
    const c = normalize(candidate, &c_buf) orelse return -1;

    if (q.len == 0) return -1;

    // 1. Exact match
    if (std.mem.eql(u8, q, c)) return exact_match;

    // 2. Prefix match
    if (std.mem.startsWith(u8, c, q)) {
        return prefix_match + prefixQuality(c, q);
    }

    // 3. Word prefix match (query at a word boundary)
    if (wordPrefixMatch(c, q)) {
        return word_prefix_match + prefixQuality(c, q);
    }

    // 4. Contains match
    if (std.mem.indexOf(u8, c, q)) |pos| {
        return contains_match - @as(Score, @intCast(pos));
    }

    // 5. Acronym match
    var abuf: [128]u8 = undefined;
    const acronym = buildAcronym(c, &abuf);
    if (acronym.len > 0 and std.mem.startsWith(u8, acronym, q)) {
        return acronym_match;
    }

    // 6. Token match (all space-separated query tokens found)
    {
        var q_tokens_buf: [16]TokenPos = undefined;
        const q_token_count = tokenize(q, &q_tokens_buf);
        if (q_token_count > 1) {
            var all_covered = true;
            for (q_tokens_buf[0..q_token_count]) |tp| {
                if (!tokenCovered(tokenAt(q, tp), c, acronym)) {
                    all_covered = false;
                    break;
                }
            }
            if (all_covered) return token_match;
        }
    }

    // 7. Typo match (Levenshtein)
    if (q.len >= min_typo_length) {
        if (typoScore(q, c)) |s| return s;
    }

    // 8. Subsequence match
    if (q.len >= min_subsequence_length and isSubsequence(q, c)) {
        return subsequence_match - subsequenceSpread(q, c);
    }

    return -1;
}

/// Scores all items, filters matches (score >= 0), sorts by score descending,
/// and returns up to `max_results` scored items. Caller owns the returned slice.
pub fn search(items: []const []const u8, query: []const u8, allocator: std.mem.Allocator) ![]ScoredItem {
    if (query.len == 0) {
        const count = @min(items.len, max_results);
        const result = try allocator.alloc(ScoredItem, count);
        for (result, 0..) |*r, i| {
            r.* = .{ .index = i, .score = 0 };
        }
        return result;
    }

    var scored: std.ArrayListUnmanaged(ScoredItem) = .empty;
    errdefer scored.deinit(allocator);

    for (items, 0..) |item, i| {
        const s = score(query, item);
        if (s >= 0) {
            try scored.append(allocator, .{ .index = i, .score = s });
        }
    }

    // Sort by score descending, then by index for stable ordering
    std.mem.sort(ScoredItem, scored.items, {}, struct {
        fn cmp(_: void, a: ScoredItem, b: ScoredItem) bool {
            if (a.score != b.score) return a.score > b.score;
            return a.index < b.index;
        }
    }.cmp);

    const limit = @min(scored.items.len, max_results);
    const result = try allocator.alloc(ScoredItem, limit);
    @memcpy(result, scored.items[0..limit]);
    scored.deinit(allocator);
    return result;
}

// --- Internal helpers ---

fn normalize(text: []const u8, buf: []u8) ?[]const u8 {
    if (text.len > buf.len) return null;
    for (text, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    return buf[0..text.len];
}

fn prefixQuality(text: []const u8, query: []const u8) Score {
    const diff = @as(Score, @intCast(text.len)) - @as(Score, @intCast(query.len));
    return @max(0, prefix_quality_max - diff);
}

fn wordPrefixMatch(text: []const u8, query: []const u8) bool {
    if (text.len < query.len) return false;
    var i: usize = 0;
    while (i <= text.len - query.len) : (i += 1) {
        const at_boundary = i == 0 or !std.ascii.isAlphanumeric(text[i - 1]);
        if (at_boundary and std.mem.eql(u8, text[i .. i + query.len], query)) {
            return true;
        }
    }
    return false;
}

fn buildAcronym(text: []const u8, buf: []u8) []const u8 {
    var len: usize = 0;
    var boundary = true;
    for (text) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            if (boundary and len < buf.len) {
                buf[len] = c;
                len += 1;
            }
            boundary = false;
        } else {
            boundary = true;
        }
    }
    return buf[0..len];
}

fn tokenize(text: []const u8, tokens_buf: []TokenPos) usize {
    var count: usize = 0;
    var start: ?usize = null;
    for (text, 0..) |c, i| {
        if (std.ascii.isAlphanumeric(c)) {
            if (start == null) start = i;
        } else if (start) |s| {
            if (count < tokens_buf.len) {
                tokens_buf[count] = .{ .start = s, .end = i };
                count += 1;
            }
            start = null;
        }
    }
    if (start) |s| {
        if (count < tokens_buf.len) {
            tokens_buf[count] = .{ .start = s, .end = text.len };
            count += 1;
        }
    }
    return count;
}

fn tokenAt(text: []const u8, pos: TokenPos) []const u8 {
    return text[pos.start..pos.end];
}

fn tokenCovered(token: []const u8, text: []const u8, acronym: []const u8) bool {
    if (std.mem.indexOf(u8, text, token) != null) return true;
    if (acronym.len >= token.len and std.mem.startsWith(u8, acronym, token)) return true;
    if (token.len >= min_typo_length) {
        if (bestTokenDistance(token, text) != null) return true;
    }
    return false;
}

fn isSubsequence(query: []const u8, text: []const u8) bool {
    if (query.len > text.len) return false;
    var qi: usize = 0;
    var ti: usize = 0;
    while (qi < query.len and ti < text.len) {
        if (query[qi] == text[ti]) qi += 1;
        ti += 1;
    }
    return qi == query.len;
}

fn subsequenceSpread(query: []const u8, text: []const u8) Score {
    var qi: usize = 0;
    var first: ?usize = null;
    var last: usize = 0;
    for (text, 0..) |c, i| {
        if (qi < query.len and c == query[qi]) {
            if (first == null) first = i;
            last = i;
            qi += 1;
        }
    }
    if (first == null) return @intCast(text.len);
    return @as(Score, @intCast(last)) - @as(Score, @intCast(first.?)) - @as(Score, @intCast(query.len));
}

fn maxEditDistance(query_len: usize) i32 {
    if (query_len >= long_query_min_length) return 2;
    if (query_len >= min_typo_length) return 1;
    return 0;
}

fn typoScore(query: []const u8, text: []const u8) ?Score {
    const best = bestTokenDistance(query, text) orelse return null;
    const max_d = maxEditDistance(query.len);
    if (best > max_d) return null;
    const len_diff = if (text.len > query.len)
        @as(Score, @intCast(text.len - query.len))
    else
        @as(Score, @intCast(query.len - text.len));
    return typo_match - (best * typo_distance_penalty) - len_diff;
}

fn bestTokenDistance(query: []const u8, text: []const u8) ?i32 {
    var tokens_buf: [16]TokenPos = undefined;
    const count = tokenize(text, &tokens_buf);
    if (count == 0) return null;

    const max_d = maxEditDistance(query.len);
    var best: i32 = std.math.maxInt(i32);
    for (tokens_buf[0..count]) |tp| {
        const token = tokenAt(text, tp);
        const len_diff = if (query.len > token.len)
            query.len - token.len
        else
            token.len - query.len;
        if (len_diff <= @as(usize, @intCast(max_d))) {
            const d = levenshtein(query, token);
            if (d < best) best = d;
        }
    }
    if (best == std.math.maxInt(i32)) return null;
    return best;
}

fn levenshtein(a: []const u8, b: []const u8) i32 {
    if (std.mem.eql(u8, a, b)) return 0;
    if (a.len == 0) return @intCast(b.len);
    if (b.len == 0) return @intCast(a.len);

    const m = b.len;
    if (m + 1 > 128) return @intCast(a.len + b.len);

    var bufs: [2][128]i32 = undefined;
    var prev_idx: usize = 0;

    // Initialize row 0
    for (0..m + 1) |j| {
        bufs[0][j] = @intCast(j);
    }

    for (0..a.len) |i| {
        const curr_idx = prev_idx ^ 1;
        bufs[curr_idx][0] = @intCast(i + 1);
        for (0..m) |j| {
            const cost: i32 = if (a[i] == b[j]) 0 else 1;
            bufs[curr_idx][j + 1] = @min(bufs[curr_idx][j] + 1, bufs[prev_idx][j + 1] + 1, bufs[prev_idx][j] + cost);
        }
        prev_idx = curr_idx;
    }

    return bufs[prev_idx][m];
}

// --- Tests ---

test "exact match" {
    try std.testing.expectEqual(exact_match, score("firefox", "firefox"));
    try std.testing.expectEqual(exact_match, score("Firefox", "firefox"));
    try std.testing.expectEqual(exact_match, score("FIREFOX", "Firefox"));
}

test "prefix match beats contains" {
    const p = score("fir", "firefox");
    const c = score("ire", "firefox");
    try std.testing.expect(p > c);
    try std.testing.expect(p >= prefix_match);
}

test "prefix quality — shorter name wins" {
    const short = score("fire", "firefox");
    const long_ = score("fire", "firefox developer edition");
    try std.testing.expect(short > long_);
}

test "word prefix beats generic contains" {
    const wp = score("map", "google maps");
    // "map" at word boundary in "google maps" → word_prefix
    // "map" inside "imap connection" (not at word boundary) → contains only
    const c = score("map", "imap connection");
    try std.testing.expect(wp >= word_prefix_match);
    try std.testing.expect(c < word_prefix_match);
}

test "contains match with position penalty" {
    const early = score("ire", "firefox");
    const late = score("ire", "xfirefox");
    try std.testing.expect(early > late);
}

test "acronym match" {
    try std.testing.expectEqual(acronym_match, score("gm", "google maps"));
    try std.testing.expectEqual(acronym_match, score("wc", "word counter"));
    // "ff" matches acronym of "fast fox" → "ff"
    try std.testing.expectEqual(acronym_match, score("ff", "fast fox"));
}

test "token match — multi-word query" {
    const s = score("web cam", "web camera");
    try std.testing.expect(s >= token_match);
}

test "typo tolerance — 1 edit short query" {
    // "fireox" → "firefo" (missing 'f') = 1 edit, len 6 → max 2 edits
    const s = score("fireox", "firefox");
    try std.testing.expect(s > 0);
    // Also test with a direct 1-edit case
    const s2 = score("firefho", "firefox");
    try std.testing.expect(s2 > 0);
}

test "typo tolerance — 2 edits long query" {
    // "firefoox" → "firefox" = 1 edit (insert 'o'), len 8 → max 2 edits
    const s = score("firefoox", "firefox");
    try std.testing.expect(s > 0);
}

test "no typo tolerance for very short queries" {
    // "xz" is too short (2 chars) for typo tolerance and doesn't match "firefox" at any tier
    try std.testing.expectEqual(@as(i32, -1), score("xz", "firefox"));
}

test "subsequence match" {
    const s = score("ffx", "firefox");
    try std.testing.expect(s > 0);
    // f,f,x found in order at positions 0,3,6 → spread=3
    try std.testing.expect(s == subsequence_match - 3);
}

test "subsequence spread penalty" {
    // "ffx" in "ffxtools" (tight: f(0),f(1),x(2)) vs "fabcd eff abcx" (spread: f(0),f(7),x(14))
    const tight = score("ffx", "ffxtools");
    const spread = score("ffx", "fabcd eff abcx");
    try std.testing.expect(tight > 0);
    try std.testing.expect(spread > 0);
    try std.testing.expect(tight > spread);
}

test "no match returns -1" {
    try std.testing.expectEqual(@as(i32, -1), score("xyz", "firefox"));
    try std.testing.expectEqual(@as(i32, -1), score("zzz", "abc"));
}

test "empty query returns -1" {
    try std.testing.expectEqual(@as(i32, -1), score("", "firefox"));
}

test "empty candidate returns -1" {
    try std.testing.expectEqual(@as(i32, -1), score("fir", ""));
}

test "search returns sorted by score" {
    const items = [_][]const u8{ "firefox", "file manager", "firefox developer edition" };
    const allocator = std.testing.allocator;
    const results = try search(&items, "fire", allocator);
    defer allocator.free(results);
    try std.testing.expect(results.len >= 2);
    try std.testing.expect(results[0].score >= results[1].score);
}

test "search caps at max_results" {
    var items: [60][]const u8 = undefined;
    for (&items, 0..) |*item, i| {
        _ = i;
        item.* = "test item";
    }
    const allocator = std.testing.allocator;
    const results = try search(&items, "test", allocator);
    defer allocator.free(results);
    try std.testing.expect(results.len <= max_results);
}

test "search empty query returns all items" {
    const items = [_][]const u8{ "alpha", "beta", "gamma" };
    const allocator = std.testing.allocator;
    const results = try search(&items, "", allocator);
    defer allocator.free(results);
    try std.testing.expectEqual(@as(usize, 3), results.len);
}
