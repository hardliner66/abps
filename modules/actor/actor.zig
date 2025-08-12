const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const config = @import("config");

const helper = @import("helper");
const println = helper.println;
const eprintln = helper.eprintln;

fn WeakPtr(comptime T: type) type {
    return *T;
}

const containers = @import("containers");

const aff = @cImport({
    @cInclude("affinity.h");
});

pub const ErasedBehavior = struct {
    const Self = @This();

    instance: *anyopaque,
    allocator: Allocator,

    // The handle method signature expected by the system
    handle: *const fn (self: *Actor, sys: *System, from: ?ActorRef, msg: *Any) anyerror!void,

    // Function to deallocate the behavior
    destroy: *const fn (self: *Self) void,
};

pub fn Behavior(comptime T: type) type {
    return struct {
        const Self = @This();

        // The handle method signature expected by the system
        fn handle(self: *Actor, sys: *System, from: ?ActorRef, msg: *Any) !void {
            const instance: *T = @ptrCast(@alignCast(self.behavior.instance));
            // Forward the handle to the instance's method
            try instance.handle(self, sys, from, msg);
        }

        // Factory function to create a new behavior
        pub fn create(allocator: Allocator, args: T) !*ErasedBehavior {
            const instance = try allocator.create(T);
            instance.* = args;

            const behavior = try allocator.create(ErasedBehavior);
            behavior.* = .{
                .instance = @ptrCast(instance),
                .allocator = allocator,
                .handle = &handle,
                .destroy = &destroy,
            };
            return behavior;
        }

        // Function to deallocate the behavior
        fn destroy(self: *ErasedBehavior) void {
            const instance: *T = @ptrCast(@alignCast(self.instance));
            self.allocator.destroy(instance);
            self.allocator.destroy(self);
        }
    };
}

