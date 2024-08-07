//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at http://mozilla.org/MPL/2.0/.

const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Allocator = mem.Allocator;
const ztracy = @import("ztracy");

const lfq = if (builtin.target.cpu.arch != .arm) @import("lfqueue.zig") else struct {
    pub const LfQueue = LQueue;
};

pub const LfQueue = lfq.LfQueue;

pub fn LQueue(comptime T: type) type {
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
            return .{
                .items = std.PriorityQueue(T, void, eq).init(allocator, void{}),
                .lock = std.Thread.Mutex{},
            };
        }

        pub fn push(self: *Self, value: T) !void {
            self.lock.lock();
            defer self.lock.unlock();
            return self.items.add(value);
        }

        pub fn pop(self: *Self) ?T {
            if (self.lock.tryLock()) {
                defer self.lock.unlock();
                return self.items.removeOrNull();
            }
            return null;
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }
    };
}

pub fn Queue(comptime T: type) type {
    return union(enum) {
        const Self = @This();
        l_queue: LQueue(T),
        lf_queue: LfQueue(T),

        pub fn init(allocator: Allocator, locked: bool) Self {
            const tracy_zone = ztracy.Zone(@src());
            defer tracy_zone.End();
            if (locked) {
                return .{
                    .l_queue = LQueue(T).init(allocator),
                };
            } else {
                return .{
                    .lf_queue = LfQueue(T).init(allocator),
                };
            }
        }

        pub fn push(self: *Self, value: T) !void {
            const tracy_zone = ztracy.Zone(@src());
            defer tracy_zone.End();
            switch (self.*) {
                Self.l_queue => |*q| return q.push(value),
                Self.lf_queue => |*q| return q.push(value),
            }
        }

        pub fn pop(self: *Self) ?T {
            const tracy_zone = ztracy.Zone(@src());
            defer tracy_zone.End();
            switch (self.*) {
                Self.l_queue => |*q| return q.pop(),
                Self.lf_queue => |*q| return q.pop(),
            }
        }

        pub fn deinit(self: *Self) void {
            const tracy_zone = ztracy.Zone(@src());
            defer tracy_zone.End();
            switch (self.*) {
                Self.l_queue => |*q| return q.deinit(),
                Self.lf_queue => |*q| return q.deinit(),
            }
        }
    };
}
