// FreeDesktop .desktop Exec= string parser.
//
// Parses exec strings like `env FOO="bar" app --flag %U` into a clean argv
// array. Handles single/double quotes, backslash escapes, and strips desktop
// field codes (%f, %F, %u, %U, etc). Also provides POSIX shell quoting for
// prefix mode.
//
// Pure Zig — no Qt dependencies.

const std = @import("std");

/// Error set for exec parsing — combines parse errors with allocation errors.
pub const ParseError = error{
    EmptyExec,
    UnterminatedQuote,
    InvalidFieldCode,
} || std.mem.Allocator.Error;

/// Parsed launch command — owns all strings in argv.
pub const LaunchCommand = struct {
    allocator: std.mem.Allocator,
    argv: []const []const u8,

    pub fn program(self: LaunchCommand) []const u8 {
        return self.argv[0];
    }

    pub fn args(self: LaunchCommand) []const []const u8 {
        return self.argv[1..];
    }

    pub fn deinit(self: *LaunchCommand) void {
        for (self.argv) |arg| self.allocator.free(arg);
        self.allocator.free(self.argv);
        self.argv = &.{};
    }
};

/// Parses an exec string into a LaunchCommand (program + args).
/// Steps: tokenize → strip field codes → filter empty tokens → return argv.
pub fn parseExec(allocator: std.mem.Allocator, exec: []const u8) ParseError!LaunchCommand {
    var raw_tokens: std.ArrayList([]const u8) = .empty;
    defer {
        for (raw_tokens.items) |token| allocator.free(token);
        raw_tokens.deinit(allocator);
    }

    try tokenizeExec(allocator, exec, &raw_tokens);

    var argv: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (argv.items) |arg| allocator.free(arg);
        argv.deinit(allocator);
    }

    for (raw_tokens.items) |token| {
        const cleaned = try stripFieldCodes(allocator, token);
        if (cleaned.len == 0) {
            allocator.free(cleaned);
            continue;
        }
        argv.append(allocator, cleaned) catch |err| {
            allocator.free(cleaned);
            return err;
        };
    }

    if (argv.items.len == 0) return error.EmptyExec;

    return .{
        .allocator = allocator,
        .argv = try argv.toOwnedSlice(allocator),
    };
}

/// Wraps an argument in single quotes for safe shell usage.
/// Escapes embedded single quotes: can't → 'can'\''t'
pub fn quoteShellArg(allocator: std.mem.Allocator, arg: []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.append(allocator, '\'');
    for (arg) |ch| {
        if (ch == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '\'');

    return out.toOwnedSlice(allocator);
}

/// Tokenizes an exec string respecting quotes and escapes.
/// Whitespace separates tokens; quotes group words; backslash escapes the next char.
fn tokenizeExec(allocator: std.mem.Allocator, exec: []const u8, tokens: *std.ArrayList([]const u8)) ParseError!void {
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);

    var quote: ?u8 = null;
    var escaped = false;
    var saw_token = false;

    for (exec) |ch| {
        if (escaped) {
            try current.append(allocator, ch);
            saw_token = true;
            escaped = false;
            continue;
        }

        if (ch == '\\') {
            escaped = true;
            saw_token = true;
            continue;
        }

        if (quote) |q| {
            if (ch == q) {
                quote = null;
            } else {
                try current.append(allocator, ch);
            }
            saw_token = true;
            continue;
        }

        if (ch == '"' or ch == '\'') {
            quote = ch;
            saw_token = true;
            continue;
        }

        if (std.ascii.isWhitespace(ch)) {
            if (saw_token) {
                try appendCurrentToken(allocator, tokens, &current);
                saw_token = false;
            }
            continue;
        }

        try current.append(allocator, ch);
        saw_token = true;
    }

    if (escaped) try current.append(allocator, '\\');
    if (quote != null) return error.UnterminatedQuote;
    if (saw_token) try appendCurrentToken(allocator, tokens, &current);
}

fn appendCurrentToken(allocator: std.mem.Allocator, tokens: *std.ArrayList([]const u8), current: *std.ArrayList(u8)) ParseError!void {
    const token = try current.toOwnedSlice(allocator);
    tokens.append(allocator, token) catch |err| {
        allocator.free(token);
        return err;
    };
}

/// Removes desktop field codes (%f, %F, %u, %U, etc) from a token.
/// %% becomes a literal %. Unknown codes are errors per the XDG spec.
fn stripFieldCodes(allocator: std.mem.Allocator, token: []const u8) ParseError![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < token.len) : (i += 1) {
        if (token[i] != '%') {
            try out.append(allocator, token[i]);
            continue;
        }

        if (i + 1 >= token.len) {
            return error.InvalidFieldCode;
        }

        const code = token[i + 1];
        if (code == '%') {
            try out.append(allocator, '%');
            i += 1;
        } else if (isDesktopFieldCode(code)) {
            i += 1;
        } else {
            return error.InvalidFieldCode;
        }
    }

    return out.toOwnedSlice(allocator);
}

fn isDesktopFieldCode(code: u8) bool {
    return switch (code) {
        'f', 'F', 'u', 'U', 'd', 'D', 'n', 'N', 'i', 'c', 'k', 'v', 'm' => true,
        else => false,
    };
}

test "parseExec handles quotes and field codes" {
    var cmd = try parseExec(std.testing.allocator, "env FOO=\"two words\" app --open %U --literal=%%");
    defer cmd.deinit();

    try std.testing.expectEqual(@as(usize, 5), cmd.argv.len);
    try std.testing.expectEqualStrings("env", cmd.argv[0]);
    try std.testing.expectEqualStrings("FOO=two words", cmd.argv[1]);
    try std.testing.expectEqualStrings("app", cmd.argv[2]);
    try std.testing.expectEqualStrings("--open", cmd.argv[3]);
    try std.testing.expectEqualStrings("--literal=%", cmd.argv[4]);
}

test "parseExec handles escaped spaces" {
    var cmd = try parseExec(std.testing.allocator, "/opt/My\\ App/bin/app --name Test");
    defer cmd.deinit();

    try std.testing.expectEqual(@as(usize, 3), cmd.argv.len);
    try std.testing.expectEqualStrings("/opt/My App/bin/app", cmd.program());
    try std.testing.expectEqualStrings("--name", cmd.args()[0]);
    try std.testing.expectEqualStrings("Test", cmd.args()[1]);
}

test "parseExec rejects empty and unterminated input" {
    try std.testing.expectError(error.EmptyExec, parseExec(std.testing.allocator, " %U "));
    try std.testing.expectError(error.UnterminatedQuote, parseExec(std.testing.allocator, "app \"broken"));
    try std.testing.expectError(error.InvalidFieldCode, parseExec(std.testing.allocator, "app %Z"));
    try std.testing.expectError(error.InvalidFieldCode, parseExec(std.testing.allocator, "app %"));
}

test "quoteShellArg emits a single POSIX shell argument" {
    const quoted = try quoteShellArg(std.testing.allocator, "can't touch /tmp/a b");
    defer std.testing.allocator.free(quoted);

    try std.testing.expectEqualStrings("'can'\\''t touch /tmp/a b'", quoted);
}
