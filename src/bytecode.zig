const std = @import("std");
const values = @import("value.zig");

pub const OpCode = enum(u8) {
    OP_CONSTANT,
    OP_RETURN,
    _,
};

const LineInfo = struct {
  /// Number of the new line
  line_number: u32,
  /// Number of instructions at this line
  instruction_count: u32,
};

pub const Chunk = struct {
    code: std.ArrayList(OpCode),
    constants: values.ValueArray,
    lines: std.ArrayList(LineInfo),

    pub fn init(alloc: std.mem.Allocator) Chunk {
        return Chunk{
          .code = std.ArrayList(OpCode).init(alloc),
          .constants = std.ArrayList(values.Value).init(alloc),
          .lines = std.ArrayList(LineInfo).init(alloc),
        };
    }

    pub fn free(self: *Chunk) void {
        self.code.deinit();
        self.constants.deinit();
        self.lines.deinit();
    }

    pub fn write_chunk(self: *Chunk, byte: OpCode, line: u32) !void {
        try self.code.append(byte);
        if (self.lines.items.len == 0 or self.lines.items[self.lines.items.len - 1].line_number != line) {
          try self.lines.append(.{.instruction_count = 1, .line_number = line});
        } else {
          self.lines.items[self.lines.items.len - 1].instruction_count += 1;
        }
    }

    pub fn add_constant(self: *Chunk, value: values.Value) !usize {
        try self.constants.append(value);
        return self.constants.items.len - 1;
    }

    pub fn get_line(self: *Chunk, index: usize) u32 {
      var i: usize = 0; // Instruction index

      for (self.lines.items) |line_info| {
        if (i <= index and i + line_info.instruction_count > index) {
          return line_info.line_number;
        }
        i += line_info.instruction_count;
      }

      std.io.getStdOut().writer().print("index out of bounds {d}", .{index}) catch {};
      std.process.exit(1);
    }
};

test "constants" {
  var chunk = Chunk.init(std.testing.allocator);
  defer chunk.free();
  const one = try chunk.add_constant(1);
  const two = try chunk.add_constant(2);
  const three = try chunk.add_constant(3);

  try std.testing.expect(chunk.constants.items[one] == 1);
  try std.testing.expect(chunk.constants.items[two] == 2);
  try std.testing.expect(chunk.constants.items[three] == 3);
}
