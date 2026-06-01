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
    rng: std.Random.DefaultPrng = undefined,
    /// Non-null while waiting for 0xFX0A (LD Vx, K). Holds destination register index.
    waiting_for_key: ?u8 = null,

    pub fn init() Cpu {
        var cpu = Cpu{};
        cpu.rng = std.Random.DefaultPrng.init(0xDEADBEEF);
        return cpu;
    }

    pub fn initSeeded(seed: u64) Cpu {
        var cpu = Cpu{};
        cpu.rng = std.Random.DefaultPrng.init(seed);
        return cpu;
    }

    pub fn fetch(self: *Cpu, mem: *const Memory) u16 {
        const hi: u16 = mem.read(self.pc);
        const lo: u16 = mem.read(self.pc + 1);
        self.pc += 2;
        return (hi << 8) | lo;
    }

    pub fn tick(self: *Cpu, mem: *Memory, display: *Display, input: *Input) CpuError!void {
        // Don't execute while blocked on a key — main loop must call resolveKey first.
        if (self.waiting_for_key != null) return;
        const op = self.fetch(mem);
        try self.execute(op, mem, display, input);
    }

    /// Called by the main loop when a key is pressed. Unblocks 0xFX0A.
    pub fn resolveKey(self: *Cpu, key: u4) void {
        if (self.waiting_for_key) |reg| {
            self.v[reg] = @intCast(key);
            self.waiting_for_key = null;
        }
    }

    /// Reset CPU to initial state, keeping the loaded ROM in memory.
    pub fn reset(self: *Cpu) void {
        self.v = [_]u8{0} ** 16;
        self.i = 0;
        self.pc = 0x200;
        self.sp = 0;
        self.stack = [_]u16{0} ** 16;
        self.delay = 0;
        self.sound = 0;
        self.waiting_for_key = null;
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
            0xC000 => self.v[x] = self.rng.random().int(u8) & kk,
            0xD000 => {
                const sprite = mem.ram[self.i .. self.i + n];
                self.v[0xF] = if (display.draw(self.v[x], self.v[y], sprite)) 1 else 0;
            },
            0xE000 => switch (kk) {
                0x9E => if (input.isPressed(@truncate(self.v[x] & 0xF))) {
                    self.pc += 2;
                },
                0xA1 => if (!input.isPressed(@truncate(self.v[x] & 0xF))) {
                    self.pc += 2;
                },
                else => return CpuError.UnknownOpcode,
            },
            0xF000 => try self.executeF(kk, x, mem, input),
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

    fn executeF(self: *Cpu, kk: u8, x: u8, mem: *Memory, _input: *Input) CpuError!void {
        _ = _input;
        switch (kk) {
            0x07 => self.v[x] = self.delay,
            0x0A => {
                self.pc -= 2; // re-point to this instruction until a key arrives
                self.waiting_for_key = x;
            },
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

// Helper: run one opcode encoded directly in memory
fn runOp(cpu: *Cpu, mem: *Memory, disp: *Display, inp: *Input, hi: u8, lo: u8) !void {
    mem.ram[cpu.pc] = hi;
    mem.ram[cpu.pc + 1] = lo;
    try cpu.tick(mem, disp, inp);
}

test "0x00E0 clear display" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    disp.framebuffer[0] = true;
    try runOp(&cpu, &mem, &disp, &inp, 0x00, 0xE0);
    try std.testing.expectEqual(false, disp.framebuffer[0]);
}

test "0x1NNN jump" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    try runOp(&cpu, &mem, &disp, &inp, 0x12, 0x34);
    try std.testing.expectEqual(@as(u16, 0x234), cpu.pc);
}

test "0x2/0xEE call and return" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    // CALL 0x300
    try runOp(&cpu, &mem, &disp, &inp, 0x23, 0x00);
    try std.testing.expectEqual(@as(u16, 0x300), cpu.pc);
    try std.testing.expectEqual(@as(u8, 1), cpu.sp);
    // Place RET at 0x300
    try runOp(&cpu, &mem, &disp, &inp, 0x00, 0xEE);
    try std.testing.expectEqual(@as(u16, 0x202), cpu.pc);
    try std.testing.expectEqual(@as(u8, 0), cpu.sp);
}

test "0x6XKK LD Vx" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    try runOp(&cpu, &mem, &disp, &inp, 0x60, 0xAB);
    try std.testing.expectEqual(@as(u8, 0xAB), cpu.v[0]);
}

