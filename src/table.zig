const std = @import("std");
const Obj = @import("Obj.zig");

pub fn Table(V: type) type {
    return struct {
        const Self = @This();

        const MaxLoad: f32 = 0.75;

        const Entry = struct {
            key: ?*Obj.String,
            value: V,
        };

        const Tombstone: V = @bitCast([_]u8{42} ** @sizeOf(V));

        const Empty: V = @bitCast([_]u8{13} ** @sizeOf(V));

        count: usize,
        entries: []Entry,
        alloc: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self {
                .count = 0,
                .entries = &.{},
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.entries);
        }

        pub fn set(self: *Self, key: *Obj.String, value: V) !bool {
            if (self.count + 1 > maxLoad(self.entries.len)) {
                const new_size: usize = if (self.entries.len == 0) 8 else self.entries.len * 2;
                try self.adjustCapacity(new_size);
            }
            const entry = self.findEntry(key);
            const isNewKey = entry.key == null;
            if (isNewKey and entry.value != Tombstone) self.count += 1;

            entry.key = key;
            entry.value = value;
            return isNewKey;
        }

        pub fn delete(self: *Self, key: *Obj.String) bool {
            if (self.count == 0) return false;

            const entry = self.findEntry(key);
            if (entry.key == null) return false;

            entry.key = null;
            const was_alive = entry.value != Tombstone;
            entry.value = Tombstone;
            return was_alive;
        }

        /// Assumes the entries slice is non-empty
        fn findEntry(self: *const Self, key: *Obj.String) *Entry {
            var index = key._hash % self.entries.len;
            var tombstone: ?*Entry= null;

            while (true) : (index = (index + 1) % self.entries.len) {
                const entry = &self.entries[index];
                if (entry.key == null) {
                    if (entry.value == Tombstone) {
                        if (tombstone == null) tombstone = entry;
                    } else {
                        return if (tombstone) |t| t else entry;
                    }
                }
                if (entry.key == key) return entry;
            }
            unreachable;
        }

        pub fn get(self: *Self, key: *Obj.String) ?V {
            if (self.count == 0) return null;
            const entry = self.findEntry(key);
            if (entry.key == null) return null;
            return entry.value;
        }

        fn adjustCapacity(self: *Self, capacity: usize) !void {
            const new_buf = try self.alloc.alloc(Entry, capacity);
            @memset(new_buf, Entry{ .key = null, .value = Empty });

            const old_entries = self.entries;
            self.entries = new_buf;
            self.count = 0;
            for (old_entries) |entry| {
                if (entry.key) |key| {
                    const dest = self.findEntry(key);
                    dest.key = key;
                    dest.value = entry.value;
                    self.count += 1;
                }
            }

            self.alloc.free(old_entries);
        }

        fn maxLoad(size: usize) usize {
            return @as(usize, @intFromFloat(@as(f32, @floatFromInt(size)) * MaxLoad));
        }
    };
}

test "basic" {
    const t = std.testing;
    const alloc = t.allocator;

    var table = Table(u8).init(alloc);
    defer table.deinit();

    const str_1 = try Obj.fromConstant("test", alloc);
    defer str_1.deinit(alloc);
    const str_2 = try Obj.fromConstant("test2", alloc);
    defer str_2.deinit(alloc);

    try t.expect(try table.set(str_1, 1));
    try t.expect(!try table.set(str_1, 2));
    try t.expectEqual(2, table.get(str_1));
    try t.expectEqual(null, table.get(str_2));
    try t.expect(table.delete(str_1));
    try t.expect(!table.delete(str_1));
}

test "many" {
    const t = std.testing;
    const alloc = t.allocator;
    const s = "abcdefghijklmnopqrstuvwxyz";

    var table = Table(usize).init(alloc);
    defer table.deinit();

    var objs: [s.len]*Obj.String = undefined;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        objs[i] = try Obj.fromConstant(s[i..i+1], alloc);
    }

    i = 0;
    while (i < s.len) : (i += 1) {
        const b = try table.set(objs[i], 0);
        try t.expect(b);
    }

    i = 0;
    while (i < s.len) : (i += 1) {
        const b = try table.set(objs[i], i + 1);
        try t.expect(!b);
    }

    i = 0;
    while (i < s.len) : (i += 1) {
        const v = table.get(objs[i]);
        try t.expectEqual(i + 1, v);
    }

    i = 0;
    while (i < s.len) : (i += 1) {
        const b = table.delete(objs[i]);
        try t.expect(b);
    }

    for (objs) |obj| {
        obj.deinit(alloc);
    }
}