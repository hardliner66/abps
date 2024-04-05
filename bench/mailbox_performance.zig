const std = @import("std");
const fmt = std.fmt;
const eql = std.mem.eql;
const a = @import("actor");
const helper = @import("helper");
const clap = @import("clap");
const println = helper.println;
const eprintln = helper.eprintln;
const config = @import("config");
const ztracy = @import("ztracy");

const ReceiverState = struct {
    max_messages: usize,
    count: usize,
};

fn receiver_fn(self: *a.Actor, sys: *a.System, state: *ReceiverState, _: a.ActorRef, msg: *a.Any) anyerror!void {
    _ = self;
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    if (msg.matches(void)) |_| {
        state.count += 1;
        if (state.count == state.max_messages) {
            sys.stop();
        }
    }
}

fn sender_fn(self: *a.Actor, sys: *a.System, state: *usize, from: a.ActorRef, msg: *a.Any) anyerror!void {
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    if (msg.matches(void)) |_| {
        for (0..state.*) |_| {
            try sys.send(self.ref, from, void, void{});
        }
    }
}

pub fn main() !void {
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    const params = comptime clap.parseParamsComptime(
        \\-h                           Display usage and exit.
        \\    --help                   Display this help and exit.
        \\-d, --debug                  An option parameter, which takes a value.
        \\-s, --sender_count <usize>   How many senders to spawn.
        \\-m, --message_count <usize>  How many messages to send per sender. (Max Value: 999999999)
        \\-g, --use_gpa                Use general purpose allocator.
        \\-l, --locked                 Use locking instead of lock-free queue.
    );

    var allocator = std.heap.c_allocator;

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit
        diag.report(std.io.getStdErr().writer(), err) catch {};
        _ = try clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    if (res.args.h != 0) {
        return clap.usage(std.io.getStdErr().writer(), clap.Help, &params);
    }

    const use_gpa = res.args.use_gpa != 0;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    if (use_gpa) {
        allocator = gpa.allocator();
    }

    const locked = res.args.locked != 0;

    const sender_count = res.args.sender_count orelse (try std.Thread.getCpuCount() / 2) - 1;
    const message_count = res.args.message_count orelse 1000;
    const total = sender_count * message_count;

    if (message_count > 999_999_999) {
        eprintln("Message count must be 999999999 or lower!", .{});
        return;
    }

    println("============================", .{});
    println("====== Runtime Config ======", .{});
    println("============================", .{});
    println("| Cpu Count    : {: <9} |", .{sender_count});
    println("| Message Count: {: <9} |", .{message_count});
    println("| Use Gpa      : {: <9} |", .{use_gpa});
    println("| Locked       : {: <9} |", .{locked});
    println("============================", .{});
    println("", .{});

    {
        var system = try a.System.init(allocator, .{ .cpu_count = sender_count + 1, .locked = locked });
        defer system.deinit() catch {};

        const receiver = try system.spawnWithName(
            null,
            "Receiver",
            ReceiverState,
            .{ .count = 0, .max_messages = total },
            &receiver_fn,
        );
        for (0..sender_count) |i| {
            var all_together: [100]u8 = undefined;
            // You can use slice syntax with at least one runtime-known index on an
            // array to convert an array into a slice.
            var start: usize = 0;
            _ = &start;
            const all_together_slice = all_together[start..];
            // String concatenation example.
            const sender_name = try fmt.bufPrint(all_together_slice, "Sendeer {}", .{i + 2});
            const sender = try system.spawnWithName(
                null,
                sender_name,
                usize,
                message_count,
                &sender_fn,
            );
            try system.send(receiver, sender, void, void{});
        }

        system.wait();
    }

    if (use_gpa) {
        if (gpa.detectLeaks()) {
            eprintln("Leak detected!", .{});
        }
    }
}