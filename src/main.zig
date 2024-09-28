const std = @import("std");
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const debug = @import("debug.zig");
const VM = @import("Vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const argv = std.os.argv;
    if (argv.len == 1) {
        try repl(gpa.allocator());
    } else if (argv.len == 2) {
        try runFile(std.mem.span(argv[1]), gpa.allocator());
    } else {
      _ = try std.io.getStdErr().write("Usage: zlox [path]\n");
      std.process.exit(64);
    }
}

fn repl(_: std.mem.Allocator) !void {
  var line_buf: [1024]u8 = undefined;
  const stdout = std.io.getStdOut().writer().any();
  const stdin = std.io.getStdIn().reader();

  while (true) {
    _ = try stdout.write("> ");
    const line = try stdin.readUntilDelimiterOrEof(&line_buf, '\n') orelse "";

    if (line.len == 0) {
      break;
    }

    try stdout.print("line: {s}\n", .{line});
  }
}

const MAX_FILE_SIZE: usize = 1 << 32;

fn runFile(path: []u8, allocator: std.mem.Allocator) !void {
    if (std.fs.cwd().openFile(path, .{})) |file| {
        defer file.close();
        const source = try file.readToEndAlloc(allocator, MAX_FILE_SIZE);
        defer allocator.free(source);
    } else |open_err| {
        try std.io.getStdErr().writer().print("Error opening file {s}: {}", .{path, open_err});
        std.process.exit(74);
    }
}

fn simpleProgram(allocator: std.mem.Allocator) !void {
    var chunk = Chunk.init(allocator);
    defer chunk.free();

    try chunk.writeConstant(1.2, 0);
    try chunk.writeConstant(3.4, 1);
    try chunk.writeInstruction(.OP_ADD, 2);
    try chunk.writeConstant(5.6, 3);
    try chunk.writeInstruction(.OP_DIVIDE, 4);
    try chunk.writeInstruction(.OP_RETURN, 5);

    var stdout = std.io.getStdOut().writer();

    try debug.disassembleChunk(&chunk, "test chunk", stdout.any());

    _ = try stdout.write("\n\n== interpret ==\n");
    _ = try VM.interpret(&chunk, allocator, stdout.any());
}
