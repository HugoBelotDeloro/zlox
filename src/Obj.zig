const std = @import("std");
const Obj = @This();

const ObjType = enum {
    String,
    Function,
};

typ: ObjType,

pub const String = @import("String.zig");
pub const Function = @import("Function.zig");

pub fn ObjTypeOf(comptime typ: ObjType) type {
    return switch (typ) {
        .String => String,
        .Function => Function,
    };
}

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
        inline .Function => {
            const fa = @as(*Function, @alignCast(@fieldParentPtr("obj", a)));
            const fb = @as(*Function, @alignCast(@fieldParentPtr("obj", b)));
            return fa.eql(fb);
        },
    }
}
