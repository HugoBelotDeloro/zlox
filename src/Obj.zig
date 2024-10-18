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

    pub fn eql(a: *ObjString, b: *ObjString) bool {
        return std.mem.eql(u8, a.str, b.str);
    }
};

pub fn asObj(o: anytype) *Obj {
    return &o.obj;
}

pub fn asString(self: *Obj) ?*ObjString {
    if (self.typ == .String) return @as(*ObjString, @alignCast(@fieldParentPtr("obj", self)));
    return null;
}

pub fn copyString(buf: []const u8, alloc: std.mem.Allocator) !*ObjString {
    const chars = try alloc.alloc(u8, buf.len);
    @memcpy(chars, buf);
    return try allocateString(chars, alloc);
}

pub fn string(str: []u8, alloc: std.mem.Allocator) !*Obj {
    const str_obj = try allocateString(str, alloc);

    return &str_obj.obj;
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
