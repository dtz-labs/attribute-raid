# Repository Guide

## Project layout

- `src/main.asm` contains the ZX Spectrum game and renderer.
- `tools/build.py` implements the project's small Z80 assembler subset and
  writes the BIN, MAP, BASIC loader, and TAP outputs (including the
  `assets/loading-screen.scr` SCREEN$ block).
- `Makefile` is the supported build and emulator entry point.
- `.github/workflows/` builds the TAP on pushes and publishes tagged releases.
- `README.md` is a deliberately short overview; the technical documentation
  lives in `docs/`: [docs/building.md](docs/building.md) (make targets,
  emulator config, toolchain, module layout), [docs/timex.md](docs/timex.md)
  (Timex 8×1 mode and AY hardware detection),
  [docs/renderer.md](docs/renderer.md) (course model, incremental renderer,
  performance budget), [docs/gameplay.md](docs/gameplay.md) (collision, HUD,
  fuel, bridges, scoring) and [docs/sound.md](docs/sound.md) (Atari-derived
  AY effects and the TIA→AY converter).
- `assets/` holds the loading screen (source PNG and converted `.scr`).

## Build and verification

- Run `make` for the normal build. It must produce
  `build/attribute-raid.tap` without an external Z80 toolchain.
- Run `make profile` when changing timing-sensitive renderer code.
- Run `git diff --check` before committing.
- Emulator targets such as `make run` require a local ZEsarUX installation and
  are not required in headless environments.

## Engineering conventions

- Keep the runtime code compatible with the ZX Spectrum 48K; AY sound may be
  used optionally on compatible 128K hardware.
- Preserve the incremental renderer: do not replace it with full-screen bitmap
  copies or a second screen buffer.
- When adding a Z80 instruction form to `src/main.asm`, add matching encoding
  support to `tools/build.py` in the same change.
- Keep generated files under `build/`; do not commit build artifacts.
- Update the documentation when controls, build commands, gameplay, or
  renderer behavior changes: player-facing basics belong in the short
  `README.md`, technical detail in the matching `docs/*.md` page.

## Profiling and emulator inspection tools

Both tools talk to a running ZEsarUX over the ZRCP remote protocol. Launch
the emulator with the protocol enabled (one instance only — kill leftovers
with `pkill -f 'zesarux --configfile'` first):

```
/Applications/ZEsarUX.app/Contents/MacOS/zesarux \
    --configfile tools/zesarux.rc --nosplash --nowelcomemessage --verbose 0 \
    --machine 128k --enable-remoteprotocol --remoteprotocol-port 10000 \
    build-bench-std/attribute-raid.tap
```

(Timex: `--machine TC2068 --enabletimexvideo` and the timex TAP.)

On a headless host add `--vo null --ao null --audiovolume 0`. Without
`--vo null` the Cocoa build blocks before it opens the ZRCP port, so the
emulator sits at 0 % CPU with nothing listening and every tool times out
waiting for it. The audio flags matter whenever the host has a speaker: the
game starts its AY effects as soon as it runs.

### Autopilot bench builds

Unattended measurement uses the AUTOPILOT define: invulnerable plane,
constant fast scroll, a 32-frame steering weave, autofire, no fuel drain.
`AUTOPILOT_NOFIRE=1` additionally holds fire so an intact bridge survives
for inspection.

```
make OUTDIR=build-bench-std DEFINES="-D AUTOPILOT=1" standard
make OUTDIR=build-bench     DEFINES="-D AUTOPILOT=1" timex
```

Delete the TAP before rebuilding with different DEFINES — the Makefile does
not track define changes.

### tools/zrcp_tail_profiler.py — where do the T-states go

Trace-based profiler built on ZRCP `cpu-history`. Records a multi-million
entry PC tail, segments it into frames at ISR entries (0x0038), counts
frames without an idle HALT run as overruns, and attributes busy time to
code regions via the `.map` file.

```
python3 tools/zrcp_tail_profiler.py build-bench-std/attribute-raid.map \
    30 /tmp/profile.txt
```

`PLAY_SECONDS 0` only drains an already recorded history.

Pitfalls, all of them learned the hard way:

- Run **one profiling cycle per emulator launch**. A second cycle on the
  same instance reads whatever state the first one left behind, which shows
  up as a trace that is 100% ROM.
- **Wait until the game is actually playing before starting the profiler.**
  Every cpu-history command briefly enters cpu-step mode, which the emulator
  refuses while a menu is open; the tool now clears that with
  `close-all-menus`, and doing so *cancels a tape load in progress*, leaving
  the machine in BASIC. Poll a game symbol (`player_x` changing) first.
- **`write-memory` silently drops the emulator into cpu-step.** Follow every
  poke with `exit-cpu-step` or the machine freezes and nothing else happens.
- Reading a multi-byte value one byte at a time straddles the frame that
  changes it and invents intermediate states. Read adjacent bytes in a single
  `read-memory`.
- Do not sample with `get-registers` polling (it aliases to the
  command-service point).
- Entry counts are not T-states — idle frames have MORE entries, not fewer.
- Two builds never play the same scene, so overrun percentages compare only
  loosely; a difference of a point or so is scene noise, not a regression.

### tools/zrcp_bridge_screenshot.py — frozen visual verification

Waits for a bridge scene (`intact`, `destroyed`, `any`, or `now` for an
immediate grab), freezes the CPU mid-cell at the worst attribute straddle,
renders the screen to PNG, saves the raw display file, and lists which
entities are live (the bridge corridor is expected to report NONE).

```
python3 tools/zrcp_bridge_screenshot.py \
    build-bench-std/attribute-raid.map /tmp/bridge intact
```

The PNG renderer understands the standard ULA screen only; for Timex
hi-colour builds use the `.raw` dump. Symbol addresses come from the map
file, so the tool survives memory-layout changes.

## Definition of done

- The normal build succeeds and produces a loadable TAP.
- Relevant profile or emulator checks are run when the environment supports
  them, and any skipped checks are reported.
- Documentation and the custom assembler remain consistent with the assembly
  source.
