const std = @import("std");

pub const Value = f64;

pub const ValueArray = std.ArrayList(Value);

pub fn format(value: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    try writer.print("{d}", value);
}
