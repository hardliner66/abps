//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at http://mozilla.org/MPL/2.0/.

const std = @import("std");
const ztracy = @import("ztracy");

pub fn print(comptime format: []const u8, args: anytype) void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    stdout.print(format, args) catch {};

    bw.flush() catch {};
}

pub fn println(comptime format: []const u8, args: anytype) void {
    print(format ++ "\n", args);
}

pub fn eprint(comptime format: []const u8, args: anytype) void {
    const stdout_file = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    stdout.print(format, args) catch {};

    bw.flush() catch {};
}

pub fn eprintln(comptime format: []const u8, args: anytype) void {
    eprint(format ++ "\n", args);
}
