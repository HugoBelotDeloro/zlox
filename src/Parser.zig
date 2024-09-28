const std = @import("std");
const Scanner = @import("Scanner.zig");

const Parser = @This();

pub fn compile(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var scanner = Scanner.init(source);
    const stdout = std.io.getStdOut().writer().any();

    var line: u32 = 0;
    while (try scanner.next()) |token| {
        if (token.line != line) {
            try stdout.print("{d: >4}", .{token.line});
            line = token.line;
        } else {
            _ = try stdout.write("   | ");
        }

        try stdout.print("{s: <16} {s}\n", .{ @tagName(token.typ), token.start[0..token.length] });
    }

    return allocator.alloc(u8, 1);
}
