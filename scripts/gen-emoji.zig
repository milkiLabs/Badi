// Build-time tool. Reads the three vendored JSON files and emits a compact
// binary slab consumed at runtime via @embedFile in src/core/emoji/loader.zig.
//
// Inputs (paths relative to repo root):
//   vendor/unicode-emoji-by.json     — name/group metadata
//   vendor/unicode-emoji-ordered.json — CLDR ordering (top-level array of glyphs)
//   vendor/emojilib.json              — keyword list per glyph
//
// Output:
//   src/core/emoji/data/emoji.bin
//
// Layout:
//   Header (16 B)            magic "BMOJ", version u32, count u32, reserved u32
//   Records (count * 16 B)   glyph_off u32, glyph_len u16,
//                            name_off u32, name_len u16,
//                            kw_off u32, kw_len u16
//   String blob (UTF-8)      glyphs, names, joined "name k1 k2 k3" keywords
//
// All integers little-endian. The runtime loader casts the embedded byte
// slice to a `[*]const Record` via @alignCast; no parsing, no allocation
// for the string data.

const std = @import("std");
const Io = std.Io;
const fs = std.fs;

const magic = "BMOJ";
const format_version: u32 = 1;

const Record = extern struct {
    glyph_off: u32,
    glyph_len: u16,
    name_off: u32,
    name_len: u16,
    kw_off: u32,
    kw_len: u16,
};

const Header = extern struct {
    magic: [4]u8,
    version: u32,
    count: u32,
    reserved: u32,
};

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var in_dir: []const u8 = "vendor";
    var out_path: []const u8 = "src/core/emoji/data/emoji.bin";
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--in") and i + 1 < args.len) {
            in_dir = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--out") and i + 1 < args.len) {
            out_path = args[i + 1];
            i += 1;
        }
    }

    const io = init.io;

    const by_path = try std.fs.path.join(arena, &.{ in_dir, "unicode-emoji-by.json" });
    const ordered_path = try std.fs.path.join(arena, &.{ in_dir, "unicode-emoji-ordered.json" });
    const lib_path = try std.fs.path.join(arena, &.{ in_dir, "emojilib.json" });

    const by_content = try std.Io.Dir.cwd().readFileAlloc(io, by_path, arena, .unlimited);
    const ordered_content = try std.Io.Dir.cwd().readFileAlloc(io, ordered_path, arena, .unlimited);
    const lib_content = try std.Io.Dir.cwd().readFileAlloc(io, lib_path, arena, .unlimited);

    const by = try std.json.parseFromSliceLeaky(std.json.Value, arena, by_content, .{});
    const ordered = try std.json.parseFromSliceLeaky(std.json.Value, arena, ordered_content, .{});
    const lib = try std.json.parseFromSliceLeaky(std.json.Value, arena, lib_content, .{});

    const ordered_arr = switch (ordered) {
        .array => |a| a,
        else => return error.OrderedNotArray,
    };
    const by_obj = switch (by) {
        .object => |o| o,
        else => return error.ByNotObject,
    };
    const lib_obj = switch (lib) {
        .object => |o| o,
        else => return error.LibNotObject,
    };

    const count = ordered_arr.items.len;

    // Build the string blob and the Record table in one pass.
    var blob = std.ArrayList(u8).empty;
    defer blob.deinit(arena);
    var records = try arena.alloc(Record, count);

    var written: usize = 0;
    for (ordered_arr.items) |item| {
        const glyph = switch (item) {
            .string => |s| s,
            else => continue,
        };
        if (glyph.len == 0) continue;

        // Lookup metadata.
        const meta_entry = by_obj.get(glyph) orelse continue;
        const meta = switch (meta_entry) {
            .object => |o| o,
            else => continue,
        };
        const name_val = meta.get("name") orelse continue;
        const name = switch (name_val) {
            .string => |s| s,
            else => continue,
        };
        if (name.len == 0) continue;

        // Lookup keywords.
        const kw_entry = lib_obj.get(glyph) orelse continue;
        const kw_arr = switch (kw_entry) {
            .array => |a| a,
            else => continue,
        };

        // Build joined searchable text: "<name> <kw1> <kw2> ...".
        // Skip the first element — emojilib stores the slug as kws[0], which
        // is just a snake-cased version of the name. Skipping keeps the
        // searchable text leaner without losing meaningful synonyms.
        var joined_buf = std.ArrayList(u8).empty;
        defer joined_buf.deinit(arena);
        try joined_buf.appendSlice(arena, name);
        for (kw_arr.items[1..]) |kw_item| {
            const kw = switch (kw_item) {
                .string => |s| s,
                else => continue,
            };
            // Skip pure-punctuation tokens (":D", ":)", "^^") — they don't
            // match how users will type.
            if (kw.len == 0) continue;
            var all_punct = true;
            for (kw) |ch| {
                if (std.ascii.isAlphanumeric(ch)) {
                    all_punct = false;
                    break;
                }
            }
            if (all_punct) continue;
            try joined_buf.append(arena, ' ');
            try joined_buf.appendSlice(arena, kw);
        }

        const glyph_off: u32 = @intCast(blob.items.len);
        try blob.appendSlice(arena, glyph);
        const glyph_len: u16 = @intCast(glyph.len);

        const name_off: u32 = @intCast(blob.items.len);
        try blob.appendSlice(arena, name);
        const name_len: u16 = @intCast(name.len);

        const kw_off: u32 = @intCast(blob.items.len);
        try blob.appendSlice(arena, joined_buf.items);
        const kw_len: u16 = @intCast(joined_buf.items.len);

        records[written] = .{
            .glyph_off = glyph_off,
            .glyph_len = glyph_len,
            .name_off = name_off,
            .name_len = name_len,
            .kw_off = kw_off,
            .kw_len = kw_len,
        };
        written += 1;
    }

    // Shrink records to the actually-written count.
    const final_records = try arena.dupe(Record, records[0..written]);
    const header = Header{
        .magic = magic.*[0..4].*,
        .version = format_version,
        .count = @intCast(written),
        .reserved = 0,
    };

    // Offsets in each Record are absolute file positions. The blob is
    // written right after the header; the records follow. The blob's
    // `items.len` is the running file offset for new appends, so we add
    // the header size to convert blob-relative offsets to file offsets.
    const blob_base: u32 = @intCast(@sizeOf(Header));
    for (final_records) |*r| {
        r.glyph_off += blob_base;
        r.name_off += blob_base;
        r.kw_off += blob_base;
    }

    // Write the file: header, blob, records.
    const records_size: u64 = @sizeOf(Record) * @as(u64, @intCast(written));
    var out_file = try std.Io.Dir.cwd().createFile(io, out_path, .{});
    defer out_file.close(io);
    try out_file.writePositionalAll(io, std.mem.asBytes(&header), 0);
    try out_file.writePositionalAll(io, blob.items, @sizeOf(Header));
    try out_file.writePositionalAll(io, std.mem.sliceAsBytes(final_records), @sizeOf(Header) + blob.items.len);

    const total: u64 = @sizeOf(Header) + blob.items.len + records_size;
    std.debug.print("wrote {s}: {} entries, {d} bytes\n", .{ out_path, written, total });
    return 0;
}
