const std = @import("std");
const mem = std.mem;
const erase = @import("erase.zig");
const lfq = @import("lfqueue.zig");

const Allocator = mem.Allocator;

pub fn TypedBehavior(comptime T: type) type {
    return *const fn (self: *Actor, sys: *System, state: *T, from: ActorRef, msg: *Any) anyerror!void;
}

pub const StatelessBehavior = *const fn (self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void;

fn toOpaque(comptime T: type, behavior: TypedBehavior(T)) *anyopaque {
    return @constCast(
        @ptrCast(behavior),
    );
}

fn statelessToOpaque(behavior: StatelessBehavior) *anyopaque {
    return @constCast(
        @ptrCast(behavior),
    );
}

pub const Actor = struct {
    ref: ActorRef,
    name: ?[]const u8,
    behavior: *anyopaque,
    state: *anyopaque,
    allocator: Allocator,
    dealloc: *const fn (allocator: Allocator, ptr: *anyopaque) void,

    call_behavior: *const fn (self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void,

    fn makeDealloc(comptime T: type) (fn (allocator: Allocator, ptr: *anyopaque) void) {
        return struct {
            fn dealloc(allocator: Allocator, ptr: *anyopaque) void {
                const p: *T = @alignCast(@ptrCast(ptr));
                allocator.destroy(p);
            }
        }.dealloc;
    }

    fn makeEmptyDealloc() (fn (allocator: Allocator, ptr: *anyopaque) void) {
        return struct {
            fn dealloc(allocator: Allocator, ptr: *anyopaque) void {
                _ = allocator;
                _ = ptr;
            }
        }.dealloc;
    }

    fn makeCallBehavior(comptime T: type) (fn (self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void) {
        return struct {
            fn callBehavior(self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void {
                const behavior: TypedBehavior(T) = @alignCast(@ptrCast(self.behavior));
                const state: *T = @alignCast(@ptrCast(self.state));

                return behavior(self, sys, state, from, msg);
            }
        }.callBehavior;
    }

    fn makeStatelessCallBehavior() (fn (self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void) {
        return struct {
            fn callBehavior(self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void {
                const behavior: StatelessBehavior = @alignCast(@ptrCast(self.behavior));

                return behavior(self, sys, from, msg);
            }
        }.callBehavior;
    }

    pub fn become(self: *Actor, comptime T: type, state: T, behavior: TypedBehavior(T)) !void {
        self.behavior = toOpaque(T, behavior);
        self.call_behavior = Actor.makeCallBehavior(T);

        self.dealloc(self.allocator, self.state);
        self.dealloc = Actor.makeDealloc(T);

        const state_ptr = try self.allocator.create(T);
        state_ptr.* = state;
        self.state = @ptrCast(state_ptr);
    }

    pub fn becomeStateless(self: *Actor, behavior: StatelessBehavior) !void {
        self.behavior = statelessToOpaque(behavior);
        self.call_behavior = Actor.makeStatelessCallBehavior();

        self.dealloc(self.allocator, self.state);
        self.dealloc = Actor.makeEmptyDealloc();
    }

    pub fn init(allocator: Allocator, comptime T: type, state: T, behavior: TypedBehavior(T)) !*Actor {
        var actor = try allocator.create(Actor);
        actor.allocator = allocator;
        actor.dealloc = Actor.makeEmptyDealloc();
        try actor.become(T, state, behavior);

        return actor;
    }

    pub fn with_name(self: *Actor, name: []const u8) *Actor {
        self.name = name;
        return self;
    }

    pub fn initStateless(allocator: Allocator, behavior: StatelessBehavior) !*Actor {
        var actor = try allocator.create(Actor);
        actor.allocator = allocator;
        actor.dealloc = Actor.makeEmptyDealloc();
        try actor.becomeStateless(behavior);

        return actor;
    }

    pub fn deinit(self: *Actor) void {
        self.state.deinit();
    }
};

pub const ActorRef = struct {
    ref: *Mailbox,
};

pub const DeadLetter = struct {
    env: Envelope,
};

pub const Envelope = struct {
    to: ActorRef,
    from: ActorRef,
    msg: Any,

    pub fn deinit(self: *Envelope) void {
        self.msg.deinit();
    }
};

pub const Mailbox = struct {
    actor: *Actor,
    queue: lfq.LfQueue(*Envelope),
    scheduler: *Scheduler,

    pub fn init(allocator: Allocator, actor: *Actor, scheduler: *Scheduler) !*@This() {
        var mb = try allocator.create(Mailbox);

        mb.actor = actor;
        mb.queue = lfq.LfQueue(*Envelope).init(allocator);
        mb.scheduler = scheduler;

        return mb;
    }

    pub fn deinit(self: *Mailbox) void {
        while (self.queue.pop()) |env| {
            env.deinit();
        }
    }
};

pub const Scheduler = struct {
    mailboxes: std.ArrayList(*Mailbox),
    running: std.atomic.Value(bool),
    worker: std.Thread,
    system: *System,
    sema: std.Thread.Semaphore,

    pub fn init(allocator: Allocator, system: *System) !*@This() {
        var scheduler = try allocator.create(Scheduler);

        scheduler.mailboxes = std.ArrayList(*Mailbox).init(allocator);
        scheduler.running = std.atomic.Value(bool).init(true);
        scheduler.system = system;
        scheduler.sema = std.Thread.Semaphore{};

        const worker = try std.Thread.spawn(.{ .allocator = allocator }, work, .{scheduler});
        scheduler.worker = worker;

        return scheduler;
    }

    pub fn deinit(self: *Scheduler) !void {
        self.stop();
        while (self.mailboxes.popOrNull()) |mb| {
            mb.deinit();
        }
    }

    pub fn stop(self: *Scheduler) void {
        self.running.store(false, .monotonic);
        self.sema.post();
    }

    pub fn wait(self: *Scheduler) void {
        self.worker.join();
    }

    fn work(self: *Scheduler) !void {
        while (self.running.load(.monotonic)) {
            if (self.sema.timedWait(1_000_000)) |_| {
                for (self.mailboxes.items) |mb| {
                    if (mb.queue.pop()) |env| {
                        mb.actor.call_behavior(mb.actor, self.system, env.from, &env.msg) catch {};
                        if (!env.msg.read) {
                            env.msg.debug(mb.actor, env.msg.ptr);
                        }
                        env.msg.deinit();
                    }
                }
            } else |_| {}
        }
    }
};

pub const System = struct {
    schedulers: std.ArrayList(*Scheduler),
    allocator: Allocator,
    counter: std.atomic.Value(usize),

    pub fn init(allocator: Allocator) !*@This() {
        var system = try allocator.create(System);
        var schedulers = std.ArrayList(*Scheduler).init(allocator);
        const cpu_count = try std.Thread.getCpuCount();
        for (0..cpu_count) |_| {
            try schedulers.append(try Scheduler.init(
                allocator,
                system,
            ));
        }
        system.allocator = allocator;
        system.schedulers = schedulers;
        system.counter = std.atomic.Value(usize).init(0);
        return system;
    }

    pub fn deinit(self: *System) !void {
        for (try self.schedulers.toOwnedSlice()) |scheduler| {
            try scheduler.deinit();
        }
        self.schedulers.deinit();
    }

    pub fn spawnWithName(self: *System, name: []const u8, T: type, state: T, behavior: TypedBehavior(T)) !ActorRef {
        const ref = try self.spawn(T, state, behavior);
        ref.ref.actor.name = name;
        return ref;
    }

    pub fn spawn(self: *System, T: type, state: T, behavior: TypedBehavior(T)) !ActorRef {
        const actor = try Actor.init(
            self.allocator,
            T,
            state,
            behavior,
        );
        const i = self.counter.fetchAdd(1, .monotonic);
        const mb = try Mailbox.init(self.allocator, actor, self.schedulers.items[i]);
        try self.schedulers.items[i].mailboxes.append(mb);

        const ref = ActorRef{ .ref = mb };
        actor.ref = ref;
        return ref;
    }

    pub fn wait(self: *System) void {
        for (self.schedulers.items) |scheduler| {
            scheduler.wait();
        }
    }

    pub fn send(self: *System, from: ActorRef, to: ActorRef, comptime T: type, value: T) !void {
        const m = try self.allocator.create(Envelope);
        m.from = from;
        m.to = to;
        m.msg = try any(
            self.allocator,
            T,
            value,
        );
        try to.ref.queue.push(m);
        to.ref.scheduler.sema.post();
    }

    pub fn stop(self: *System) void {
        for (self.schedulers.items) |scheduler| {
            scheduler.stop();
        }
    }
};

fn print(comptime format: []const u8, args: anytype) void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    stdout.print(format, args) catch {};

    bw.flush() catch {};
}

fn eprint(comptime format: []const u8, args: anytype) void {
    const stdout_file = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    stdout.print(format, args) catch {};

    bw.flush() catch {};
}

pub const Any = struct {
    ptr: erase.AnyPointer,
    allocator: Allocator,
    dealloc: *const fn (allocator: Allocator, ptr: erase.AnyPointer) void,
    debug: *const fn (actor: *Actor, ptr: erase.AnyPointer) void,
    read: bool,

    fn makeDealloc(comptime T: type) (fn (allocator: Allocator, ptr: erase.AnyPointer) void) {
        return struct {
            fn dealloc(allocator: Allocator, ptr: erase.AnyPointer) void {
                const p = ptr.cast(*T);
                allocator.destroy(p);
            }
        }.dealloc;
    }

    fn makeDebug(comptime T: type) (fn (actor: *Actor, ptr: erase.AnyPointer) void) {
        return struct {
            fn debug(actor: *Actor, ptr: erase.AnyPointer) void {
                const name = actor.name orelse "<unnamed>";
                if (ptr.tryCast(*[]const u8)) |s| {
                    eprint("Message was not handled by {*}.\"{s}\": {s}\n", .{ actor, name, s.* });
                } else if (ptr.tryCast(*[]u8)) |s| {
                    eprint("Message was not handled by {*}.\"{s}\": {s}\n", .{ actor, name, s.* });
                } else {
                    const p = ptr.cast(*T);
                    eprint("Message was not handled by {*}.\"{s}\": {any}\n", .{ actor, name, p.* });
                }
            }
        }.debug;
    }

    pub fn init(allocator: Allocator, comptime T: type, v: T) !Any {
        const value = try allocator.create(T);
        value.* = v;
        return Any{
            .ptr = erase.AnyPointer.make(*T, value),
            .read = false,
            .allocator = allocator,
            .dealloc = Any.makeDealloc(T),
            .debug = Any.makeDebug(T),
        };
    }

    pub fn matches(self: *Any, comptime T: type) ?T {
        const ptr = self.ptr.tryCast(*T);
        if (ptr) |p| {
            self.read = true;
            return p.*;
        }
        return null;
    }

    pub fn deinit(self: *const Any) void {
        self.dealloc(self.allocator, self.ptr);
    }
};

pub fn any(allocator: Allocator, comptime T: type, v: T) !Any {
    return Any.init(allocator, T, v);
}
