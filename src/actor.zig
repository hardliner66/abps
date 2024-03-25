const std = @import("std");
const mem = std.mem;
const erase = @import("erase.zig");

const Allocator = mem.Allocator;

pub const Behavior = *const fn (self: *Actor, sys: *System, state: *Any, from: ActorRef, msg: *Any) anyerror!void;

fn toOpaque(behavior: Behavior) *anyopaque {
    return @constCast(
        @ptrCast(@alignCast(behavior)),
    );
}

fn fromOpaque(behavior: *anyopaque) Behavior {
    return @constCast(
        @ptrCast(@alignCast(behavior)),
    );
}

pub const Actor = struct {
    ref: ActorRef,
    behavior: *anyopaque,
    last_behavior: ?*anyopaque,
    state: Any,

    pub fn init(ref: ActorRef, state: Any, behavior: Behavior) Actor {
        return .{
            .behavior = toOpaque(behavior),
            .state = state,
            .ref = ref,
            .last_behavior = null,
        };
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
    name: []const u8,
};

pub const DeadLetter = struct {
    msg: Message,
};

pub const Message = struct {
    to: ActorRef,
    from: ActorRef,
    msg: Any,
};

pub const System = struct {
    actors: std.StringHashMap(Actor),
    queue: std.ArrayList(*Message),
    running: bool,
    allocator: Allocator,

    pub fn new(alloc: Allocator) @This() {
        return .{
            .allocator = alloc,
            .actors = std.StringHashMap(Actor).init(alloc),
            .queue = std.ArrayList(*Message).init(alloc),
            .running = true,
        };
    }

    pub fn destroy(self: *System) void {
        var it = self.actors.valueIterator();
        while (it.next()) |value_ptr| {
            value_ptr.deinit();
        }
        self.actors.deinit();
        self.queue.clearAndFree();
    }

    pub fn spawn(self: *System, T: type, state: T, behavior: Behavior) !ActorRef {
        const actor = Actor.init(
            .{ .name = "test" },
            try any(self.allocator, T, state),
            behavior,
        );
        try self.actors.put("test", actor);
        return .{ .name = "test" };
    }

    pub fn send(self: *System, from: ActorRef, to: ActorRef, comptime T: type, msg: T) !void {
        const m = try self.allocator.create(Message);
        m.from = from;
        m.to = to;
        m.msg = try any(
            self.allocator,
            T,
            msg,
        );
        try self.queue.insert(0, m);
    }

    pub fn stop(self: *System) void {
        self.running = false;
    }

    pub fn work(self: *System) !void {
        while (self.running) {
            if (self.queue.items.len == 0) {
                break;
            }
            if (self.queue.popOrNull()) |msg| {
                if (self.actors.getPtr(msg.from.name)) |actor| {
                    const behavior: Behavior = fromOpaque(actor.behavior);
                    try behavior(actor, self, &actor.state, msg.from, &msg.msg);
                    if (!msg.msg.read) {
                        msg.msg.debug(msg.msg.ptr);
                    }
                    msg.msg.deinit();
                }
            }
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
