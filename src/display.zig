pub const WIDTH = 64;
pub const HEIGHT = 32;
pub const SCALE = 10;

pub const Display = struct {
    framebuffer: [WIDTH * HEIGHT]bool = [_]bool{false} ** (WIDTH * HEIGHT),
    dirty: bool = false,

    pub fn init() Display {
        return .{};
    }

    pub fn clear(self: *Display) void {
        @memset(&self.framebuffer, false);
        self.dirty = true;
    }

    /// XOR sprite onto framebuffer. Returns true if any pixel was erased (collision).
    pub fn draw(self: *Display, px: u8, py: u8, sprite: []const u8) bool {
        var collision = false;
        for (sprite, 0..) |row, dy| {
            var bit: u3 = 7;
            while (true) {
                const dx: u8 = 7 - bit;
                if ((row >> bit) & 1 == 1) {
                    const sx = (px + dx) % WIDTH;
                    const sy = (@as(usize, py) + dy) % HEIGHT;
                    const idx = sy * WIDTH + sx;
                    if (self.framebuffer[idx]) collision = true;
                    self.framebuffer[idx] = !self.framebuffer[idx];
                }
                if (bit == 0) break;
                bit -= 1;
            }
        }
        self.dirty = true;
        return collision;
    }

    pub fn getPixel(self: *const Display, x: usize, y: usize) bool {
        return self.framebuffer[y * WIDTH + x];
    }
};

const std = @import("std");

test "clear display" {
    var d = Display.init();
    d.framebuffer[0] = true;
    d.clear();
    try std.testing.expectEqual(false, d.framebuffer[0]);
}

test "draw sprite no collision" {
    var d = Display.init();
    const sprite = [_]u8{0xFF}; // full row of 8 pixels
    const hit = d.draw(0, 0, &sprite);
    try std.testing.expectEqual(false, hit);
    try std.testing.expectEqual(true, d.framebuffer[0]);
}

test "draw sprite collision" {
    var d = Display.init();
    const sprite = [_]u8{0x80}; // single leftmost pixel
    _ = d.draw(0, 0, &sprite);
    const hit = d.draw(0, 0, &sprite); // draw same pixel again → collision
    try std.testing.expectEqual(true, hit);
    try std.testing.expectEqual(false, d.framebuffer[0]); // XOR'd back to off
}
