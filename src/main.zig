const std = @import("std");
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const debug = @import("debug.zig");
const Vm = @import("Vm.zig");
const Parser = @import("Parser.zig");
const Table = @import("table.zig").Table;

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
    var strings = Table(u8).init(allocator);
    defer strings.deinit();

    if (try Parser.compile(source, &strings, allocator)) |function| {
        defer function.deinit();
        return Vm.interpret(function, &strings, allocator, writer);
    }
    return .CompileError;
}
