const std = @import("std");
const a = @import("actor.zig");

fn print(comptime format: []const u8, args: anytype) void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    stdout.print(format, args) catch {};

    bw.flush() catch {};
}

fn counting(self: *a.Actor, sys: *a.System, state: *i32, from: a.ActorRef, msg: *a.Any) anyerror!void {
    _ = state;
    if (msg.matches(i32)) |v| {
        if (v <= 10_000_000) {
            try sys.send(self.ref, from, i32, v + 1);
        } else {
            print("Done: {}", .{v});
            sys.stop();
        }
    }
}

pub fn main() !void {
    // const allocator = std.heap.c_allocator;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var system = try a.System.init(allocator);
    defer system.deinit() catch {};

    const ref = try system.spawn(i32, 5, &counting);
    try system.send(ref, ref, bool, true);
    try system.send(ref, ref, i32, 5);

    system.wait();
}
