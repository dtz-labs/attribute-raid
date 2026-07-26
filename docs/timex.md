# Timex TC2048/TC2068/TS2068 support

The game ships a dedicated Timex TAP that uses the Timex 8×1 hi-colour
graphics mode; this page collects the hardware specifics.

The standard ZX Spectrum 128K still has 8×8 colour attributes; its shadow
screen does not add an 8×1 mode. Use the standard TAP on that machine. The
separate Timex TAP selects Extended Color mode through port `0xff`, where the
second display file becomes 6144 scanline attributes. It therefore provides
real 8×1 colour on the TC2048, TC2068, and TS2068, but its colours will not
display correctly on an ordinary Spectrum 128K. The Timex build keeps the same
bitmap, incremental renderer, controls, and 48K-sized game code.

The TC2048 has no native AY chip, but one may be fitted as an optional
interface, so the Timex TAP probes for it instead of going silent outright: a
TC2068 or TS2068 is recognized from its HOME ROM signature and uses the
native AY register/data ports `$00F5`/`$00F6`, while on a TC2048 the build
tests the standard `$FFFD`/`$BFFD` ports (both odd addresses, so the ULA is
never touched) and enables sound only when a real AY answers — register R1
must mask a written `$FF` down to `$0F` and R0 must round-trip `$55`/`$AA`,
which a floating bus fails. The standard TAP continues to use the Spectrum
128K ports `$FFFD`/`$BFFD`. `make run-timex` therefore defaults to TC2068,
while the model-specific targets make the selected hardware explicit.

