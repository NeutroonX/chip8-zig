const sdl = @cImport(@cInclude("SDL2/SDL.h"));
const std = @import("std");

const SAMPLE_RATE = 44100;
const AMPLITUDE = 3000;
const FREQ = 440;

var beeping: bool = false;
var phase: f32 = 0.0;
var dev_id: sdl.SDL_AudioDeviceID = 0;

pub const Audio = struct {
    pub fn init() !Audio {
        const spec = sdl.SDL_AudioSpec{
            .freq = SAMPLE_RATE,
            .format = sdl.AUDIO_S16SYS,
            .channels = 1,
            .samples = 512,
            .callback = audioCallback,
            .userdata = null,
            .silence = 0,
            .size = 0,
            .padding = 0,
        };
        dev_id = sdl.SDL_OpenAudioDevice(null, 0, &spec, null, 0);
        if (dev_id == 0) return error.AudioInit;
        sdl.SDL_PauseAudioDevice(dev_id, 0);
        return .{};
    }

    pub fn deinit(_: *Audio) void {
        if (dev_id != 0) sdl.SDL_CloseAudioDevice(dev_id);
    }

    pub fn setBeeping(_: *Audio, on: bool) void {
        beeping = on;
    }
};

fn audioCallback(_: ?*anyopaque, stream: [*c]u8, len: c_int) callconv(.c) void {
    const buf: [*]i16 = @alignCast(@ptrCast(stream));
    const n: usize = @intCast(@divTrunc(len, 2));
    const step: f32 = FREQ / SAMPLE_RATE;
    for (0..n) |i| {
        if (beeping) {
            buf[i] = if (phase < 0.5) AMPLITUDE else -AMPLITUDE;
            phase += step;
            if (phase >= 1.0) phase -= 1.0;
        } else {
            buf[i] = 0;
        }
    }
}
