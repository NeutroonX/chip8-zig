const std = @import("std");
const Memory = @import("memory.zig").Memory;
const Display = @import("display.zig").Display;
const Input = @import("input.zig").Input;

pub const CpuError = error{
    UnknownOpcode,
    StackOverflow,
    StackUnderflow,
};

pub const Cpu = struct {
    v: [16]u8 = [_]u8{0} ** 16,
    i: u16 = 0,
    pc: u16 = 0x200,
    sp: u8 = 0,
    stack: [16]u16 = [_]u16{0} ** 16,
    delay: u8 = 0,
    sound: u8 = 0,

    pub fn init() Cpu {
        return .{};
    }

    pub fn fetch(self: *Cpu, mem: *const Memory) u16 {
        const hi: u16 = mem.read(self.pc);
        const lo: u16 = mem.read(self.pc + 1);
        self.pc += 2;
        return (hi << 8) | lo;
    }

    pub fn tick(self: *Cpu, mem: *Memory, display: *Display, input: *Input) CpuError!void {
        const op = self.fetch(mem);
        try self.execute(op, mem, display, input);
    }

    pub fn tickTimers(self: *Cpu) void {
        if (self.delay > 0) self.delay -= 1;
        if (self.sound > 0) self.sound -= 1;
    }

    fn execute(self: *Cpu, op: u16, mem: *Memory, display: *Display, input: *Input) CpuError!void {
        const nnn: u16 = op & 0x0FFF;
        const n: u8 = @intCast(op & 0x000F);
        const x: u8 = @intCast((op >> 8) & 0xF);
        const y: u8 = @intCast((op >> 4) & 0xF);
        const kk: u8 = @intCast(op & 0x00FF);

        switch (op & 0xF000) {
            0x0000 => switch (op) {
                0x00E0 => display.clear(),
                0x00EE => {
                    if (self.sp == 0) return CpuError.StackUnderflow;
                    self.sp -= 1;
                    self.pc = self.stack[self.sp];
                },
                else => {}, // SYS addr — ignored on modern interpreters
            },
            0x1000 => self.pc = nnn,
            0x2000 => {
                if (self.sp >= 16) return CpuError.StackOverflow;
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = nnn;
            },
            0x3000 => if (self.v[x] == kk) {
                self.pc += 2;
            },
            0x4000 => if (self.v[x] != kk) {
                self.pc += 2;
            },
            0x5000 => if (self.v[x] == self.v[y]) {
                self.pc += 2;
            },
            0x6000 => self.v[x] = kk,
            0x7000 => self.v[x] = self.v[x] +% kk,
            0x8000 => try self.executeArith(op & 0xF, x, y),
            0x9000 => if (self.v[x] != self.v[y]) {
                self.pc += 2;
            },
            0xA000 => self.i = nnn,
            0xB000 => self.pc = nnn + self.v[0],
            0xC000 => self.v[x] = std.crypto.random.int(u8) & kk,
            0xD000 => {
                const sprite = mem.ram[self.i .. self.i + n];
                self.v[0xF] = if (display.draw(self.v[x], self.v[y], sprite)) 1 else 0;
            },
            0xE000 => switch (kk) {
                0x9E => if (input.isPressed(self.v[x] & 0xF)) {
                    self.pc += 2;
                },
                0xA1 => if (!input.isPressed(self.v[x] & 0xF)) {
                    self.pc += 2;
                },
                else => return CpuError.UnknownOpcode,
            },
            0xF000 => try self.executeF(kk, x, n, mem, input),
            else => return CpuError.UnknownOpcode,
        }
    }

    fn executeArith(self: *Cpu, kind: u16, x: u8, y: u8) CpuError!void {
        switch (kind) {
            0x0 => self.v[x] = self.v[y],
            0x1 => self.v[x] |= self.v[y],
            0x2 => self.v[x] &= self.v[y],
            0x3 => self.v[x] ^= self.v[y],
            0x4 => {
                const res: u16 = @as(u16, self.v[x]) + self.v[y];
                self.v[0xF] = if (res > 0xFF) 1 else 0;
                self.v[x] = @truncate(res);
            },
            0x5 => {
                self.v[0xF] = if (self.v[x] >= self.v[y]) 1 else 0;
                self.v[x] = self.v[x] -% self.v[y];
            },
            0x6 => {
                self.v[0xF] = self.v[x] & 0x1;
                self.v[x] >>= 1;
            },
            0x7 => {
                self.v[0xF] = if (self.v[y] >= self.v[x]) 1 else 0;
                self.v[x] = self.v[y] -% self.v[x];
            },
            0xE => {
                self.v[0xF] = (self.v[x] >> 7) & 0x1;
                self.v[x] <<= 1;
            },
            else => return CpuError.UnknownOpcode,
        }
    }

    fn executeF(self: *Cpu, kk: u8, x: u8, _n: u8, mem: *Memory, input: *Input) CpuError!void {
        _ = _n;
        switch (kk) {
            0x07 => self.v[x] = self.delay,
            0x0A => self.v[x] = input.waitForKey(),
            0x15 => self.delay = self.v[x],
            0x18 => self.sound = self.v[x],
            0x1E => self.i +%= self.v[x],
            0x29 => self.i = @import("memory.zig").Memory.fontAddr(self.v[x]),
            0x33 => {
                mem.write(self.i, self.v[x] / 100);
                mem.write(self.i + 1, (self.v[x] / 10) % 10);
                mem.write(self.i + 2, self.v[x] % 10);
            },
            0x55 => {
                var j: u8 = 0;
                while (j <= x) : (j += 1) {
                    mem.write(self.i + j, self.v[j]);
                }
            },
            0x65 => {
                var j: u8 = 0;
                while (j <= x) : (j += 1) {
                    self.v[j] = mem.read(self.i + j);
                }
            },
            else => return CpuError.UnknownOpcode,
        }
    }
};

test "cpu init" {
    const cpu = Cpu.init();
    try std.testing.expectEqual(@as(u16, 0x200), cpu.pc);
    try std.testing.expectEqual(@as(u8, 0), cpu.sp);
}

test "fetch advances pc" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    mem.ram[0x200] = 0x12;
    mem.ram[0x201] = 0x34;
    const op = cpu.fetch(&mem);
    try std.testing.expectEqual(@as(u16, 0x1234), op);
    try std.testing.expectEqual(@as(u16, 0x202), cpu.pc);
}

test "timers decrement" {
    var cpu = Cpu.init();
    cpu.delay = 5;
    cpu.sound = 3;
    cpu.tickTimers();
    try std.testing.expectEqual(@as(u8, 4), cpu.delay);
    try std.testing.expectEqual(@as(u8, 2), cpu.sound);
}

test "timers stop at zero" {
    var cpu = Cpu.init();
    cpu.delay = 0;
    cpu.tickTimers();
    try std.testing.expectEqual(@as(u8, 0), cpu.delay);
}