pub const Actor = struct {
    ref: ActorRef,
    name: []const u8,
    behavior: *ErasedBehavior,
    allocator: Allocator,
    dealloc: *const fn (allocator: Allocator, ptr: *anyopaque) void,
    parent: ?ActorRef,

    pub fn become(self: *Actor, comptime T: type, behavior: T) !void {
        self.behavior.destroy(self.behavior);
        self.behavior = try Behavior(T).create(self.allocator, behavior);
    }

    pub fn init(allocator: Allocator, comptime T: type, behavior: T) !*Actor {
        var actor = try allocator.create(Actor);
        actor.allocator = allocator;
        actor.behavior = try Behavior(T).create(actor.allocator, behavior);

        return actor;
    }

    pub fn deinit(self: *Actor) void {
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
    from: ?ActorRef,
    msg: Any,

    pub fn deinit(self: *Envelope) void {
        self.msg.deinit();
    }
};

pub const Mailbox = struct {
    actor: *Actor,
    queue: containers.Queue(*Envelope),
    scheduler: WeakPtr(Scheduler),
    allocator: Allocator,

    pub fn init(allocator: Allocator, actor: *Actor, scheduler: *Scheduler, locked: bool) !*@This() {
        var mb = try allocator.create(Mailbox);

        mb.actor = actor;
        mb.queue = containers.Queue(*Envelope).init(allocator, locked);
        mb.scheduler = scheduler;
        mb.allocator = allocator;

        return mb;
    }

    pub fn deinit(self: *Mailbox) void {
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
        self.stop();
        while (self.mailboxes.pop()) |mb| {
            mb.deinit();
            self.allocator.destroy(mb);
        }
        self.mailboxes.deinit();
        self.new_mailboxes.deinit();
    }

    pub fn stop(self: *Scheduler) void {
        self.running.store(false, .monotonic);
    }

    pub fn wait(self: *Scheduler) void {
        self.worker.join();
    }

    fn work(self: *Scheduler) !void {
        _ = aff.set_affinity(self.cpu);
        while (self.running.load(.monotonic)) {
            if (self.new_mailboxes_lock.tryLock()) {
                defer self.new_mailboxes_lock.unlock();
                while (self.new_mailboxes.pop()) |mb| {
                    try self.mailboxes.append(mb);
                }
            }
            for (self.mailboxes.items) |mb| {
                if (mb.queue.pop()) |env| {
                    mb.actor.behavior.handle(mb.actor, self.system, env.from, &env.msg) catch |err| {
                        if (mb.actor.parent) |p| {
                            try self.system.send(mb.actor.ref, p, anyerror, err);
                        } else {
                            eprintln("Actor Error but no parent to send to. {} @ {*}.\"{s}\"", .{
                                err,
                                mb.actor,
                                mb.actor.name,
                            });
                        }
                    };
                    if (!env.msg.read and self.system.options.debug) {
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
    debug: bool,
};

pub const System = struct {
    schedulers: std.ArrayList(*Scheduler),
    allocator: Allocator,
    counter: std.atomic.Value(usize),
    options: SystemOptions,

    pub fn init(allocator: Allocator, options: SystemOptions) !*@This() {
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
        while (self.schedulers.pop()) |scheduler| {
            try scheduler.deinit();
            self.allocator.destroy(scheduler);
        }
        self.schedulers.deinit();
        self.allocator.destroy(self);
    }

    pub fn spawnWithName(self: *System, parent: ?ActorRef, name: []const u8, comptime T: type, behavior: T) !ActorRef {
        const ref = try self.spawn(parent, T, behavior);
        ref.ref.actor.name = name;
        return ref;
    }

    fn createRefAndAdd(self: *System, actor: *Actor) !ActorRef {
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

    pub fn spawn(self: *System, parent: ?ActorRef, comptime T: type, behavior: T) !ActorRef {
        const actor = try Actor.init(
            self.allocator,
            T,
            behavior,
        );
        actor.parent = parent;
        actor.name = "<unnamed>";

        return try self.createRefAndAdd(actor);
    }

    pub fn wait(self: *System) void {
        for (self.schedulers.items) |scheduler| {
            scheduler.wait();
        }
    }

    pub fn send(self: *System, from: ?ActorRef, to: ActorRef, comptime T: type, value: T) !void {
        const m = try self.allocator.create(Envelope);
        m.from = from;
        m.to = to;
        m.msg = try any(T).init(
            self.allocator,
            value,
        );
        try to.ref.queue.push(m);
    }

    pub fn stop(self: *System) void {
        for (self.schedulers.items) |scheduler| {
            scheduler.stop();
        }
    }
};

const AnyDealloc = *const fn (allocator: Allocator, ptr: *anyopaque) void;
const AnyDebug = *const fn (actor: *Actor, ptr: *anyopaque) void;
pub const Any = struct {
    ptr: *anyopaque,
    allocator: Allocator,
    dealloc: AnyDealloc,
    debug: AnyDebug,
    read: bool,
    type_name: []const u8,

    fn init(allocator: Allocator, comptime T: type, value: T, dealloc: AnyDealloc, debug: AnyDebug) !Any {
        const ptr = try allocator.create(T);
        ptr.* = value;
        return .{
            .ptr = @ptrCast(ptr),
            .allocator = allocator,
            .dealloc = dealloc,
            .debug = debug,
            .read = false,
            .type_name = @typeName(T),
        };
    }

    pub fn matches(self: *Any, comptime T: type) ?T {
        if (std.mem.eql(u8, self.type_name, @typeName(T))) {
            self.read = true;
            const ptr: *T = @ptrCast(@alignCast(self.ptr));
            return ptr.*;
        }
        return null;
    }

    pub fn deinit(self: *const Any) void {
        self.dealloc(self.allocator, self.ptr);
    }
};

pub fn any(comptime T: type) type {
    return struct {
        ptr: *anyopaque,
        allocator: Allocator,
        dealloc_fn: *const fn (allocator: Allocator, ptr: *anyopaque) void,
        debug_fn: *const fn (actor: *Actor, ptr: *anyopaque) void,
        read: bool,

        fn dealloc(allocator: Allocator, ptr: *anyopaque) void {
            const p: *T = @ptrCast(@alignCast(ptr));
            allocator.destroy(p);
        }

        fn debug(actor: *Actor, ptr: *anyopaque) void {
            const p: *T = @ptrCast(@alignCast(ptr));
            const format_string = comptime if (std.mem.eql(u8, @typeName(T), @typeName(*[]const u8)))
                "Message was not handled by {*}.\"{s}\": {s}"
            else if (std.mem.eql(u8, @typeName(T), @typeName(*[]u8)))
                "Message was not handled by {*}.\"{s}\": {s}"
            else if (std.mem.eql(u8, @typeName(T), @typeName([]const u8)))
                "Message was not handled by {*}.\"{s}\": {s}"
            else if (std.mem.eql(u8, @typeName(T), @typeName([]u8)))
                "Message was not handled by {*}.\"{s}\": {s}"
            else
                "Message was not handled by {*}.\"{s}\": {any}";
            eprintln(format_string, .{ actor, actor.name, p.* });
        }

        pub fn init(allocator: Allocator, v: T) !Any {
            return try Any.init(allocator, T, v, &dealloc, &debug);
        }
    };
}
