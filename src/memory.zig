const std = @import("std");

pub const RAM_SIZE = 4096;
pub const FONT_START: u16 = 0x050;
pub const PROG_START: u16 = 0x200;

const font_sprites = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

pub const Memory = struct {
    ram: [RAM_SIZE]u8,

    pub fn init() Memory {
        var m = Memory{ .ram = [_]u8{0} ** RAM_SIZE };
        @memcpy(m.ram[FONT_START .. FONT_START + font_sprites.len], &font_sprites);
        return m;
    }

    pub fn load(self: *Memory, rom: []const u8) error{RomTooLarge}!void {
        if (rom.len > RAM_SIZE - PROG_START) return error.RomTooLarge;
        @memcpy(self.ram[PROG_START .. PROG_START + rom.len], rom);
    }

    pub fn read(self: *const Memory, addr: u16) u8 {
        return self.ram[addr & 0x0FFF];
    }

    pub fn write(self: *Memory, addr: u16, val: u8) void {
        self.ram[addr & 0x0FFF] = val;
    }

    pub fn fontAddr(digit: u8) u16 {
        return FONT_START + @as(u16, digit & 0xF) * 5;
    }
};

test "font loaded" {
    const m = Memory.init();
    try std.testing.expectEqual(@as(u8, 0xF0), m.ram[FONT_START]);
}

test "rom load" {
    var m = Memory.init();
    const rom = [_]u8{ 0x00, 0xE0, 0x12, 0x00 };
    try m.load(&rom);
    try std.testing.expectEqual(@as(u8, 0x00), m.ram[PROG_START]);
    try std.testing.expectEqual(@as(u8, 0xE0), m.ram[PROG_START + 1]);
}

test "rom too large" {
    var m = Memory.init();
    const big_rom = [_]u8{0} ** (RAM_SIZE - PROG_START + 1);
    try std.testing.expectError(error.RomTooLarge, m.load(&big_rom));
}
