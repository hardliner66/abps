const std = @import("std");

const helper = @import("helper");
const print = helper.print;
const eprint = helper.eprint;

pub fn setAffinity(core: usize) !void {
    _ = core;
}
