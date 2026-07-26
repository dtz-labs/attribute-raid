# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); released
versions are git tags of the form `vX.Y.Z`, and the release workflow attaches
both TAPs to every tagged release.

## [Unreleased]

Nothing yet.

## [0.3.0] - 2026-07-26

### Added

- Loading screen: both TAPs carry a `SCREEN$` block (converted in
  `assets/loading-screen.scr`) shown while the code block loads.

- Sound effects ported from the Atari 2600 original: the per-frame TIA
  register behaviour of River Raid's sound routine, transcribed from Thomas
  Jentzsch's commented disassembly, is converted offline by `tools/tia2ay.py`
  into committed AY frame tables (`src/sound_ay_data.asm`). This covers the
  missile's descending sweep, the destroyed-actor crackle (noise frequency
  re-randomised every frame), the life-lost burst, a distinct longer burst
  when the tank runs dry, and the repeating refuel ping that jumps one octave
  higher on a full tank.
- Low-fuel warning: below a quarter tank the engine channel periodically
  gives way to the original's rising siren tone.
- The jet engine's three speed steps now sample the original's
  speed-to-frequency formula, with louder fast flight.
- TC2048: the Timex build probes the standard `$FFFD`/`$BFFD` ports for an
  optional AY interface (R1 must mask `$FF` to `$0F`, R0 must round-trip
  `$55`/`$AA`) and enables sound when a real chip answers, instead of
  staying silent on every TC2048.
- `make sound-data` regenerates `src/sound_ay_data.asm` after converter
  changes.

### Changed

- `src/sound_ay.asm` is now a table-driven per-frame player; the tank shell
  sweep and the water splash keep their previous, Spectrum-original sounds.
- README shortened to an overview; technical documentation moved to `docs/`
  (building, Timex support, renderer, gameplay, sound).
- Standard-build road restyled as black bitmap edge lines.
- Bridges align to the attribute grid, land on flush banks, and their boards
  spawn no conflicting actors.

### Fixed

- The player aircraft now draws over the FUEL depot while refuelling: the
  depot joined the world-background model, so the plane composes on top of
  it (and sprites restored over the depot keep its body) instead of the
  scrolling depot column overwriting the plane.

### Performance

- The steering compositor is faster, unchanged dirty rows are nearly free,
  and the bridge board holds 50 Hz; a trace-based profiling bench
  (`tools/zrcp_tail_profiler.py`) measures frame overruns in ZEsarUX.

## [0.2.0] - 2026-07-25

- Timex 8×1 hi-colour build for TC2048/TC2068/TS2068 with a pixel-precise
  course; native TC2068/TS2068 AY output at `$00F5`/`$00F6`.
- Assembly split into per-subsystem modules under `src/`.
- Resident sprite rendering refactored; Atari-style river banking restored.
- ZEsarUX runs from a project config file with the real joystick mapping.
- Releases ship both the standard and Timex TAPs.

## [0.1.3] - 2026-07-25

- Optimized frame load and top-edge spawning.

## [0.1.2] - 2026-07-25

- Asymmetric river width changes.

## [0.1.1] - 2026-07-25

- Left bank rendering and object spawning fixes; repository agent guide.

## [0.1.0] - 2026-07-25

- Initial beta: renderer V3 prototype with the eight-scanline course cadence,
  jagged precomputed river, smooth-scrolling sprites and water traffic, speed
  controls, collisions, fuel and refuelling, scoring, first AY sound, and the
  Timex double-buffer groundwork.
