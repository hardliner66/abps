const std = @import("std");
const fmt = std.fmt;
const eql = std.mem.eql;
const a = @import("actor");
const helper = @import("helper");
const clap = @import("clap");
const println = helper.println;
const eprintln = helper.eprintln;
const config = @import("config");

const Die = struct {
    pub fn handle(_: *Die, _: *a.Actor, sys: *a.System, _: ?a.ActorRef, msg: *a.Any) anyerror!void {
        // make sure we dont get a "message was not handled!" message
        _ = msg.matches(void);
        sys.stop();
    }
};

const zigTime = std.time;
const cTime = @cImport(@cInclude("time.h"));

const SomeError = error{
    SomeError,
};

const Counting = struct {
    max_messages: usize,
    next: a.ActorRef,

    pub fn handle(state: *@This(), self: *a.Actor, sys: *a.System, _: ?a.ActorRef, msg: *a.Any) anyerror!void {
        if (msg.matches(a.ActorRef)) |r| {
            state.next = r;
        }
        if (msg.matches(i32)) |v| {
            if (v < state.max_messages) {
                // const curtime = zigTime.timestamp();
                // const tm = cTime.localtime(&curtime);
                //
                // var buf: [200]u8 = .{0} ** 200;
                // _ = cTime.strftime(@as([*c]u8, @ptrCast(@alignCast(&buf))), 200, "%H:%M:%S", tm);
                // println("{s}: Working({}): {}", .{ buf, std.Thread.getCurrentId(), v });
                try sys.send(self.ref, state.next, i32, v + 1);
            } else {
                println("Done: {}", .{v});
                try self.become(Die, .{});
                try sys.send(self.ref, self.ref, void, {});
                return SomeError.SomeError;
            }
        }
    }
};

const Initial = struct {
    max_messages: usize,
    pub fn handle(state: *@This(), self: *a.Actor, _: *a.System, _: ?a.ActorRef, msg: *a.Any) anyerror!void {
        if (msg.matches(a.ActorRef)) |r| {
            try self.become(Counting, .{ .next = r, .max_messages = state.max_messages });
        }
    }
};

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h                           Display usage and exit.
        \\    --help                   Display this help and exit.
        \\-d, --debug                  An option parameter, which takes a value.
        \\-c, --cpu_count <usize>      How many schedulers to spawn.
        \\-m, --message_count <usize>  How many messages to send. (Max Value: 999999999)
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
    const cpu_count = res.args.cpu_count orelse default_cpu_count;
    const message_count = res.args.message_count orelse 1000;

    if (message_count > 999_999_999) {
        eprintln("Message count must be 999999999 or lower!", .{});
        return;
    }

    println("============================", .{});
    println("====== Runtime Config ======", .{});
    println("============================", .{});
    println("| Cpu Count    : {: <9} |", .{cpu_count});
    println("| Message Count: {: <9} |", .{message_count});
    println("| Use Gpa      : {: <9} |", .{use_gpa});
    println("| Locked       : {: <9} |", .{locked});
    println("============================", .{});
    println("", .{});

    {
        var system = try a.System.init(allocator, .{
            .cpu_count = cpu_count,
            .locked = locked,
            .debug = debug,
        });
        defer system.deinit() catch {};

        const first = try system.spawnWithName(
            null,
            "Counting Actor 1",
            Initial,
            .{ .max_messages = message_count },
        );
        var last: a.ActorRef = first;
        for (0..cpu_count - 1) |i| {
            var all_together: [100]u8 = undefined;
            // You can use slice syntax with at least one runtime-known index on an
            // array to convert an array into a slice.
            var start: usize = 0;
            _ = &start;
            const all_together_slice = all_together[start..];
            // String concatenation example.
            const hello_world = try fmt.bufPrint(all_together_slice, "Counting Actor {}", .{i + 2});

            last = try system.spawnWithName(
                null,
                hello_world,
                Counting,
                .{ .next = last, .max_messages = message_count },
            );
        }
        try system.send(first, first, []const u8, "test");
        try system.send(first, first, a.ActorRef, last);
        try system.send(first, first, i32, 1);

        const abcd = try system.spawnWithName(
            null,
            "",
            struct {
                pub fn handle(_: *@This(), _: *a.Actor, _: *a.System, _: ?a.ActorRef, msg: *a.Any) anyerror!void {
                    if (msg.matches(i32)) |v| {
                        println("Anonymous Actor got value: {}", .{v});
                    }
                }
            },
            .{},
        );
        try system.send(abcd, abcd, i32, 5);

        system.wait();
    }

    if (use_gpa) {
        if (gpa.detectLeaks()) {
            eprintln("Leak detected!", .{});
        }
    }
}
