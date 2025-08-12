const std = @import("std");
const p = std.debug.print;

pub fn print(comptime format: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &stdout_writer.interface;
    stdout.print(format, args) catch {};
    stdout.flush() catch {};
}

pub fn println(comptime format: []const u8, args: anytype) void {
    print(format ++ "\n", args);
}

pub fn eprint(comptime format: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &stderr_writer.interface;
    stderr.print(format, args) catch {};
    stderr.flush() catch {};
}

pub fn eprintln(comptime format: []const u8, args: anytype) void {
    eprint(format ++ "\n", args);
}
