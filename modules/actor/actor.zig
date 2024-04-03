const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const erase = @import("erase.zig");
const config = @import("config");

const helper = @import("helper");
const println = helper.println;
const eprintln = helper.eprintln;

const containers = @import("containers");
const ztracy = @import("ztracy");

const aff = @cImport({
    @cInclude("affinity.h");
});

pub fn TypedBehavior(comptime T: type) type {
    return *const fn (self: *Actor, sys: *System, state: *T, from: ActorRef, msg: *Any) anyerror!void;
}

pub const StatelessBehavior = *const fn (self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void;

fn toOpaque(comptime T: type, behavior: TypedBehavior(T)) *anyopaque {
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    return @constCast(
        @ptrCast(behavior),
    );
}

fn statelessToOpaque(behavior: StatelessBehavior) *anyopaque {
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
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
    parent: ?ActorRef,

    call_behavior: *const fn (self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void,

    fn makeDealloc(comptime T: type) (fn (allocator: Allocator, ptr: *anyopaque) void) {
        return struct {
            fn dealloc(allocator: Allocator, ptr: *anyopaque) void {
                const tracy_zone = ztracy.Zone(@src());
                defer tracy_zone.End();
                const p: *T = @alignCast(@ptrCast(ptr));
                allocator.destroy(p);
            }
        }.dealloc;
    }

    fn makeEmptyDealloc() (fn (allocator: Allocator, ptr: *anyopaque) void) {
        return struct {
            fn dealloc(allocator: Allocator, ptr: *anyopaque) void {
                const tracy_zone = ztracy.Zone(@src());
                defer tracy_zone.End();
                _ = allocator;
                _ = ptr;
            }
        }.dealloc;
    }

    fn makeCallBehavior(comptime T: type) (fn (self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void) {
        return struct {
            fn callBehavior(self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void {
                const tracy_zone = ztracy.Zone(@src());
                defer tracy_zone.End();
                const behavior: TypedBehavior(T) = @alignCast(@ptrCast(self.behavior));
                const state: *T = @alignCast(@ptrCast(self.state));

                return behavior(self, sys, state, from, msg);
            }
        }.callBehavior;
    }

    fn makeStatelessCallBehavior() (fn (self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void) {
        return struct {
            fn callBehavior(self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void {
                const tracy_zone = ztracy.Zone(@src());
                defer tracy_zone.End();
                const behavior: StatelessBehavior = @alignCast(@ptrCast(self.behavior));

                return behavior(self, sys, from, msg);
            }
        }.callBehavior;
    }

    pub fn become(self: *Actor, comptime T: type, state: T, behavior: TypedBehavior(T)) !void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        self.behavior = toOpaque(T, behavior);
        self.call_behavior = Actor.makeCallBehavior(T);

        self.dealloc(self.allocator, self.state);
        self.dealloc = Actor.makeDealloc(T);

        const state_ptr = try self.allocator.create(T);
        state_ptr.* = state;
        self.state = @ptrCast(state_ptr);
    }

    pub fn becomeStateless(self: *Actor, behavior: StatelessBehavior) !void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        self.behavior = statelessToOpaque(behavior);
        self.call_behavior = Actor.makeStatelessCallBehavior();

        self.dealloc(self.allocator, self.state);
        self.dealloc = Actor.makeEmptyDealloc();
    }

    pub fn init(allocator: Allocator, comptime T: type, state: T, behavior: TypedBehavior(T)) !*Actor {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        var actor = try allocator.create(Actor);
        actor.allocator = allocator;
        actor.dealloc = Actor.makeEmptyDealloc();
        try actor.become(T, state, behavior);

        return actor;
    }

    pub fn initStateless(allocator: Allocator, behavior: StatelessBehavior) !*Actor {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        var actor = try allocator.create(Actor);
        actor.allocator = allocator;
        actor.dealloc = Actor.makeEmptyDealloc();
        try actor.becomeStateless(behavior);

        return actor;
    }

    pub fn deinit(self: *Actor) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
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
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        self.msg.deinit();
    }
};

pub const Mailbox = struct {
    actor: *Actor,
    queue: containers.Queue(*Envelope),
    scheduler: *Scheduler,

    pub fn init(allocator: Allocator, actor: *Actor, scheduler: *Scheduler, locked: bool) !*@This() {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        var mb = try allocator.create(Mailbox);

        mb.actor = actor;
        mb.queue = containers.Queue(*Envelope).init(allocator, locked);
        mb.scheduler = scheduler;

        return mb;
    }

    pub fn deinit(self: *Mailbox) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        while (self.queue.pop()) |env| {
            env.deinit();
        }
    }
};

pub const Scheduler = struct {
    new_mailboxes: std.ArrayList(*Mailbox),
    new_mailboxes_lock: std.Thread.Mutex,
    mailboxes: std.ArrayList(*Mailbox),
    running: std.atomic.Value(bool),
    worker: std.Thread,
    system: *System,
    cpu: usize,

    pub fn init(
        allocator: Allocator,
        system: *System,
        cpu: usize,
    ) !*@This() {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        var scheduler = try allocator.create(Scheduler);

        scheduler.mailboxes = std.ArrayList(*Mailbox).init(allocator);
        scheduler.new_mailboxes = std.ArrayList(*Mailbox).init(allocator);
        scheduler.new_mailboxes_lock = .{};
        scheduler.running = std.atomic.Value(bool).init(true);
        scheduler.system = system;
        scheduler.cpu = cpu;

        const worker = try std.Thread.spawn(.{ .allocator = allocator }, work, .{scheduler});
        scheduler.worker = worker;

        return scheduler;
    }

    pub fn deinit(self: *Scheduler) !void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        self.stop();
        while (self.mailboxes.popOrNull()) |mb| {
            mb.deinit();
        }
    }

    pub fn stop(self: *Scheduler) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        self.running.store(false, .monotonic);
    }

    pub fn wait(self: *Scheduler) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        self.worker.join();
    }

    fn work(self: *Scheduler) !void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        _ = aff.set_affinity(self.cpu);
        while (self.running.load(.monotonic)) {
            if (self.new_mailboxes_lock.tryLock()) {
                defer self.new_mailboxes_lock.unlock();
                while (self.new_mailboxes.popOrNull()) |mb| {
                    try self.mailboxes.append(mb);
                }
            }
            for (self.mailboxes.items) |mb| {
                if (mb.queue.pop()) |env| {
                    mb.actor.call_behavior(mb.actor, self.system, env.from, &env.msg) catch {};
                    if (!env.msg.read) {
                        env.msg.debug(mb.actor, env.msg.ptr);
                    }
                    env.msg.deinit();
                }
            }
        }
    }
};

