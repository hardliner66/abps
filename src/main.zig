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

fn die(self: *a.Actor, sys: *a.System, from: a.ActorRef, msg: *a.Any) anyerror!void {
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    _ = self;
    _ = from;
    // make sure we dont get a "message was not handled!" message
    _ = msg.matches(void);
    sys.stop();
}

const zigTime = std.time;
const cTime = @cImport(@cInclude("time.h"));

fn counting(self: *a.Actor, sys: *a.System, state: *a.ActorRef, _: a.ActorRef, msg: *a.Any) anyerror!void {
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    if (msg.matches(a.ActorRef)) |r| {
        state.* = r;
    }
    if (msg.matches(i32)) |v| {
        if (v < config.max_messages) {
            // const curtime = zigTime.timestamp();
            // const tm = cTime.localtime(&curtime);
            //
            // var buf: [200]u8 = .{0} ** 200;
            // _ = cTime.strftime(@as([*c]u8, @ptrCast(@alignCast(&buf))), 200, "%H:%M:%S", tm);
            // println("{s}: Working({}): {}", .{ buf, std.Thread.getCurrentId(), v });
            try sys.send(self.ref, state.*, i32, v + 1);
        } else {
            println("Done: {}", .{v});
            try self.becomeStateless(&die);
            try sys.send(self.ref, self.ref, void, {});
        }
    }
}

fn initial(self: *a.Actor, _: *a.System, _: a.ActorRef, msg: *a.Any) anyerror!void {
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    if (msg.matches(a.ActorRef)) |r| {
        try self.become(a.ActorRef, r, &counting);
    }
}

pub fn main() !void {
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    const params = comptime clap.parseParamsComptime(
        \\-h                           Display this help and exit.
        \\    --help                   Display this help and exit.
        \\-d, --debug                  An option parameter, which takes a value.
        \\-c, --cpu_count <usize>      How many schedulers to spawn.
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

    if (config.use_gpa) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        allocator = gpa.allocator();
    }

    const cpu_count = res.args.cpu_count orelse try std.Thread.getCpuCount();

    var system = try a.System.init(allocator, .{ .cpu_count = cpu_count });
    defer system.deinit() catch {};

    const first = try system.spawnWithNameStateless("Counting Actor 1", &initial);
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

        last = try system.spawnWithName(hello_world, a.ActorRef, last, &counting);
    }
    try system.send(first, first, []const u8, "test");
    try system.send(first, first, a.ActorRef, last);
    try system.send(first, first, i32, 1);

    system.wait();
}
