const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const lfq = @import("lfqueue.zig");

pub const LfQueue = lfq.LfQueue;
