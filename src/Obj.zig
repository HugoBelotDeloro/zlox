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
    len: usize,

    pub fn getObj(self: *ObjString) *Obj {
        return &self.obj;
    }

    pub fn getString(self: *const ObjString) []const u8 {
        return self.getStringPtr()[0..self.len];
    }

    fn getStringPtr(self: *const ObjString) [*]const u8 {
        const as_u8: [*]const u8 = @ptrCast(self);
        return as_u8 + @sizeOf(ObjString);
    }

    fn getStringMut(self: *ObjString) []u8 {
        return self.getStringPtrMut()[0..self.len];
    }

    /// Strings should be immutable, only for building
    fn getStringPtrMut(self: *ObjString) [*]u8 {
        const as_u8: [*]u8 = @ptrCast(self);
        return as_u8 + @sizeOf(ObjString);
    }

    pub fn format(
        str: *ObjString,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("\"{s}\"", .{str.getString()});
    }

    pub fn eql(a: *ObjString, b: *ObjString) bool {
        return std.mem.eql(u8, a.getString(), b.getString());
    }
};

pub fn asString(self: *Obj) ?*ObjString {
    if (self.typ == .String) return @as(*ObjString, @alignCast(@fieldParentPtr("obj", self)));
    return null;
}

pub fn fromConstant(str: []const u8, alloc: std.mem.Allocator) !*ObjString {
    const obj_str = try allocateString(str.len, alloc);
    @memcpy(obj_str.getStringPtrMut(), str);
    return obj_str;
}

pub fn fromCopy(str: []u8, alloc: std.mem.Allocator) !*Obj {
    const str_obj = try allocateString(str.len, alloc);

    return str_obj.getObj();
}

pub fn withFn(init: fn (buf: []u8, data: *const anyopaque) void, data: *const anyopaque, len: usize, alloc: std.mem.Allocator) !*ObjString {
    const str_obj = try allocateString(len, alloc);
    init(str_obj.getStringMut(), data);

    return str_obj;
}

fn allocateString(buf_size: usize, alloc: std.mem.Allocator) !*ObjString {
    const bytes = try alloc.alloc(u8, @sizeOf(ObjString) + buf_size);
    const str_obj: *ObjString = @alignCast(@ptrCast(bytes));
    str_obj.* = ObjString{ .obj = Obj{
        .typ = .String,
    }, .len = buf_size };

    return str_obj;
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

pub fn eql(a: *Obj, b: *Obj) bool {
    if (a.typ != b.typ) return false;

    switch (a.typ) {
        inline .String => {
            const oa = @as(*ObjString, @alignCast(@fieldParentPtr("obj", a)));
            const ob = @as(*ObjString, @alignCast(@fieldParentPtr("obj", b)));
            return oa.eql(ob);
        },
    }
}
