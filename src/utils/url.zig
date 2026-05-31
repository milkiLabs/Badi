const std = @import("std");

pub fn isUrl(text: []const u8) bool {
    if (std.mem.startsWith(u8, text, "http://")) return true;
    if (std.mem.startsWith(u8, text, "https://")) return true;
    
    if (std.mem.indexOfScalar(u8, text, ' ') != null) return false;
    
    if (std.mem.startsWith(u8, text, "localhost:")) return true;
    if (std.mem.eql(u8, text, "localhost")) return true;

    const last_dot = std.mem.lastIndexOfScalar(u8, text, '.') orelse return false;
    if (last_dot == 0 or last_dot == text.len - 1) return false;
    
    const tld = text[last_dot + 1 ..];
    // Any TLD with 2 or more characters is considered valid
    if (tld.len < 2) return false;
    
    for (tld) |c| {
        if (!std.ascii.isAlphabetic(c)) return false;
    }
    
    return true;
}
