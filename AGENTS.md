# Repository Guide

## Project layout

- `src/main.asm` contains the ZX Spectrum game and renderer.
- `tools/build.py` implements the project's small Z80 assembler subset and
  writes the BIN, MAP, BASIC loader, and TAP outputs.
- `Makefile` is the supported build and emulator entry point.
- `.github/workflows/` builds the TAP on pushes and publishes tagged releases.

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
- Update `README.md` when controls, build commands, gameplay, or renderer
  behavior changes.

## Definition of done

- The normal build succeeds and produces a loadable TAP.
- Relevant profile or emulator checks are run when the environment supports
  them, and any skipped checks are reported.
- Documentation and the custom assembler remain consistent with the assembly
  source.
