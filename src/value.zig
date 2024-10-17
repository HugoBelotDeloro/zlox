const std = @import("std");
const Obj = @import("Obj.zig");

pub const Value = union(enum) {
    Bool: bool,
    Nil,
    Number: f64,
    Obj: *Obj,

    pub fn boolean(b: bool) Value {
        return .{
            .Bool = b,
        };
    }

    pub fn nil() Value {
        return Value.Nil;
    }

    pub fn number(n: f64) Value {
        return .{
            .Number = n,
        };
    }

    pub fn obj(o: *Obj) Value {
        return .{
            .Obj = o,
        };
    }

    pub fn any(val: anytype) Value {
        return switch (@TypeOf(val)) {
            inline f64 => Value.number(val),
            inline bool => Value.boolean(val),
            inline void => Value.nil(),
            inline *Obj => Value.obj(val),
            else => @compileError("Invalid type for value"),
        };
    }

    pub fn eql(a: Value, b: Value) bool {
        return switch (a) {
            .Nil => switch (b) {
                .Nil => true,
                else => false,
            },
            .Number => |na| switch (b) {
                .Number => |nb| na == nb,
                else => false,
            },
            .Bool => |ba| switch (b) {
                .Bool => |bb| ba == bb,
                else => false,
            },
            .Obj => |oa| switch (b) {
                .Obj => |ob| oa.eql(ob),
                else => false,
            },
        };
    }

    pub fn format(value: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try switch (value) {
            .Bool => |b| writer.print("{any}", .{b}),
            .Nil => writer.print("nil", .{}),
            .Number => |n| writer.print("{d}", .{n}),
            .Obj => |o| writer.print("{any}", .{o}),
        };
    }
};
