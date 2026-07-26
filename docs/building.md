# Building and running

Technical build reference. For the quick start see the top-level README;
for the Timex-specific video/AY notes see [timex.md](timex.md).

```sh
make
make run
make run-48       # graphics/gameplay only on a stock 48K machine
make run-timex    # alias for TC2068: hi-colour plus native AY
make run-tc2048   # hi-colour, no native AY chip
make run-tc2068   # hi-colour plus AY at ports 00F5/00F6
make run-ts2068   # US TS2068 variant
```

The default build produces two files:

- `build/attribute-raid.tap` for the ZX Spectrum 48K/128K,
- `build/attribute-raid-timex.tap` for the Timex TC2048/TC2068/TS2068
  hi-colour mode.

Other targets are:

```sh
make standard     # build only the 48K/128K TAP
make timex        # build only the Timex 8x1 TAP
make profile      # the border shows the duration of a complete game update
make run-profile
make profile-timex      # the same timing build for Timex 8x1
make run-profile-timex
make zesarux-config  # re-copy the host joystick mapping from ~/.zesaruxrc
make clean
```

### Emulator configuration

The `run*` targets start ZEsarUX with `--configfile tools/zesarux.rc` instead
of the global `~/.zesaruxrc`, so runs are reproducible and never overwrite
your own settings. That file holds the emulated Kempston joystick plus the
host joystick/pad mapping, and the emulator is told not to save it on exit.

Remap the pad in a normal ZEsarUX session (which writes `~/.zesaruxrc`), then
run `make zesarux-config` to copy the mapping back into `tools/zesarux.rc`.
Extra one-off flags can still be passed via `ZESARUX_FLAGS`, for example
`make run ZESARUX_FLAGS="--zoom 3"`.

`make run` selects a Spectrum 128K in ZEsarUX so the AY soundtrack is audible.
The program remains safe on a stock 48K machine, but its AY port writes have no
chip to answer them and are therefore silent.

The program starts at address `32768` (`0x8000`). `tools/build.py` implements
the small subset of Z80 instructions used by the game and generates both the
BASIC loader and TAP file, so no external Z80 toolchain is required.

The assembly is split by responsibility: `main.asm` owns startup, the main
loop, Spectrum attributes and screen states; course, entities, resident sprite
rendering, Timex attributes, AY sound, input, sprite data and writable state
live in separate `src/*.asm` includes. The built-in preprocessor supports
`#include`, conditional builds, `equ`, `assert`, and small parameter macros:
`#macro NAME arg`, `{arg}` substitution, `@NAME value`, and expansion-local
labels beginning with `%%`. `make` tracks every included assembly file.

