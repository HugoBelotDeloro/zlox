const std = @import("std");
const Obj = @This();

pub const Ptr = *align(16) Obj;

const ObjType = enum(u8) {
    String,
};

typ: ObjType,

pub fn ObjTypeOf(comptime typ: ObjType) type {
    return switch (typ) {
        .String => ObjString,
    };
}

const ObjString = packed struct {
    obj: ObjType = .String,
    str: [*]const u8,
    len: usize,
};

pub fn asObj(o: anytype) Obj.Ptr {
    return @ptrCast(o);
}

pub fn copyString(buf: []const u8, alloc: std.mem.Allocator) !*ObjString {
    const chars = try alloc.alloc(u8, buf.len);
    @memcpy(chars, buf);
    return try allocateString(chars, alloc);
}

fn allocateString(chars: []const u8, alloc: std.mem.Allocator) !*ObjString {
    const str = try allocateObject(.String, alloc);
    str.str = chars.ptr;
    str.len = chars.len;

    return str;
}

fn allocateObject(comptime typ: ObjType, alloc: std.mem.Allocator) !*ObjTypeOf(typ) {
    const obj = try alloc.create(ObjTypeOf(typ));
    obj.obj = typ;
    return obj;
}

pub fn asString(self: Obj.Ptr) ?[]const u8 {
    return switch (self.typ) {
        .String => @as(ObjString, @fieldParentPtr("obj", self)).str,
        else => null,
    };
}

pub fn format(
    obj: Obj.Ptr,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    return switch (obj.typ) {
        .String => {
            const str: *ObjString = @ptrCast(obj);
            _ = try writer.print("\"{s}\"", .{str.str[0..str.len]});
        },
    };
}
