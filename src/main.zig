const std = @import("std");
const eql = std.mem.eql;
const a = @import("actor.zig");

fn print(comptime format: []const u8, args: anytype) void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    stdout.print(format, args) catch {};

    bw.flush() catch {};
}

fn die(self: *a.Actor, sys: *a.System, from: a.ActorRef, msg: *a.Any) anyerror!void {
    _ = self;
    _ = from;
    // make sure we dont get a "message was not handled!" message
    _ = msg.matches(void);
    sys.stop();
}

fn counting(self: *a.Actor, sys: *a.System, state: *i32, from: a.ActorRef, msg: *a.Any) anyerror!void {
    if (msg.matches(i32)) |v| {
        state.* += v;
        if (state.* < 10_000_000 / 2) {
            try sys.send(self.ref, from, i32, 1);
        } else {
            print("Done: {}\n", .{state.*});
            try self.becomeStateless(&die);
            try sys.send(self.ref, self.ref, void, {});
        }
    }
}

pub fn main() !void {
    var allocator = std.heap.c_allocator;
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();

    var argsIterator = try std.process.ArgIterator.initWithAllocator(allocator);
    defer argsIterator.deinit();

    // Skip executable
    _ = argsIterator.next();

    // Handle cases accordingly
    while (argsIterator.next()) |arg| {
        if (eql(u8, arg, "--debug")) {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            allocator = gpa.allocator();
            print("DEBUG MODE\n", .{});
        }
    }

    var system = try a.System.init(allocator);
    defer system.deinit() catch {};

    const ref_a = try system.spawnWithName("Counting Actor", i32, 0, &counting);
    const ref_b = try system.spawnWithName("Counting Actor", i32, 0, &counting);
    try system.send(ref_a, ref_a, []const u8, "test");
    try system.send(ref_b, ref_a, i32, 1);

    system.wait();
}