pub const SystemOptions = struct {
    cpu_count: ?usize,
    locked: bool,
};

pub const System = struct {
    schedulers: std.ArrayList(*Scheduler),
    allocator: Allocator,
    counter: std.atomic.Value(usize),
    options: SystemOptions,

    pub fn init(allocator: Allocator, options: SystemOptions) !*@This() {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        var system = try allocator.create(System);
        var schedulers = std.ArrayList(*Scheduler).init(allocator);
        const cpu_count = options.cpu_count orelse try std.Thread.getCpuCount();
        for (0..cpu_count) |i| {
            try schedulers.append(try Scheduler.init(
                allocator,
                system,
                i,
            ));
        }
        system.allocator = allocator;
        system.schedulers = schedulers;
        system.counter = std.atomic.Value(usize).init(0);
        system.options = options;
        return system;
    }

    pub fn deinit(self: *System) !void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        for (try self.schedulers.toOwnedSlice()) |scheduler| {
            try scheduler.deinit();
        }
        self.schedulers.deinit();
    }

    pub fn spawnWithName(self: *System, parent: ?ActorRef, name: []const u8, T: type, state: T, behavior: TypedBehavior(T)) !ActorRef {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        const ref = try self.spawn(T, state, behavior);
        ref.ref.actor.name = name;
        ref.ref.actor.parent = parent;
        return ref;
    }

    pub fn spawnWithNameStateless(self: *System, parent: ?ActorRef, name: []const u8, behavior: StatelessBehavior) !ActorRef {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        const ref = try self.spawnStateless(behavior);
        ref.ref.actor.name = name;
        ref.ref.actor.parent = parent;
        return ref;
    }

    fn createRefAndAdd(self: *System, actor: *Actor) !ActorRef {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        const i = self.counter.fetchAdd(1, .monotonic);
        const mb = try Mailbox.init(self.allocator, actor, self.schedulers.items[i % self.schedulers.items.len], self.options.locked);

        var scheduler = self.schedulers.items[i % self.schedulers.items.len];
        scheduler.new_mailboxes_lock.lock();
        defer scheduler.new_mailboxes_lock.unlock();
        try scheduler.new_mailboxes.append(mb);

        const ref = ActorRef{ .ref = mb };
        actor.ref = ref;
        return ref;
    }

    pub fn spawn(self: *System, T: type, state: T, behavior: TypedBehavior(T)) !ActorRef {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        const actor = try Actor.init(
            self.allocator,
            T,
            state,
            behavior,
        );

        return try self.createRefAndAdd(actor);
    }

    pub fn spawnStateless(self: *System, behavior: StatelessBehavior) !ActorRef {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        const actor = try Actor.initStateless(
            self.allocator,
            behavior,
        );

        return try self.createRefAndAdd(actor);
    }

    pub fn wait(self: *System) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        for (self.schedulers.items) |scheduler| {
            scheduler.wait();
        }
    }

    pub fn send(self: *System, from: ActorRef, to: ActorRef, comptime T: type, value: T) !void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        const m = try self.allocator.create(Envelope);
        m.from = from;
        m.to = to;
        m.msg = try any(
            self.allocator,
            T,
            value,
        );
        try to.ref.queue.push(m);
    }

    pub fn stop(self: *System) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        for (self.schedulers.items) |scheduler| {
            scheduler.stop();
        }
    }
};

