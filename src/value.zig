const std = @import("std");

pub const Value = union(enum) {
    Bool: bool,
    Nil,
    Number: f64,

    pub fn boolean(b: bool) Value {
        return .{ .Bool = b, };
    }

    pub fn nil() Value {
        return .{ .nil, };
    }

    pub fn number(n: f64) Value {
        return .{ .Number = n, };
    }

    pub fn format(value: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try switch (value) {
            .Bool => |b| writer.print("{any}", .{b}),
            .Nil => writer.print("nil", .{}),
            .Number => |n| writer.print("{d}", .{n}),
        };
    }
};
