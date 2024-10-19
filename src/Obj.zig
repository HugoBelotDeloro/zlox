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
    owned: bool,

    pub fn getObj(self: *ObjString) *Obj {
        return &self.obj;
    }

    pub fn getString(self: *const ObjString) []const u8 {
        return self.getStringPtr()[0..self.len];
    }

    fn getStringPtr(self: *const ObjString) [*]const u8 {
        const as_u8: [*]const u8 = @ptrCast(self);
        const data = as_u8 + @sizeOf(ObjString);
        if (self.owned) {
            return data;
        }
        return @as(*const [*]const u8, @ptrCast(@alignCast(data))).*;
    }

    fn getStringMut(self: *ObjString) []u8 {
        return self.getStringPtrMut()[0..self.len];
    }

    /// Strings should be immutable, only for building
    fn getStringPtrMut(self: *ObjString) [*]u8 {
        if (!self.owned) {
            std.process.exit(1);
        }
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
    const obj_str = try allocateStringRef(str, alloc);
    const as_u8: [*]u8 = @ptrCast(obj_str);
    const data = as_u8 + @sizeOf(ObjString);
    @as(*[*]const u8, @ptrCast(@alignCast(data))).* = str.ptr;
    return obj_str;
}

pub fn fromCopy(str: []u8, alloc: std.mem.Allocator) !*Obj {
    const str_obj = try allocateStringOwned(str.len, alloc);
    @memcpy(str_obj.getStringPtrMut(), str);

    return str_obj.getObj();
}

pub fn withFn(init: fn (buf: []u8, data: *const anyopaque) void, data: *const anyopaque, len: usize, alloc: std.mem.Allocator) !*ObjString {
    const str_obj = try allocateStringOwned(len, alloc);
    init(str_obj.getStringMut(), data);

    return str_obj;
}

fn allocateStringOwned(buf_size: usize, alloc: std.mem.Allocator) !*ObjString {
    const bytes = try alloc.alloc(u8, @sizeOf(ObjString) + buf_size);
    const str_obj: *ObjString = @alignCast(@ptrCast(bytes));
    str_obj.* = ObjString{
        .obj = Obj{
            .typ = .String,
        },
        .len = buf_size,
        .owned = true,
    };

    return str_obj;
}

fn allocateStringRef(slice: []const u8, alloc: std.mem.Allocator) !*ObjString {
    const bytes = try alloc.alloc(u8, @sizeOf(ObjString) + @sizeOf([*]const u8));
    const str_obj: *ObjString = @alignCast(@ptrCast(bytes));
    str_obj.* = ObjString{
        .obj = Obj{
            .typ = .String,
        },
        .len = slice.len,
        .owned = false,
    };

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
