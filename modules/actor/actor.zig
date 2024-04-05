const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const erase = @import("erase.zig");
const config = @import("config");

const helper = @import("helper");
const println = helper.println;
const eprintln = helper.eprintln;

fn WeakPtr(comptime T: type) type {
    return *T;
}

const containers = @import("containers");
const ztracy = @import("ztracy");

const aff = @cImport({
    @cInclude("affinity.h");
});

pub const ErasedBehavior = struct {
    const Self = @This();

    instance: *anyopaque,
    allocator: Allocator,

    // The call method signature expected by the system
    call: *const fn (self: *Actor, sys: *System, from: ActorRef, msg: *Any) anyerror!void,

    // Function to deallocate the behavior
    destroy: *const fn (self: *Self) void,
};

pub fn Behavior(comptime T: type) type {
    return struct {
        const Self = @This();

        // The call method signature expected by the system
        pub fn call(self: *Actor, sys: *System, from: ActorRef, msg: *Any) !void {
            const instance: *T = @alignCast(@ptrCast(self.behavior.instance));
            // Forward the call to the instance's method
            try instance.call(self, sys, from, msg);
        }

        // Factory function to create a new behavior
        pub fn create(allocator: Allocator, args: T) !*ErasedBehavior {
            const instance = try allocator.create(T);
            instance.* = args;

            const behavior = try allocator.create(ErasedBehavior);
            behavior.* = .{
                .instance = @ptrCast(instance),
                .allocator = allocator,
                .call = &call,
                .destroy = &destroy,
            };
            return behavior;
        }

        // Function to deallocate the behavior
        pub fn destroy(self: *ErasedBehavior) void {
            const instance: *T = @alignCast(@ptrCast(self.instance));
            self.allocator.destroy(instance);
            self.allocator.destroy(self);
        }
    };
}

pub const Actor = struct {
    ref: ActorRef,
    name: ?[]const u8,
    behavior: *ErasedBehavior,
    allocator: Allocator,
    dealloc: *const fn (allocator: Allocator, ptr: *anyopaque) void,
    parent: ?ActorRef,

    pub fn become(self: *Actor, comptime T: type, behavior: T) !void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        self.behavior.destroy(self.behavior);
        self.behavior = try Behavior(T).create(self.allocator, behavior);
    }

    pub fn init(allocator: Allocator, comptime T: type, behavior: T) !*Actor {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        var actor = try allocator.create(Actor);
        actor.allocator = allocator;
        actor.behavior = try Behavior(T).create(actor.allocator, behavior);

        return actor;
    }

    pub fn deinit(self: *Actor) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        self.behavior.destroy(self.behavior);
    }
};

pub const ActorRef = struct {
    ref: WeakPtr(Mailbox),
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
    scheduler: WeakPtr(Scheduler),
    allocator: Allocator,

    pub fn init(allocator: Allocator, actor: *Actor, scheduler: *Scheduler, locked: bool) !*@This() {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        var mb = try allocator.create(Mailbox);

        mb.actor = actor;
        mb.queue = containers.Queue(*Envelope).init(allocator, locked);
        mb.scheduler = scheduler;
        mb.allocator = allocator;

        return mb;
    }

    pub fn deinit(self: *Mailbox) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        while (self.queue.pop()) |env| {
            env.deinit();
            self.allocator.destroy(env);
        }
        self.queue.deinit();
        self.actor.deinit();
        self.allocator.destroy(self.actor);
    }
};

pub const Scheduler = struct {
    new_mailboxes: std.ArrayList(*Mailbox),
    new_mailboxes_lock: std.Thread.Mutex,
    mailboxes: std.ArrayList(*Mailbox),
    running: std.atomic.Value(bool),
    worker: std.Thread,
    system: WeakPtr(System),
    cpu: usize,
    allocator: Allocator,

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
        scheduler.allocator = allocator;

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
            self.allocator.destroy(mb);
        }
        self.mailboxes.deinit();
        self.new_mailboxes.deinit();
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
                    mb.actor.behavior.call(mb.actor, self.system, env.from, &env.msg) catch {};
                    if (!env.msg.read) {
                        env.msg.debug(mb.actor, env.msg.ptr);
                    }
                    env.deinit();
                    self.allocator.destroy(env);
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
        while (self.schedulers.popOrNull()) |scheduler| {
            try scheduler.deinit();
            self.allocator.destroy(scheduler);
        }
        self.schedulers.deinit();
        self.allocator.destroy(self);
    }

    pub fn spawnWithName(self: *System, parent: ?ActorRef, name: []const u8, comptime T: type, behavior: T) !ActorRef {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        const ref = try self.spawn(T, behavior);
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

    pub fn spawn(self: *System, comptime T: type, behavior: T) !ActorRef {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        const actor = try Actor.init(
            self.allocator,
            T,
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
