pub const FakeTracyZone = struct {
    pub fn End(_: @This()) void {}
};
pub fn Zone(_: anytype) FakeTracyZone {
    return .{};
}