test "0x7XKK ADD Vx, byte" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    cpu.v[1] = 0x10;
    try runOp(&cpu, &mem, &disp, &inp, 0x71, 0x05);
    try std.testing.expectEqual(@as(u8, 0x15), cpu.v[1]);
}

test "0x8XY4 ADD with carry" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    cpu.v[0] = 0xFF;
    cpu.v[1] = 0x01;
    try runOp(&cpu, &mem, &disp, &inp, 0x80, 0x14);
    try std.testing.expectEqual(@as(u8, 0x00), cpu.v[0]);
    try std.testing.expectEqual(@as(u8, 1), cpu.v[0xF]); // carry
}

test "0x8XY5 SUB with borrow" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    cpu.v[0] = 0x05;
    cpu.v[1] = 0x03;
    try runOp(&cpu, &mem, &disp, &inp, 0x80, 0x15);
    try std.testing.expectEqual(@as(u8, 0x02), cpu.v[0]);
    try std.testing.expectEqual(@as(u8, 1), cpu.v[0xF]); // no borrow
}

test "0xANNN LD I" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    try runOp(&cpu, &mem, &disp, &inp, 0xA1, 0x23);
    try std.testing.expectEqual(@as(u16, 0x123), cpu.i);
}

test "0xDXYN draw sprite with collision" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    // place 1-byte sprite at 0x300
    mem.ram[0x300] = 0x80; // leftmost pixel only
    cpu.i = 0x300;
    cpu.v[0] = 0;
    cpu.v[1] = 0;
    // draw once - no collision
    try runOp(&cpu, &mem, &disp, &inp, 0xD0, 0x11);
    try std.testing.expectEqual(@as(u8, 0), cpu.v[0xF]);
    // draw again - collision
    try runOp(&cpu, &mem, &disp, &inp, 0xD0, 0x11);
    try std.testing.expectEqual(@as(u8, 1), cpu.v[0xF]);
}

test "0xFX33 BCD" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    cpu.v[0] = 123;
    cpu.i = 0x300;
    try runOp(&cpu, &mem, &disp, &inp, 0xF0, 0x33);
    try std.testing.expectEqual(@as(u8, 1), mem.ram[0x300]);
    try std.testing.expectEqual(@as(u8, 2), mem.ram[0x301]);
    try std.testing.expectEqual(@as(u8, 3), mem.ram[0x302]);
}

test "0xFX55/0xFX65 store and load registers" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();
    cpu.v[0] = 0xAA;
    cpu.v[1] = 0xBB;
    cpu.v[2] = 0xCC;
    cpu.i = 0x300;
    try runOp(&cpu, &mem, &disp, &inp, 0xF2, 0x55); // store V0..V2
    cpu.v[0] = 0;
    cpu.v[1] = 0;
    cpu.v[2] = 0;
    cpu.i = 0x300;
    try runOp(&cpu, &mem, &disp, &inp, 0xF2, 0x65); // load V0..V2
    try std.testing.expectEqual(@as(u8, 0xAA), cpu.v[0]);
    try std.testing.expectEqual(@as(u8, 0xBB), cpu.v[1]);
    try std.testing.expectEqual(@as(u8, 0xCC), cpu.v[2]);
}

test "0xFX0A waitForKey — blocks until resolveKey called" {
    var cpu = Cpu.init();
    var mem = Memory.init();
    var disp = Display.init();
    var inp = Input.init();

    // Encode LD V3, K at 0x200
    mem.ram[0x200] = 0xF3;
    mem.ram[0x201] = 0x0A;

    // First tick: CPU sets waiting_for_key and rewinds PC, doesn't advance
    try cpu.tick(&mem, &disp, &inp);
    try std.testing.expectEqual(@as(?u8, 3), cpu.waiting_for_key);
    try std.testing.expectEqual(@as(u16, 0x200), cpu.pc); // rewound

    // Second tick while still waiting: no-op
    try cpu.tick(&mem, &disp, &inp);
    try std.testing.expectEqual(@as(u16, 0x200), cpu.pc);

    // Key arrives: resolveKey unblocks
    cpu.resolveKey(0x7);
    try std.testing.expectEqual(@as(?u8, null), cpu.waiting_for_key);
    try std.testing.expectEqual(@as(u8, 0x7), cpu.v[3]);

    // Next tick executes normally (past the LD Vx,K instruction)
    mem.ram[0x200] = 0x00; // NOP (SYS — ignored)
    mem.ram[0x201] = 0x00;
    try cpu.tick(&mem, &disp, &inp);
    try std.testing.expectEqual(@as(u16, 0x202), cpu.pc);
}
