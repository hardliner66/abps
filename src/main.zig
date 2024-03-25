const std = @import("std");
const a = @import("actor.zig");

fn counting(self: *a.Actor, sys: *a.System, state: *a.Any, from: a.ActorRef, msg: a.Any) anyerror!void {
    _ = state;
    if (msg.tryGet(i32)) |v| {
        if (v <= 10_000_000) {
            try sys.send(self.ref, from, i32, v + 1);
        }
    }
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    var system = a.System.new(gpa);
    defer system.destroy();

    const ref = try system.spawn(i32, 5, &counting);
    try system.send(ref, ref, i32, 5);

    try system.work();

    // const a = try actor.any(i32, gpa, 32);
    //
    // if (a.tryGet(i32)) |value| {
    //     std.debug.print("{any}\n", .{value});
    // }

    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // don't forget to flush!
}
