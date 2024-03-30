const std = @import("std");
const eql = std.mem.eql;
const a = @import("actor.zig");
const helper = @import("helper");
const print = helper.print;
const eprint = helper.eprint;

fn die(self: *a.Actor, sys: *a.System, from: a.ActorRef, msg: *a.Any) anyerror!void {
    _ = self;
    _ = from;
    // make sure we dont get a "message was not handled!" message
    _ = msg.matches(void);
    sys.stop();
}

fn counting(self: *a.Actor, sys: *a.System, state: *a.ActorRef, _: a.ActorRef, msg: *a.Any) anyerror!void {
    if (msg.matches(a.ActorRef)) |r| {
        state.* = r;
    }
    if (msg.matches(i32)) |v| {
        if (v < 5_000_000) {
            try sys.send(self.ref, state.*, i32, v + 1);
        } else {
            print("Done: {}\n", .{v});
            try self.becomeStateless(&die);
            try sys.send(self.ref, self.ref, void, {});
        }
    }
}

fn initial(self: *a.Actor, _: *a.System, _: a.ActorRef, msg: *a.Any) anyerror!void {
    if (msg.matches(a.ActorRef)) |r| {
        try self.become(a.ActorRef, r, &counting);
    }
}

pub fn main() !void {
    var allocator = std.heap.c_allocator;

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

    var system = try a.System.init(allocator, null);
    defer system.deinit() catch {};

    const ref_1 = try system.spawnWithNameStateless("Counting Actor 1", &initial);
    const ref_2 = try system.spawnWithName("Counting Actor 2", a.ActorRef, ref_1, &counting);
    const ref_3 = try system.spawnWithName("Counting Actor 3", a.ActorRef, ref_2, &counting);
    const ref_4 = try system.spawnWithName("Counting Actor 4", a.ActorRef, ref_3, &counting);
    const ref_5 = try system.spawnWithName("Counting Actor 5", a.ActorRef, ref_4, &counting);
    const ref_6 = try system.spawnWithName("Counting Actor 6", a.ActorRef, ref_5, &counting);
    const ref_7 = try system.spawnWithName("Counting Actor 7", a.ActorRef, ref_6, &counting);
    const ref_8 = try system.spawnWithName("Counting Actor 8", a.ActorRef, ref_7, &counting);
    const ref_9 = try system.spawnWithName("Counting Actor 9", a.ActorRef, ref_8, &counting);
    const ref_10 = try system.spawnWithName("Counting Actor 10", a.ActorRef, ref_9, &counting);
    const ref_11 = try system.spawnWithName("Counting Actor 11", a.ActorRef, ref_10, &counting);
    const ref_12 = try system.spawnWithName("Counting Actor 12", a.ActorRef, ref_11, &counting);
    const ref_13 = try system.spawnWithName("Counting Actor 13", a.ActorRef, ref_12, &counting);
    const ref_14 = try system.spawnWithName("Counting Actor 14", a.ActorRef, ref_13, &counting);
    const ref_15 = try system.spawnWithName("Counting Actor 15", a.ActorRef, ref_14, &counting);
    const ref_16 = try system.spawnWithName("Counting Actor 16", a.ActorRef, ref_15, &counting);
    try system.send(ref_1, ref_1, []const u8, "test");
    try system.send(ref_1, ref_1, a.ActorRef, ref_16);
    try system.send(ref_1, ref_1, i32, 1);

    system.wait();
}
