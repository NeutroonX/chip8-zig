pub const Input = struct {
    keys: [16]bool = [_]bool{false} ** 16,
    last_key: ?u4 = null,

    pub fn init() Input {
        return .{};
    }

    pub fn isPressed(self: *const Input, key: u4) bool {
        return self.keys[key];
    }

    pub fn setKey(self: *Input, key: u4, pressed: bool) void {
        self.keys[key] = pressed;
        if (pressed) self.last_key = key;
    }
};

const std = @import("std");

test "set and check key" {
    var inp = Input.init();
    inp.setKey(0xA, true);
    try std.testing.expectEqual(true, inp.isPressed(0xA));
    inp.setKey(0xA, false);
    try std.testing.expectEqual(false, inp.isPressed(0xA));
}

test "last_key tracks most recent press" {
    var inp = Input.init();
    inp.setKey(0x3, true);
    try std.testing.expectEqual(@as(?u4, 0x3), inp.last_key);
    inp.setKey(0x3, false);
    try std.testing.expectEqual(@as(?u4, 0x3), inp.last_key); // not cleared on release
}
