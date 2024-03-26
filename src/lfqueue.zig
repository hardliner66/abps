const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const cq = @cImport({
    @cInclude("c_api/concurrentqueue.h");
});

pub fn LfQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        lfq: *void,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            var lfq: *void = undefined;
            _ = cq.moodycamel_cq_create(@ptrCast(&lfq));
            return .{
                .lfq = lfq,
                .allocator = allocator,
            };
        }

        pub fn push(self: Self, value: T) !void {
            const v = try self.allocator.create(T);
            v.* = value;
            _ = cq.moodycamel_cq_enqueue(self.lfq, @ptrCast(v));
        }

        pub fn pop(self: Self) ?T {
            var v: *T = undefined;
            if (cq.moodycamel_cq_try_dequeue(self.lfq, @ptrCast(&v)) != 0) {
                const result = v.*;
                self.allocator.destroy(v);
                return result;
            }
            return null;
        }

        pub fn deinit(self: Self) void {
            _ = cq.moodycamel_cq_destroy(@ptrCast(self.lfq));
        }
    };
}
