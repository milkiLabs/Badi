// CLI flag parsing. Currently just `--prompt` (with optional inline label,
// --default, --password, --allow-empty). Other flags can be added here
// without touching anything else.

const std = @import("std");
const state = @import("../state/mod.zig");

/// Settings derived from the command line. The prompt config slices
/// borrow from `arena` (the init arena), which is process-long-lived.
pub const Settings = struct {
    /// Set when --prompt was passed. The launcher's prompt mode reads
    /// this; otherwise it falls through to stdin-pipe / apps detection.
    prompt: ?state.PromptConfig = null,
};

/// Materializes the args slice into `arena`, then parses flags.
/// `arena` must outlive the returned Settings (its slices are borrowed
/// from the materialized slice).
pub fn parse(arena: std.mem.Allocator, args: std.process.Args) !Settings {
    const args_slice = try args.toSlice(arena);
    return .{ .prompt = try parsePromptFlags(args_slice) };
}

fn parsePromptFlags(args: []const [:0]const u8) !?state.PromptConfig {
    var i: usize = 0;
    var has_prompt = false;
    var label: []const u8 = "";
    var default_value: []const u8 = "";
    var password = false;
    var allow_empty = false;

    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--prompt")) {
            has_prompt = true;
            // Optional inline label: the next arg, only if it doesn't start with "-".
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                label = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, a, "--default")) {
            if (i + 1 >= args.len) return error.MissingValueForDefault;
            default_value = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--password")) {
            password = true;
        } else if (std.mem.eql(u8, a, "--allow-empty")) {
            allow_empty = true;
        }
    }

    if (!has_prompt) return null;
    return .{
        .label = label,
        .default_value = default_value,
        .password = password,
        .allow_empty = allow_empty,
    };
}
