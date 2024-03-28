const std = @import("std");
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
        print("{}\n", .{v});
        state.* += v;
        if (state.* < 5) {
            try sys.send(self.ref, from, i32, 1);
        } else {
            print("Done: {}\n", .{state.*});
            try self.becomeStateless(&die);
            try sys.send(self.ref, from, void, {});
        }
    }
}

pub fn main() !void {
    // const allocator = std.heap.c_allocator;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var system = try a.System.init(allocator);
    defer system.deinit() catch {};

    const ref = try system.spawnWithName("Counting Actor", i32, 0, &counting);
    try system.send(ref, ref, []const u8, "test");
    try system.send(ref, ref, i32, 1);

    system.wait();
}
