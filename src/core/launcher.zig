const std = @import("std");
const qt6 = @import("libqt6zig");
const context = @import("../context.zig");
const exec = @import("exec.zig");

/// Executes the currently selected item from the Qt list widget.
pub fn executeSelection() void {
    const app = context.state();
    switch (app.mode) {
        // In piped mode, we print the selected line to stdout and exit with code 0, so the output can be captured by a shell pipe.
        .piped => {
            const row = app.ui.list.CurrentRow();
            if (row < 0) return;
            const item = app.ui.list.Item(row);
            const variant = item.Data(context.UserRole);
            defer variant.Delete();
            const data_raw = variant.ToString(app.allocator);
            defer app.allocator.free(data_raw);
            const stdout = std.Io.File.stdout();
            var buf: [8192]u8 = undefined;
            var writer = stdout.writer(app.io, &buf);
            writer.interface.print("{s}\n", .{data_raw}) catch {};
            writer.interface.flush() catch {};
            app.exit_code = 0;
            _ = app.ui.main.Close();
        },
        // In apps mode, we execute the desktop entry's Exec command and exit immediately, so the launched app isn't a child of Badi and won't be killed when Badi exits.
        .apps => {
            const row = app.ui.list.CurrentRow();
            if (row < 0) return;
            const item = app.ui.list.Item(row);
            const variant = item.Data(context.UserRole);
            defer variant.Delete();
            const data_raw = variant.ToString(app.allocator);
            defer app.allocator.free(data_raw);
            var command = exec.parseExec(app.allocator, data_raw) catch |err| {
                std.log.warn("failed parsing desktop Exec command '{s}': {}", .{ data_raw, err });
                return;
            };
            defer command.deinit();
            _ = qt6.QProcess.StartDetached22(app.allocator, command.program(), command.args());
            _ = app.ui.main.Close();
        },
        .prefix => |cfg| {
            // Read the query directly from the input box
            const text_ptr = app.ui.input.Text(app.allocator);
            defer app.allocator.free(text_ptr);
            const query = text_ptr;
            if (query.len == 0) return;

            const quoted_query = exec.quoteShellArg(app.allocator, query) catch return;
            defer app.allocator.free(quoted_query);

            // Replace %s with one shell-quoted argument.
            const final_cmd = if (std.mem.indexOf(u8, cfg.action, "%s")) |idx| blk: {
                const prefix_part = cfg.action[0..idx];
                const suffix_part = cfg.action[idx + 2 ..];
                break :blk std.fmt.allocPrint(app.allocator, "{s}{s}{s}", .{ prefix_part, quoted_query, suffix_part }) catch return;
            } else blk: {
                break :blk std.fmt.allocPrint(app.allocator, "{s} {s}", .{ cfg.action, quoted_query }) catch return;
            };
            defer app.allocator.free(final_cmd);

            // Run via sh -c
            _ = qt6.QProcess.StartDetached22(app.allocator, "sh", &[_][]const u8{ "-c", final_cmd });
            _ = app.ui.main.Close();
        },
    }
}
