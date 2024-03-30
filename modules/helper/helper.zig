const std = @import("std");

pub fn print(comptime format: []const u8, args: anytype) void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    stdout.print(format, args) catch {};

    bw.flush() catch {};
}

pub fn println(comptime format: []const u8, args: anytype) void {
    print(format ++ "\n", args);
}

pub fn eprint(comptime format: []const u8, args: anytype) void {
    const stdout_file = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    stdout.print(format, args) catch {};

    bw.flush() catch {};
}

pub fn eprintln(comptime format: []const u8, args: anytype) void {
    eprint(format ++ "\n", args);
}
