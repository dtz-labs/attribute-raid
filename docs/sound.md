# AY sound

The effects are a port of the original Atari 2600 sound routine: its per-frame
TIA register behaviour was transcribed from the commented River Raid
disassembly and converted offline by `tools/tia2ay.py` into the AY frame
tables in the generated, committed `src/sound_ay_data.asm` (tone frequencies
convert exactly, noise pitches map order-preservingly into the AY range,
linear TIA volumes map onto the AY's logarithmic scale, and every sequence is
resampled from 60 Hz to 50 Hz). Run `make sound-data` after changing the
converter. The channel layout:

- channel A is the white-noise jet engine; slow, base, and fast movement
  sample the original's speed-to-frequency formula, and fast flight is louder,
- channel A also carries the low-fuel warning (below a quarter tank the
  engine periodically gives way to the original's rising siren tone) and the
  life-lost noise burst, which uses a longer, higher variant when the tank
  runs dry,
- channel B replays the missile's descending frequency sweep; tank fire keeps
  its own sharper sweep (the shore gun has no Atari counterpart),
- channel C plays the destroyed-actor burst — white noise whose frequency is
  re-randomised every frame, giving the original's crackle — plus the tank
  shell's water splash,
- refuelling repeats the original's short decaying ping for as long as the
  aircraft touches the depot, jumping exactly one octave higher once the tank
  is full.

Engine registers are rewritten only when the requested speed changes. A stock
48K Spectrum continues to run the same game code silently; use `make run` for a
128K ZEsarUX configuration or `make run-48` to test that fallback explicitly.