pub const Any = struct {
    ptr: erase.AnyPointer,
    allocator: Allocator,
    dealloc: *const fn (allocator: Allocator, ptr: erase.AnyPointer) void,
    debug: *const fn (actor: *Actor, ptr: erase.AnyPointer) void,
    read: bool,

    fn makeDealloc(comptime T: type) (fn (allocator: Allocator, ptr: erase.AnyPointer) void) {
        return struct {
            fn dealloc(allocator: Allocator, ptr: erase.AnyPointer) void {
                const tracy_zone = ztracy.Zone(@src());
                defer tracy_zone.End();
                const p = ptr.cast(*T);
                allocator.destroy(p);
            }
        }.dealloc;
    }

    fn makeDebug(comptime T: type) (fn (actor: *Actor, ptr: erase.AnyPointer) void) {
        return struct {
            fn debug(actor: *Actor, ptr: erase.AnyPointer) void {
                const tracy_zone = ztracy.Zone(@src());
                defer tracy_zone.End();
                const name = actor.name orelse "<unnamed>";
                if (ptr.tryCast(*[]const u8)) |s| {
                    eprintln("Message was not handled by {*}.\"{s}\": {s}", .{ actor, name, s.* });
                } else if (ptr.tryCast(*[]u8)) |s| {
                    eprintln("Message was not handled by {*}.\"{s}\": {s}", .{ actor, name, s.* });
                } else {
                    const p = ptr.cast(*T);
                    eprintln("Message was not handled by {*}.\"{s}\": {any}", .{ actor, name, p.* });
                }
            }
        }.debug;
    }

    pub fn init(allocator: Allocator, comptime T: type, v: T) !Any {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
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
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        const ptr = self.ptr.tryCast(*T);
        if (ptr) |p| {
            self.read = true;
            return p.*;
        }
        return null;
    }

    pub fn deinit(self: *const Any) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        self.dealloc(self.allocator, self.ptr);
    }
};

pub fn any(allocator: Allocator, comptime T: type, v: T) !Any {
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    return Any.init(allocator, T, v);
}
