const std = @import("std");
const Obj = @This();

const ObjType = enum {
    String,
};

typ: ObjType,

pub fn ObjTypeOf(comptime typ: ObjType) type {
    return switch (typ) {
        .String => ObjString,
    };
}

const ObjString = struct {
    obj: Obj = Obj{ .typ = .String },
    str: []const u8,

    pub fn format(
        str: ObjString,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("\"{s}\"", .{str.str});
    }
};

pub fn asObj(o: anytype) *Obj {
    return &o.obj;
}

pub fn copyString(buf: []const u8, alloc: std.mem.Allocator) !*ObjString {
    const chars = try alloc.alloc(u8, buf.len);
    @memcpy(chars, buf);
    return try allocateString(chars, alloc);
}

fn allocateString(chars: []const u8, alloc: std.mem.Allocator) !*ObjString {
    const str = try allocateObject(.String, alloc);
    str.str = chars;

    return str;
}

fn allocateObject(comptime typ: ObjType, alloc: std.mem.Allocator) !*ObjTypeOf(typ) {
    const obj = try alloc.create(ObjTypeOf(typ));
    obj.obj = Obj{ .typ = typ };
    return obj;
}

pub fn format(
    obj: *Obj,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    inline for (comptime std.enums.values(ObjType)) |obj_typ| {
        const typ = ObjTypeOf(obj_typ);
        const o = @as(*typ, @alignCast(@fieldParentPtr("obj", obj)));
        try writer.print("{}", .{o});
    }
}

pub fn eql(a: Obj, b: *Obj) bool {
    _ = a;
    _ = b;
    return false;
}
