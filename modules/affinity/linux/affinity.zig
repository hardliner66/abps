const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;
const pid_t = linux.pid_t;
const cpu_set_t = linux.cpu_set_t;
const cpu_count_t = linux.cpu_count_t;
const CPU_SETSIZE = linux.CPU_SETSIZE;
const syscall3 = linux.syscall3;
const sched_getaffinity = posix.sched_getaffinity;
const errno = posix.errno;
const unexpectedErrno = posix.unexpectedErrno;

const helper = @import("helper");
const print = helper.print;
const eprint = helper.eprint;

/// Clear all CPUs from the CPU set, initializing the mask.
pub fn CPU_ZERO(set: *cpu_set_t) void {
    for (set, 0..) |_, i| {
        set[i] = 0;
    }
}

/// Add a CPU to the CPU set by setting the corresponding bit.
pub fn CPU_SET(cpu: usize, set: *cpu_set_t) void {
    const index = cpu / @sizeOf(usize) * 8; // Calculate index in the array
    const bit = cpu % (@sizeOf(usize) * 8); // Calculate bit within the usize
    set[index] |= @as(u32, @intCast(1)) << @intCast(bit);
}

pub fn sched_setaffinity(pid: pid_t, set: *const cpu_set_t) !void {
    const size = @sizeOf(cpu_set_t);
    const rc = syscall3(.sched_setaffinity, @as(usize, @bitCast(@as(isize, pid))), size, @intFromPtr(set));

    switch (errno(rc)) {
        .SUCCESS => return,
        else => |err| return unexpectedErrno(err),
    }
}

pub fn setThreadAffinity(cpu: usize) !void {
    var cpuset: std.os.linux.cpu_set_t = .{0} ** 16;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu, &cpuset);
    try sched_setaffinity(0, &cpuset);
}

pub fn setAffinity(core: usize) !void {
    try setThreadAffinity(core);
}

pub fn printAffinity() !void {
    const cpuset = try sched_getaffinity(@intCast(std.Thread.getCurrentId()));
    print("{any}\n", .{cpuset});
}
