# CHIP-8 Emulator in Zig

A fully featured, cycle-accurate CHIP-8 emulator written in [Zig 0.16.0](https://ziglang.org/), with SDL2 rendering, audio buzzer, configurable emulation speed, and a clean modular architecture.

---

## Table of Contents

- [About CHIP-8](#about-chip-8)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Building](#building)
- [Running a ROM](#running-a-rom)
- [Controls](#controls)
- [Included ROMs](#included-roms)
- [Testing](#testing)
- [Project Structure](#project-structure)
- [CHIP-8 Specification](#chip-8-specification)
- [Opcode Coverage](#opcode-coverage)
- [Troubleshooting](#troubleshooting)

---

## About CHIP-8

CHIP-8 is an interpreted programming language developed in the mid-1970s by Joseph Weisbecker for the COSMAC VIP and Telmac 1800 microcomputers. It was designed to make game development easier on these 8-bit machines. Modern CHIP-8 emulators run programs written for this virtual machine, which includes classic games like Pong, Space Invaders, and Tetris.

This emulator faithfully implements the original CHIP-8 specification, including all 35 opcodes, a 64×32 monochrome display, a 16-key hexadecimal keypad, delay and sound timers, and a buzzer.

---

## Features

- **Full opcode coverage** — all 35 standard CHIP-8 opcodes implemented
- **SDL2 rendering** — 64×32 display scaled 10× to a 640×320 window
- **Audio buzzer** — SDL2 audio callback generates a 440 Hz square wave tied to the sound timer
- **60 Hz emulation loop** — timers decrement at the correct rate
- **Configurable CPU speed** — `--cycles N` flag to tune cycles per frame for ROM compatibility
- **Pause / Resume** — press `P` to freeze and unfreeze emulation mid-game
- **Reset** — press `F5` to reload and restart the ROM from scratch
- **Window title** — displays the loaded ROM filename
- **Non-blocking `LD Vx, K`** — key-wait opcode suspends the CPU without blocking the event loop
- **24 unit tests** — covering opcodes, memory, display, and input

---

## Architecture

```
src/
├── main.zig       — SDL2 event loop, CLI arg parsing, frame timing
├── cpu.zig        — Registers, fetch/decode/execute, all 35 opcodes, timers
├── memory.zig     — 4 KB RAM, font sprite table, ROM loader
├── display.zig    — 64×32 framebuffer, XOR sprite drawing, dirty flag
├── input.zig      — 16-key keypad state, SDL2 scancode mapping
├── audio.zig      — SDL2 audio device, 440 Hz square-wave buzzer
└── root.zig       — Library re-exports (Memory, Cpu, Display, Input)
```

Each module is independently testable. Only `main.zig` and `audio.zig` depend on SDL2 — the core emulator logic has zero external dependencies.

---

## Prerequisites

| Dependency | Version | Install |
|------------|---------|---------|
| [Zig](https://ziglang.org/download/) | 0.16.0 | See ziglang.org |
| [SDL2](https://www.libsdl.org/) | 2.x | See below |

### Installing SDL2

**Arch / CachyOS / Manjaro**
```sh
sudo pacman -S sdl2
```

**Ubuntu / Debian**
```sh
sudo apt install libsdl2-dev
```

**Fedora**
```sh
sudo dnf install SDL2-devel
```

**macOS (Homebrew)**
```sh
brew install sdl2
```

---

## Building

Clone the repository and build with the Zig build system:

```sh
git clone <https://github.com/NeutroonX/chip8-zig.git>
cd chip8-zig
zig build
```

The compiled binary lands at `zig-out/bin/chip8_zig`.

### Build Modes

```sh
zig build                        # Debug build (default)
zig build -Doptimize=ReleaseFast # Optimised release build
zig build -Doptimize=ReleaseSafe # Release with safety checks
zig build -Doptimize=ReleaseSmall # Smallest binary size
```

---

## Running a ROM

```sh
zig build run -- <path/to/rom.ch8>
```

### With Custom CPU Speed

Different ROMs were written expecting different interpreter speeds. The default is 10 cycles per frame (~600 Hz). Increase it if a ROM runs too slowly, decrease it if it runs too fast.

```sh
zig build run -- --cycles 10 roms/pong.ch8          # default speed
zig build run -- --cycles 15 roms/space-invaders.ch8 # slightly faster
zig build run -- --cycles 20 roms/tetris.ch8         # faster for some ROMs
```

### Running the Included ROMs

```sh
# Test suite — run these first to verify emulator correctness
zig build run -- roms/1-chip8-logo.ch8
zig build run -- roms/2-ibm-logo.ch8
zig build run -- roms/3-corax+.ch8
zig build run -- roms/4-flags.ch8

# Games
zig build run -- roms/pong.ch8
zig build run -- roms/tetris.ch8
zig build run -- roms/space-invaders.ch8
```

---

## Controls

### Emulator Controls

| Key | Action |
|-----|--------|
| `ESC` | Quit emulator |
| `P` | Pause / Unpause |
| `F5` | Reset (reload ROM from start) |

### CHIP-8 Keypad Mapping

The original CHIP-8 used a 16-key hexadecimal keypad (0–F). This emulator maps it to a standard QWERTY keyboard as follows:

```
CHIP-8 Keypad        Keyboard Mapping
┌───┬───┬───┬───┐    ┌───┬───┬───┬───┐
│ 1 │ 2 │ 3 │ C │    │ 1 │ 2 │ 3 │ 4 │
├───┼───┼───┼───┤    ├───┼───┼───┼───┤
│ 4 │ 5 │ 6 │ D │    │ Q │ W │ E │ R │
├───┼───┼───┼───┤    ├───┼───┼───┼───┤
│ 7 │ 8 │ 9 │ E │    │ A │ S │ D │ F │
├───┼───┼───┼───┤    ├───┼───┼───┼───┤
│ A │ 0 │ B │ F │    │ Z │ X │ C │ V │
└───┴───┴───┴───┘    └───┴───┴───┴───┘
```

---

## Included ROMs

### Test Suite (by [Timendus](https://github.com/Timendus/chip8-test-suite))

These ROMs are designed to test emulator correctness. Run them in order to diagnose issues.

| File | What it tests |
|------|--------------|
| `1-chip8-logo.ch8` | Basic display — shows the CHIP-8 logo |
| `2-ibm-logo.ch8` | Drawing opcodes — renders the IBM logo |
| `3-corax+.ch8` | Arithmetic opcodes — `ADD`, `SUB`, `AND`, `OR`, `XOR`, shifts |
| `4-flags.ch8` | VF flag correctness — carry, borrow, collision |
| `5-quirks.ch8` | Interpreter quirks (shift, memory, display) |

### Games

| File | Description | Speed hint |
|------|-------------|------------|
| `pong.ch8` | Classic Pong — 1 player vs CPU | `--cycles 10` |
| `tetris.ch8` | Falling block puzzle game | `--cycles 10` |
| `space-invaders.ch8` | Classic Space Invaders | `--cycles 12` |

---

## Testing

Run all 24 unit tests:

```sh
zig build test
```

Run tests directly with verbose output:

```sh
zig test src/cpu.zig
```

### What Is Tested

| Module | Tests |
|--------|-------|
| `memory.zig` | Font sprite loaded, ROM load, ROM too large error |
| `display.zig` | Clear screen, draw sprite, XOR collision detection |
| `input.zig` | Key press/release, `last_key` tracking |
| `cpu.zig` | `CLS`, `JP`, `CALL`/`RET`, `LD`, `ADD`, `ADD` with carry, `SUB` with borrow, `LD I`, `DRW` collision, `BCD`, store/load registers, timer decrement, `LD Vx K` blocking and unblocking |

---

## Project Structure

```
chip8-zig/
├── src/
│   ├── main.zig          SDL2 entry point and emulation loop
│   ├── cpu.zig           CHIP-8 CPU — all 35 opcodes
│   ├── memory.zig        4 KB RAM + font sprites
│   ├── display.zig       64×32 framebuffer
│   ├── input.zig         Hex keypad input
│   ├── audio.zig         SDL2 buzzer
│   └── root.zig          Library exports
├── roms/
│   ├── 1-chip8-logo.ch8
│   ├── 2-ibm-logo.ch8
│   ├── 3-corax+.ch8
│   ├── 4-flags.ch8
│   ├── 5-quirks.ch8
│   ├── pong.ch8
│   ├── space-invaders.ch8
│   └── tetris.ch8
├── build.zig             Zig build configuration
├── build.zig.zon         Package manifest
└── .gitignore
```

---

## CHIP-8 Specification

| Property | Value |
|----------|-------|
| RAM | 4096 bytes (0x000–0xFFF) |
| Program start | 0x200 |
| Font sprites | 0x050–0x09F |
| Registers | V0–VF (8-bit × 16) |
| Index register | I (16-bit) |
| Program counter | PC (16-bit) |
| Stack depth | 16 levels |
| Display | 64 × 32 monochrome |
| Timers | Delay + Sound (8-bit, 60 Hz) |
| Keypad | 16 keys (0x0–0xF) |

### Memory Map

```
0x000 ┌─────────────────────┐
      │  Interpreter area   │  (reserved)
0x050 ├─────────────────────┤
      │  Font sprites 0–F   │  5 bytes × 16 chars
0x09F ├─────────────────────┤
      │      (unused)       │
0x200 ├─────────────────────┤
      │    ROM / Program    │  loaded here
      │                     │
0xFFF └─────────────────────┘
```

---

## Opcode Coverage

All 35 standard CHIP-8 opcodes are implemented:

| Opcode | Mnemonic | Description |
|--------|----------|-------------|
| `00E0` | `CLS` | Clear display |
| `00EE` | `RET` | Return from subroutine |
| `1NNN` | `JP addr` | Jump to address |
| `2NNN` | `CALL addr` | Call subroutine |
| `3XKK` | `SE Vx, byte` | Skip if Vx == kk |
| `4XKK` | `SNE Vx, byte` | Skip if Vx != kk |
| `5XY0` | `SE Vx, Vy` | Skip if Vx == Vy |
| `6XKK` | `LD Vx, byte` | Set Vx = kk |
| `7XKK` | `ADD Vx, byte` | Set Vx = Vx + kk |
| `8XY0` | `LD Vx, Vy` | Set Vx = Vy |
| `8XY1` | `OR Vx, Vy` | Set Vx = Vx OR Vy |
| `8XY2` | `AND Vx, Vy` | Set Vx = Vx AND Vy |
| `8XY3` | `XOR Vx, Vy` | Set Vx = Vx XOR Vy |
| `8XY4` | `ADD Vx, Vy` | Set Vx = Vx + Vy, VF = carry |
| `8XY5` | `SUB Vx, Vy` | Set Vx = Vx - Vy, VF = NOT borrow |
| `8XY6` | `SHR Vx` | Shift right, VF = LSB |
| `8XY7` | `SUBN Vx, Vy` | Set Vx = Vy - Vx, VF = NOT borrow |
| `8XYE` | `SHL Vx` | Shift left, VF = MSB |
| `9XY0` | `SNE Vx, Vy` | Skip if Vx != Vy |
| `ANNN` | `LD I, addr` | Set I = nnn |
| `BNNN` | `JP V0, addr` | Jump to V0 + nnn |
| `CXKK` | `RND Vx, byte` | Set Vx = random AND kk |
| `DXYN` | `DRW Vx, Vy, n` | Draw n-byte sprite, VF = collision |
| `EX9E` | `SKP Vx` | Skip if key Vx is pressed |
| `EXA1` | `SKNP Vx` | Skip if key Vx is not pressed |
| `FX07` | `LD Vx, DT` | Set Vx = delay timer |
| `FX0A` | `LD Vx, K` | Wait for key press, store in Vx |
| `FX15` | `LD DT, Vx` | Set delay timer = Vx |
| `FX18` | `LD ST, Vx` | Set sound timer = Vx |
| `FX1E` | `ADD I, Vx` | Set I = I + Vx |
| `FX29` | `LD F, Vx` | Set I = font sprite address for Vx |
| `FX33` | `LD B, Vx` | Store BCD of Vx at I, I+1, I+2 |
| `FX55` | `LD [I], Vx` | Store V0–Vx in memory at I |
| `FX65` | `LD Vx, [I]` | Read V0–Vx from memory at I |

---

## Troubleshooting

**ROM runs too fast / too slow**
> Adjust the `--cycles` flag. Try values between `5` and `20`.
> ```sh
> zig build run -- --cycles 8 roms/pong.ch8
> ```

**No sound**
> Ensure SDL2 audio is available on your system. The emulator will print a warning and continue without sound if audio init fails.

**Black screen / nothing displayed**
> Run the test ROMs first (`1-chip8-logo.ch8`, `2-ibm-logo.ch8`). If those work, the ROM may require SUPER-CHIP extensions not implemented here.

**Build error: SDL2 not found**
> Install SDL2 development headers for your distro (see [Prerequisites](#prerequisites)).

**`zig build test` shows no output**
> This is normal — Zig only prints output for failing tests. All tests passed silently.
> Run `zig test src/cpu.zig` for verbose per-test output.
