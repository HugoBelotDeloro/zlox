const std = @import("std");
const Obj = @This();

const ObjType = enum {
    String,
};

typ: ObjType,

pub fn ObjTypeOf(comptime typ: ObjType) type {
    return switch (typ) {
        .String => String,
    };
}

pub const String = struct {
    obj: Obj = Obj{ .typ = .String },
    len: usize,
    owned: bool,
    _hash: u32,

    pub fn deinit(self: *String, alloc: std.mem.Allocator) void {
        if (self.owned) {
            alloc.free(@as([*]u8, @ptrCast(self))[0..(@sizeOf(String) + self.len)]);
        } else {
            alloc.free(@as([*]u8, @ptrCast(self))[0..(@sizeOf(String) + @sizeOf([*]const u8))]);
        }
    }

    pub fn getObj(self: *String) *Obj {
        return &self.obj;
    }

    pub fn getString(self: *const String) []const u8 {
        return self.getStringPtr()[0..self.len];
    }

    fn getStringPtr(self: *const String) [*]const u8 {
        const as_u8: [*]const u8 = @ptrCast(self);
        const data = as_u8 + @sizeOf(String);
        if (self.owned) {
            return data;
        }
        return @as(*const [*]const u8, @ptrCast(@alignCast(data))).*;
    }

    fn getStringMut(self: *String) []u8 {
        return self.getStringPtrMut()[0..self.len];
    }

    /// Strings should be immutable, only for building
    fn getStringPtrMut(self: *String) [*]u8 {
        if (!self.owned) {
            std.process.exit(1);
        }
        const as_u8: [*]u8 = @ptrCast(self);
        return as_u8 + @sizeOf(String);
    }

    fn hash(str: []const u8) u32 {
        var hashed: u32 = 2166136261;
        for (str) |c| {
            hashed ^= c;
            hashed *%= 16777619;
        }

        return hashed;
    }

    pub fn fromConstant(str: []const u8, alloc: std.mem.Allocator) !*String {
        const obj_str = try allocateStringRef(str, alloc);
        const as_u8: [*]u8 = @ptrCast(obj_str);
        const data = as_u8 + @sizeOf(String);
        @as(*[*]const u8, @ptrCast(@alignCast(data))).* = str.ptr;
        return obj_str;
    }

    pub fn fromCopy(str: []u8, alloc: std.mem.Allocator) !*Obj {
        const obj_str = try allocateStringOwned(str.len, alloc);
        @memcpy(obj_str.getStringPtrMut(), str);
        obj_str._hash = String.hash(obj_str.getString());

        return obj_str.getObj();
    }

    pub fn withFn(init: fn (buf: []u8, data: *const anyopaque) void, data: *const anyopaque, len: usize, alloc: std.mem.Allocator) !*String {
        const obj_str = try allocateStringOwned(len, alloc);
        init(obj_str.getStringMut(), data);
        obj_str._hash = String.hash(obj_str.getString());

        return obj_str;
    }

    /// Will not set hash nor init array
    fn allocateStringOwned(buf_size: usize, alloc: std.mem.Allocator) !*String {
        const bytes = try alloc.alloc(u8, @sizeOf(String) + buf_size);
        const obj_str: *String = @alignCast(@ptrCast(bytes));
        obj_str.* = String{
            .len = buf_size,
            .owned = true,
            ._hash = undefined,
        };

        return obj_str;
    }

    fn allocateStringRef(slice: []const u8, alloc: std.mem.Allocator) !*String {
        const bytes = try alloc.alloc(u8, @sizeOf(String) + @sizeOf([*]const u8));
        const obj_str: *String = @alignCast(@ptrCast(bytes));
        obj_str.* = String{
            .len = slice.len,
            .owned = false,
            ._hash = String.hash(slice),
        };

        return obj_str;
    }

    pub fn format(
        str: *String,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("\"{s}\"", .{str.getString()});
    }

    pub fn eql(a: *String, b: *String) bool {
        return a == b; // Thanks to interning
    }
};

pub fn asString(self: *Obj) ?*String {
    if (self.typ == .String) return @as(*String, @alignCast(@fieldParentPtr("obj", self)));
    return null;
}

fn allocateObject(comptime typ: ObjType, alloc: std.mem.Allocator) !*ObjTypeOf(typ) {
    const obj: *String = try alloc.create(ObjTypeOf(typ));
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
            const oa = @as(*String, @alignCast(@fieldParentPtr("obj", a)));
            const ob = @as(*String, @alignCast(@fieldParentPtr("obj", b)));
            return oa.eql(ob);
        },
    }
}
