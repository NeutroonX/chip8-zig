pub const Input = struct {
    keys: [16]bool = [_]bool{false} ** 16,
    // Set by the main loop before each frame to signal LD Vx, K completion
    last_key: ?u4 = null,

    pub fn init() Input {
        return .{};
    }

    pub fn isPressed(self: *const Input, key: u4) bool {
        return self.keys[key];
    }

    /// Blocking wait — returns the next key pressed.
    /// In practice the main loop sets last_key and this polls it.
    pub fn waitForKey(self: *Input) u8 {
        // Spin until the main loop delivers a key via last_key.
        while (self.last_key == null) {
            // The SDL main loop must drive this by setting last_key.
            // In headless/test mode this would hang; tests should not call this.
        }
        const k = self.last_key.?;
        self.last_key = null;
        return @intCast(k);
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
