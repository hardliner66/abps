const std = @import("std");
const builtin = @import("builtin");
const ztracy = @import("ztracy");

pub const AnyPointer = SafePointer;

/// A type-erased pointer. Will perform safety checks in safe modes, otherwise will invoke undefined behaviour.
// pub const AnyPointer = if (std.debug.runtime_safety)
// SafePointer
// else
//     UnsafePointer;

/// A type-checking type-erased pointer. Can contain *any* pointer and can be converted back to the original one.
pub const SafePointer = struct {
    /// Pointer to a invalid value.
    pub const null_pointer = SafePointer{ .address = 0, .type_id = @as(TypeId, @enumFromInt(0)) };

    address: usize,
    type_id: TypeId,

    /// Creates a new type-erased pointer.
    pub fn make(comptime T: type, ptr: T) SafePointer {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        assertPointer(T);
        return SafePointer{
            .address = @intFromPtr(ptr),
            .type_id = typeId(T),
        };
    }

    /// Casts the type-erased pointer to the pointer type `T`. Will perform a safety check and panic, if the pointer isn't of type `T`.
    /// Returns `T`.
    pub fn cast(self: SafePointer, comptime T: type) T {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        assertPointer(T);
        if (typeId(T) != self.type_id) {
            std.debug.panic("Type mismatch: Expected {s}, but got {s}!", .{ @typeName(T), self.type_id.name() });
        }
        return @as(T, @ptrFromInt(self.address));
    }

    /// Will try to cast the type-erased pointer to `T`. Does return `null` if the types don't match, otherwise will
    /// return the pointer as `T`.
    pub fn tryCast(self: SafePointer, comptime T: type) ?T {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        assertPointer(T);
        if (self.isNull())
            return null;
        return if (typeId(T) == self.type_id)
            @as(T, @ptrFromInt(self.address))
        else
            null;
    }

    /// Returns true if the pointer is a null pointer
    pub fn isNull(self: SafePointer) bool {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        return self.address == 0;
    }

    /// Returns true if the address of both pointers is the same.
    pub fn eql(self: SafePointer, other: SafePointer) bool {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        return self.address == other.address;
    }
};

const TypeId = enum(usize) {
    _,

    pub fn name(self: TypeId) []const u8 {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        return std.mem.sliceTo(@as([*:0]const u8, @ptrFromInt(@intFromEnum(self))), 0);
    }
};

fn assertPointer(comptime T: type) void {
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    comptime var ti: std.builtin.Type = @typeInfo(T);
    if (ti == .Optional) {
        ti = @typeInfo(ti.Optional.child);
    }
    if (ti != .Pointer)
        @compileError("any-pointer only works with (optional) pointers to one or many.");
    switch (ti.Pointer.size) {
        .One, .Many, .C => {},
        else => @compileError("any-pointer only works with (optional) pointers to one or many."),
    }
}

fn typeId(comptime T: type) TypeId {
    const Tag =
        struct {
        const str = @typeName(T);
        var name: [str.len:0]u8 = str.*;
    };
    return @as(TypeId, @enumFromInt(@intFromPtr(&Tag.name)));
}

test "basic pointer" {
    var i: u32 = 0;

    const erased = AnyPointer.make(*u32, &i);

    const ptr = erased.cast(*u32);

    try std.testing.expectEqual(@as(*u32, &i), ptr);

    ptr.* = 42;

    std.debug.assert(i == 42);
}
