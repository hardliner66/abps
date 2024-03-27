const std = @import("std");
const mem = std.mem;
const erase = @import("erase.zig");
const lfq = @import("lfqueue.zig");

const Allocator = mem.Allocator;

pub const Behavior = *const fn (self: *Actor, sys: *System, state: *Any, from: ActorRef, msg: *Any) anyerror!void;

fn toOpaque(behavior: Behavior) *anyopaque {
    return @constCast(
        @ptrCast(behavior),
    );
}

fn fromOpaque(behavior: *anyopaque) Behavior {
    return @constCast(
        @ptrCast(behavior),
    );
}

pub const Actor = struct {
    ref: ActorRef,
    behavior: *anyopaque,
    last_behavior: ?*anyopaque,
    state: Any,

    pub fn init(allocator: Allocator, state: Any, behavior: Behavior) !*Actor {
        var actor = try allocator.create(Actor);
        actor.behavior = toOpaque(behavior);
        actor.state = state;
        actor.last_behavior = null;

        return actor;
    }

    pub fn deinit(self: *Actor) void {
        self.state.deinit();
    }

    pub fn become(self: *Actor, behavior: Behavior) void {
        self.last_behavior = self.behavior;
        self.behavior = toOpaque(behavior);
    }

    pub fn unbecome(self: *Actor) void {
        if (self.last_behavior) |b| {
            self.behavior = b;
            self.last_behavior = null;
        }
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
    running: bool,
    worker: std.Thread,
    system: *System,
    sema: std.Thread.Semaphore,

    pub fn init(allocator: Allocator, system: *System) !*@This() {
        var scheduler = try allocator.create(Scheduler);

        scheduler.mailboxes = std.ArrayList(*Mailbox).init(allocator);
        scheduler.running = true;
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
        self.running = false;
        self.sema.post();
    }

    pub fn wait(self: *Scheduler) void {
        self.worker.join();
    }

    fn work(self: *Scheduler) !void {
        while (self.running) {
            if (self.sema.timedWait(1_000_000)) |_| {
                for (self.mailboxes.items) |mb| {
                    if (mb.queue.pop()) |env| {
                        const behavior: Behavior = fromOpaque(mb.actor.behavior);
                        try behavior(mb.actor, self.system, &mb.actor.state, env.from, &env.msg);
                        if (!env.msg.read) {
                            env.msg.debug(env.msg.ptr);
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

    pub fn spawn(self: *System, T: type, state: T, behavior: Behavior) !ActorRef {
        const actor = try Actor.init(
            self.allocator,
            try any(self.allocator, T, state),
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

pub const Any = struct {
    ptr: erase.AnyPointer,
    allocator: Allocator,
    dealloc: *const fn (allocator: Allocator, ptr: erase.AnyPointer) void,
    debug: *const fn (ptr: erase.AnyPointer) void,
    read: bool,

    pub fn makeDealloc(comptime T: type) (fn (allocator: Allocator, ptr: erase.AnyPointer) void) {
        return struct {
            fn dealloc(allocator: Allocator, ptr: erase.AnyPointer) void {
                const p = ptr.cast(*T);
                allocator.destroy(p);
            }
        }.dealloc;
    }

    pub fn makeDebug(comptime T: type) (fn (ptr: erase.AnyPointer) void) {
        return struct {
            fn debug(ptr: erase.AnyPointer) void {
                const p = ptr.cast(*T);
                std.debug.print("Could not deliver message: {any}\n", .{p.*});
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
