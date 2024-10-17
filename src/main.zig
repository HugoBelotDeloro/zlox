const std = @import("std");
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const debug = @import("debug.zig");
const Vm = @import("Vm.zig");
const Parser = @import("Parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const argv = std.os.argv;
    if (argv.len == 1) {
        try repl(gpa.allocator());
    } else if (argv.len == 2) switch (try runFile(std.mem.span(argv[1]), gpa.allocator())) {
        .CompileError => std.process.exit(65),
        .RuntimeError => std.process.exit(70),
        else => {},
    } else {
        _ = try std.io.getStdErr().write("Usage: zlox [path]\n");
        std.process.exit(64);
    }
}

fn repl(allocator: std.mem.Allocator) !void {
    var line_buf: [1024]u8 = undefined;
    const stdout = std.io.getStdOut().writer().any();
    const stdin = std.io.getStdIn().reader();

    while (true) {
        _ = try stdout.write("> ");
        const line: []u8 = try stdin.readUntilDelimiterOrEof(&line_buf, '\n') orelse "";

        if (line.len == 0) {
            break;
        }

        _ = try executeSource(line, allocator);
    }
}

const MaxFileSize: usize = 1 << 32;

fn runFile(path: []const u8, allocator: std.mem.Allocator) !Vm.InterpretResult {
    if (std.fs.cwd().openFile(path, .{})) |file| {
        defer file.close();
        const source = try file.readToEndAlloc(allocator, MaxFileSize);
        defer allocator.free(source);

        return executeSource(source, allocator);
    } else |open_err| {
        try std.io.getStdErr().writer().print("Error opening file {s}: {}", .{ path, open_err });
        std.process.exit(74);
    }
}

fn executeSource(source: []u8, allocator: std.mem.Allocator) !Vm.InterpretResult {
    const writer = std.io.getStdOut().writer().any();
    var chunk = Chunk.init(allocator);
    try Parser.compile(source, &chunk, allocator);
    defer chunk.free();
    return Vm.interpret(&chunk, allocator, writer);
}

fn simpleProgram(allocator: std.mem.Allocator) !void {
    var chunk = Chunk.init(allocator);
    defer chunk.free();

    try chunk.writeConstant(1.2, 0);
    try chunk.writeConstant(3.4, 1);
    try chunk.writeInstruction(.Add, 2);
    try chunk.writeConstant(5.6, 3);
    try chunk.writeInstruction(.Divide, 4);
    try chunk.writeInstruction(.Return, 5);

    var stdout = std.io.getStdOut().writer();

    try debug.disassembleChunk(&chunk, "test chunk", stdout.any());

    _ = try stdout.write("\n\n== interpret ==\n");
    _ = try Vm.interpret(&chunk, allocator, stdout.any());
}
