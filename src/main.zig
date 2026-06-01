const std = @import("std");
const sdl = @cImport(@cInclude("SDL2/SDL.h"));

const Memory = @import("memory.zig").Memory;
const Cpu = @import("cpu.zig").Cpu;
const display_mod = @import("display.zig");
const Display = display_mod.Display;
const Input = @import("input.zig").Input;
const Audio = @import("audio.zig").Audio;

const WINDOW_W = display_mod.WIDTH * display_mod.SCALE;
const WINDOW_H = display_mod.HEIGHT * display_mod.SCALE;

// SDL scancode → CHIP-8 hex key
// Keyboard layout:
//   1 2 3 4  →  1 2 3 C
//   Q W E R  →  4 5 6 D
//   A S D F  →  7 8 9 E
//   Z X C V  →  A 0 B F
const key_map = blk: {
    var m = [_]?u4{null} ** 256;
    m[sdl.SDL_SCANCODE_1] = 0x1;
    m[sdl.SDL_SCANCODE_2] = 0x2;
    m[sdl.SDL_SCANCODE_3] = 0x3;
    m[sdl.SDL_SCANCODE_4] = 0xC;
    m[sdl.SDL_SCANCODE_Q] = 0x4;
    m[sdl.SDL_SCANCODE_W] = 0x5;
    m[sdl.SDL_SCANCODE_E] = 0x6;
    m[sdl.SDL_SCANCODE_R] = 0xD;
    m[sdl.SDL_SCANCODE_A] = 0x7;
    m[sdl.SDL_SCANCODE_S] = 0x8;
    m[sdl.SDL_SCANCODE_D] = 0x9;
    m[sdl.SDL_SCANCODE_F] = 0xE;
    m[sdl.SDL_SCANCODE_Z] = 0xA;
    m[sdl.SDL_SCANCODE_X] = 0x0;
    m[sdl.SDL_SCANCODE_C] = 0xB;
    m[sdl.SDL_SCANCODE_V] = 0xF;
    break :blk m;
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

    if (args.len < 2) {
        std.debug.print("Usage: chip8_zig <rom.ch8>\n", .{});
        return;
    }

    const rom_data = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        init.gpa,
        std.Io.Limit.limited(3584),
    ) catch |err| {
        std.debug.print("Failed to read ROM '{s}': {}\n", .{ args[1], err });
        return;
    };
    defer init.gpa.free(rom_data);

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_AUDIO) != 0) {
        std.debug.print("SDL_Init failed: {s}\n", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow(
        "CHIP-8",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        WINDOW_W,
        WINDOW_H,
        0,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{sdl.SDL_GetError()});
        return;
    };
    defer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(
        window,
        -1,
        sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC,
    ) orelse {
        std.debug.print("SDL_CreateRenderer failed: {s}\n", .{sdl.SDL_GetError()});
        return;
    };
    defer sdl.SDL_DestroyRenderer(renderer);

    var audio_opt: ?Audio = Audio.init() catch |err| blk: {
        std.debug.print("Audio unavailable ({}), continuing without sound.\n", .{err});
        break :blk null;
    };
    defer if (audio_opt) |*a| a.deinit();

    var mem = Memory.init();
    try mem.load(rom_data);

    var cpu = Cpu.initSeeded(sdl.SDL_GetTicks64());
    var display = Display.init();
    var input = Input.init();

    const CYCLES_PER_FRAME = 10; // ~600Hz at 60fps
    const MS_PER_FRAME: u32 = 16; // ~60Hz

    var running = true;
    while (running) {
        const frame_start = sdl.SDL_GetTicks64();

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => running = false,
                sdl.SDL_KEYDOWN => {
                    if (event.key.keysym.scancode == sdl.SDL_SCANCODE_ESCAPE) running = false;
                    const sc: usize = @intCast(event.key.keysym.scancode);
                    if (sc < key_map.len) {
                        if (key_map[sc]) |k| input.setKey(k, true);
                    }
                },
                sdl.SDL_KEYUP => {
                    const sc: usize = @intCast(event.key.keysym.scancode);
                    if (sc < key_map.len) {
                        if (key_map[sc]) |k| input.setKey(k, false);
                    }
                },
                else => {},
            }
        }

        for (0..CYCLES_PER_FRAME) |_| {
            cpu.tick(&mem, &display, &input) catch |err| {
                std.debug.print("CPU error: {}\n", .{err});
                running = false;
                break;
            };
        }

        cpu.tickTimers();

        if (audio_opt) |*a| a.setBeeping(cpu.sound > 0);

        if (display.dirty) {
            display.dirty = false;
            _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
            _ = sdl.SDL_RenderClear(renderer);
            _ = sdl.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
            for (0..display_mod.HEIGHT) |row| {
                for (0..display_mod.WIDTH) |col| {
                    if (display.getPixel(col, row)) {
                        const rect = sdl.SDL_Rect{
                            .x = @intCast(col * display_mod.SCALE),
                            .y = @intCast(row * display_mod.SCALE),
                            .w = display_mod.SCALE,
                            .h = display_mod.SCALE,
                        };
                        _ = sdl.SDL_RenderFillRect(renderer, &rect);
                    }
                }
            }
            sdl.SDL_RenderPresent(renderer);
        }

        const elapsed: u32 = @truncate(sdl.SDL_GetTicks64() - frame_start);
        if (elapsed < MS_PER_FRAME) sdl.SDL_Delay(MS_PER_FRAME - elapsed);
    }
}
