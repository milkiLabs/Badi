// CLI flag parsing. Supports:
//   --prompt [LABEL] [--default TEXT] [--password] [--allow-empty]
//   --emoji [--copy|--print|--type]
//
// Adding a new flag is a single-pass change here.

const std = @import("std");
const state = @import("../state/mod.zig");

/// Settings derived from the command line. The prompt/emoji config slices
/// borrow from `arena` (the init arena), which is process-long-lived.
pub const Settings = struct {
    /// Set when --prompt was passed. The launcher's prompt mode reads
    /// this; otherwise it falls through to stdin-pipe / apps detection.
    prompt: ?state.PromptConfig = null,
    /// Set when --emoji was passed. Mutually exclusive with --prompt.
    emoji: ?state.EmojiConfig = null,
};

/// Materializes the args slice into `arena`, then parses flags.
/// `arena` must outlive the returned Settings (its slices are borrowed
/// from the materialized slice).
pub fn parse(arena: std.mem.Allocator, args: std.process.Args) !Settings {
    const args_slice = try args.toSlice(arena);
    var settings: Settings = .{};
    var i: usize = 0;
    while (i < args_slice.len) : (i += 1) {
        const a = args_slice[i];
        if (std.mem.eql(u8, a, "--prompt")) {
            if (settings.emoji != null) return error.PromptAndEmojiExclusive;
            settings.prompt = try parsePromptAt(args_slice, &i);
        } else if (std.mem.eql(u8, a, "--emoji")) {
            if (settings.prompt != null) return error.PromptAndEmojiExclusive;
            settings.emoji = try parseEmojiAt(args_slice, &i);
        }
    }
    return settings;
}

/// Parses the --prompt flag and any of its trailing flag/label arguments
/// starting at `i` (which points at the "--prompt" token). Advances `i`
/// past all consumed args.
fn parsePromptAt(args: []const [:0]const u8, i: *usize) !state.PromptConfig {
    var label: []const u8 = "";
    var default_value: []const u8 = "";
    var password = false;
    var allow_empty = false;

    if (i.* + 1 < args.len and !std.mem.startsWith(u8, args[i.* + 1], "-")) {
        label = args[i.* + 1];
        i.* += 1;
    }
    // After the optional label, scan remaining args for prompt-specific flags.
    // We use a separate inner loop to avoid re-scanning consumed tokens.
    while (i.* + 1 < args.len) : (i.* += 1) {
        const next = args[i.* + 1];
        if (std.mem.eql(u8, next, "--default")) {
            if (i.* + 2 >= args.len) return error.MissingValueForDefault;
            default_value = args[i.* + 2];
            i.* += 1;
        } else if (std.mem.eql(u8, next, "--password")) {
            password = true;
        } else if (std.mem.eql(u8, next, "--allow-empty")) {
            allow_empty = true;
        } else if (std.mem.startsWith(u8, next, "--")) {
            // Hit a non-prompt flag (e.g. --emoji, --copy) — stop.
            break;
        } else {
            break;
        }
    }
    return .{
        .label = label,
        .default_value = default_value,
        .password = password,
        .allow_empty = allow_empty,
    };
}

/// Parses the --emoji flag and its action (--copy / --print / --type) at
/// the current position. Advances `i` past all consumed args. Sets
/// `entry = .cli` so key-handling knows to close-on-Esc (like piped/
/// prompt) rather than fall back to apps mode.
fn parseEmojiAt(args: []const [:0]const u8, i: *usize) !state.EmojiConfig {
    var cfg: state.EmojiConfig = .{ .entry = .cli };
    while (i.* + 1 < args.len) : (i.* += 1) {
        const next = args[i.* + 1];
        if (std.mem.eql(u8, next, "--copy")) {
            cfg.action = .copy;
        } else if (std.mem.eql(u8, next, "--print")) {
            cfg.action = .print;
        } else if (std.mem.eql(u8, next, "--type")) {
            cfg.action = .type_keys;
        } else if (std.mem.startsWith(u8, next, "--")) {
            break;
        } else {
            break;
        }
    }
    return cfg;
}
