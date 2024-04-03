const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ztracy = @import("ztracy");

const lfq = @import("lfqueue.zig");

pub const LfQueue = lfq.LfQueue;

pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();
        items: std.PriorityQueue(T, void, eq),
        lock: std.Thread.Mutex,

        fn eq(context: void, a: T, b: T) std.math.Order {
            _ = context;
            _ = a;
            _ = b;
            return .eq;
        }

        pub fn init(allocator: Allocator) Self {
            const tracy_zone = ztracy.Zone(@src());
            defer tracy_zone.End();
            return .{
                .items = std.PriorityQueue(T, void, eq).init(allocator, void{}),
                .lock = std.Thread.Mutex{},
            };
        }

        pub fn push(self: *Self, value: T) !void {
            const tracy_zone = ztracy.Zone(@src());
            defer tracy_zone.End();
            self.lock.lock();
            defer self.lock.unlock();
            return self.items.add(value);
        }

        pub fn pop(self: *Self) ?T {
            const tracy_zone = ztracy.Zone(@src());
            defer tracy_zone.End();
            if (self.lock.tryLock()) {
                defer self.lock.unlock();
                return self.items.removeOrNull();
            }
            return null;
        }

        pub fn deinit(self: *Self) void {
            const tracy_zone = ztracy.Zone(@src());
            defer tracy_zone.End();
            self.items.deinit();
        }
    };
}
