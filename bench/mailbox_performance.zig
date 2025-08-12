const std = @import("std");
const fmt = std.fmt;
const eql = std.mem.eql;
const a = @import("actor");
const helper = @import("helper");
const clap = @import("clap");
const println = helper.println;
const eprintln = helper.eprintln;
const config = @import("config");

const Receiver = struct {
    max_messages: usize,
    count: usize,

    pub fn handle(state: *@This(), self: *a.Actor, sys: *a.System, _: ?a.ActorRef, msg: *a.Any) anyerror!void {
        _ = self;
        if (msg.matches(void)) |_| {
            state.count += 1;
            if (state.count == state.max_messages) {
                sys.stop();
            }
        }
    }
};

const Sender = struct {
    message_count: usize,
    pub fn handle(state: *@This(), self: *a.Actor, sys: *a.System, from: ?a.ActorRef, msg: *a.Any) anyerror!void {
        if (msg.matches(void)) |_| {
            for (0..state.message_count) |_| {
                try sys.send(self.ref, from.?, void, void{});
            }
        }
    }
};

pub fn main() !void {
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
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.helpToFile(.stderr(), clap.Help, &params, .{});
    }

    if (res.args.h != 0) {
        return clap.usageToFile(.stdout(), clap.Help, &params);
    }

    const use_gpa = res.args.use_gpa != 0;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    if (use_gpa) {
        allocator = gpa.allocator();
    }

    const locked = res.args.locked != 0;
    const debug = res.args.debug != 0;

    var default_cpu_count = (try std.Thread.getCpuCount() / 2);
    if (default_cpu_count <= 0) {
        default_cpu_count = 1;
    }

    const sender_count = res.args.sender_count orelse default_cpu_count;
    const message_count = res.args.message_count orelse 1000;
    const per_sender = message_count / sender_count;
    const rest = message_count - (per_sender * sender_count);

    if (message_count > 999_999_999) {
        eprintln("Message count must be 999999999 or lower!", .{});
        return;
    }

    println("============================", .{});
    println("====== Runtime Config ======", .{});
    println("============================", .{});
    println("| Cpu Count    : {: <9} |", .{sender_count + 1});
    println("| Message Count: {: <9} |", .{message_count});
    println("| Use Gpa      : {: <9} |", .{use_gpa});
    println("| Locked       : {: <9} |", .{locked});
    println("============================", .{});
    println("", .{});

    {
        var system = try a.System.init(allocator, .{
            .cpu_count = sender_count + 1,
            .locked = locked,
            .debug = debug,
        });
        defer system.deinit() catch {};

        const receiver = try system.spawnWithName(
            null,
            "Receiver",
            Receiver,
            .{ .count = 0, .max_messages = message_count },
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
                Sender,
                .{ .message_count = if (i == 0) per_sender + rest else per_sender },
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
