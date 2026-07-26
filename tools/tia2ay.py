#!/usr/bin/env python3
"""Generate src/sound_ay_data.asm from the original River Raid sound model.

The Atari 2600 original drives two TIA channels from a per-frame routine
(DoSound). The register behaviour below was transcribed from Thomas
Jentzsch's commented disassembly of River Raid (Activision, 1982): only the
derived per-frame register values are reproduced here, no original code.

TIA model recap (NTSC):
  audio clock  = 3579545 / 114 = 31399.5 Hz
  AUDC 4       = pure tone, f = clock / (AUDF + 1) / 2
  AUDC 0x0C    = pure tone through the divide-by-6 stage
  AUDC 8       = 9-bit polynomial white noise clocked at clock / (AUDF + 1)
  AUDV         = 4-bit linear volume

AY model (Spectrum 128K, 1.7734 MHz):
  tone frequency  f = 1773400 / (16 * period)   -> period = 110837.5 / f
  noise period    5 bits, lower = higher hiss
  volume          4 bits, roughly logarithmic (~1.5 dB per step)

Conversions:
  * Tone effects convert exactly through the two frequency formulas.
  * TIA noise sits far lower than the AY noise generator can reach, so noise
    pitches map order-preservingly into the AY range instead of absolutely:
    the engine/crash map scales the original AUDF span onto periods 1..31,
    while the explosion crackle keeps the original's eight distinct random
    pitches (AUDF 24..31) as AY periods 24..31 to preserve its variety.
  * Volumes convert from TIA's linear DAC to the AY's logarithmic one:
    ay = 15 + 20*log10(tia/15) / 1.5, clamped to 1..15 (0 stays 0).
  * Sequences are resampled from the original's 60 Hz to the Spectrum's
    50 Hz, keeping wall-clock duration and sweep rates.

Run: python3 tools/tia2ay.py [output.asm]   (default src/sound_ay_data.asm)
"""

from __future__ import annotations

import math
import random
import sys
from pathlib import Path

TIA_CLOCK = 3579545 / 114  # 31399.5 Hz NTSC audio clock
AY_CLOCK = 1773400.0
LINE_WIDTH = 12  # db values per emitted line


def tia_tone_freq(audf: int, divider: int) -> float:
    return TIA_CLOCK / ((audf + 1) * divider)


def ay_period(freq: float) -> int:
    period = round(AY_CLOCK / 16 / freq)
    if not 1 <= period <= 4095:
        raise ValueError(f"AY period {period} out of range for {freq:.1f} Hz")
    return period


def ay_noise_scaled(audf: int) -> int:
    # Order-preserving map of the TIA noise range onto the AY's 5-bit range:
    # the lowest TIA rumble the game uses (AUDF $1C) lands on period 31.
    return max(1, min(31, round((audf + 1) * 31 / 29)))


def ay_volume(tia: int) -> int:
    if tia <= 0:
        return 0
    tia = min(tia, 15)
    decibels = 20 * math.log10(tia / 15)
    return max(1, min(15, round(15 + decibels / 1.5)))


def resample_60_to_50(seq: list) -> list:
    n = len(seq)
    m = max(1, int(n * 50 / 60 + 0.5))
    if n == 1 or m == 1:
        return [seq[0]] * m
    return [seq[round(j * (n - 1) / (m - 1))] for j in range(m)]


def missile_frames() -> list[tuple[int, int, int]]:
    # Fifteen frames of descending sweep on the div-6 tone (AUDF $0D..$1B at
    # constant volume 8), then one silent frame so the player ends muted.
    seq = [(0x1C - ms, 8) for ms in range(15, 0, -1)]
    seq.append((seq[-1][0], 0))
    frames = []
    for audf, vol in resample_60_to_50(seq):
        period = ay_period(tia_tone_freq(audf, 6))
        frames.append((period & 0xFF, period >> 8, ay_volume(vol)))
    return frames


def impact_frames() -> list[tuple[int, int]]:
    # A destroyed actor: white noise whose frequency is re-randomised every
    # frame over AUDF 24..31 while the volume falls 15..4 over 23 frames.
    # The randomness is baked with a fixed seed so builds stay reproducible.
    rng = random.Random(0x1982)
    seq = []
    for step in range(23):
        remaining = 23 - step
        audf = 0x18 | rng.randrange(8)
        seq.append((audf, (remaining >> 1) + 4))
    seq.append((seq[-1][0], 0))
    return [(audf, ay_volume(vol)) for audf, vol in resample_60_to_50(seq)]


def decay_burst(count: int) -> list[int]:
    # Sound ids 1 and 2: volume is the countdown halved, through the TIA's
    # 4-bit register (id 2 starts above 15, so its first frames wrap to
    # near-silence before the burst pops in - kept faithfully).
    seq = [((count - step) >> 1) & 0x0F for step in range(count)]
    return [ay_volume(vol) for vol in resample_60_to_50(seq)]


def ding_frames() -> list[int]:
    # Eight frames of decaying pure tone, retriggered on contact with the
    # depot; the final zero mutes the channel between pings.
    seq = list(range(8, 0, -1)) + [0]
    return [ay_volume(vol) for vol in resample_60_to_50(seq)]


def siren_cycle() -> list[int]:
    # Low fuel warning: a 64-frame cycle where the first 36 frames replace
    # the engine with a rising div-6 tone (AUDF cnt/2 for cnt $3F..$1C) and
    # the rest fall back to jet noise (period 0,0 marks those frames).
    seq = []
    for cnt in range(0x3F, -1, -1):
        if cnt >= 0x1C:
            seq.append(ay_period(tia_tone_freq(cnt >> 1, 6)))
        else:
            seq.append(0)
    return resample_60_to_50(seq)


def splash_frames() -> list[tuple[int, int, int]]:
    # No Atari counterpart: the pre-existing AY splash, kept byte-for-byte
    # (falling tone plus coarse noise, volume 7..0 over eight frames).
    frames = []
    period = 768
    for vol in range(7, -1, -1):
        frames.append((period & 0xFF, period >> 8, vol))
        period += 64
    return frames


def engine_tables() -> tuple[list[int], list[int]]:
    # The original maps jet speed to noise AUDF $20-speedY/16 over speedY
    # $41..$FF and volume 4 (7 while accelerating). The game's three speed
    # steps sample that range at slow/normal/fast.
    audfs = [0x1C, 0x17, 0x11]
    tia_vols = [4, 4, 7]
    return ([ay_noise_scaled(a) for a in audfs], [ay_volume(v) for v in tia_vols])


def db_lines(label: str, values: list[int], comment: str) -> list[str]:
    for value in values:
        if not 0 <= value <= 255:
            raise ValueError(f"{label}: byte {value} out of range")
    lines = [f"{label}:"]
    if comment:
        lines[0:0] = [f"; {line}" for line in comment.splitlines()]
    for start in range(0, len(values), LINE_WIDTH):
        chunk = ",".join(str(v) for v in values[start : start + LINE_WIDTH])
        lines.append(f"    db {chunk}")
    return lines


def main() -> int:
    out_path = Path(sys.argv[1] if len(sys.argv) > 1 else "src/sound_ay_data.asm")

    missile = missile_frames()
    impact = impact_frames()
    crash = decay_burst(31)
    fuelout = decay_burst(35)
    ding = ding_frames()
    siren = siren_cycle()
    splash = splash_frames()
    noise_periods, volumes = engine_tables()

    ding_normal = ay_period(tia_tone_freq(0x1F, 2))
    ding_full = ay_period(tia_tone_freq(0x0F, 2))
    assert ding_normal < 256 and ding_full < 256
    assert all(hi < 16 for _, hi, _ in missile)
    assert all(period < 4096 for period in siren)
    assert sum(1 for period in siren if period) >= 25

    lines = [
        "; Generated by tools/tia2ay.py - do not edit by hand.",
        "; Regenerate with: python3 tools/tia2ay.py",
        ";",
        "; Per-frame AY register data derived from the sound behaviour of the",
        "; original Atari 2600 River Raid (values only; see tools/tia2ay.py",
        "; for the TIA-to-AY conversion rules).",
        "",
    ]

    def emit(label: str, values: list[int], comment: str = "") -> None:
        lines.extend(db_lines(label, values, comment))
        lines.append("")

    emit("missile_sound_frames", [len(missile)])
    emit(
        "missile_sound_table",
        [b for frame in missile for b in frame],
        "Player missile: tone period low, high, volume per frame.",
    )
    emit("impact_sound_frames", [len(impact)])
    emit(
        "impact_sound_table",
        [b for frame in impact for b in frame],
        "Destroyed actor: noise period, volume per frame.",
    )
    emit("crash_sound_frames", [len(crash)])
    emit("crash_sound_noise", [ay_noise_scaled(0x1C)])
    emit(
        "crash_sound_table",
        crash,
        "Life lost: channel A volume ramp over fixed coarse noise.",
    )
    emit("fuelout_sound_frames", [len(fuelout)])
    emit("fuelout_sound_noise", [ay_noise_scaled(0x08)])
    emit(
        "fuelout_sound_table",
        fuelout,
        "Out of fuel: longer, higher-pitched variant of the life-lost burst.",
    )
    emit("ding_sound_frames", [len(ding)])
    emit("ding_period_normal", [ding_normal])
    emit("ding_period_full", [ding_full])
    emit(
        "ding_volume_table",
        ding,
        "Refuelling ping volume ramp; the tone period is set at trigger time.",
    )
    emit("siren_cycle_frames", [len(siren)])
    emit("siren_volume", [15])
    emit(
        "siren_period_table",
        [b for period in siren for b in (period & 0xFF, period >> 8)],
        "Low-fuel warning cycle: tone period low, high per frame; a zero\n"
        "period hands the frame back to the engine noise.",
    )
    emit("splash_sound_frames", [len(splash)])
    emit(
        "splash_sound_table",
        [b for frame in splash for b in frame],
        "Shell splash (no Atari counterpart): tone period low, high, volume.",
    )
    emit(
        "ay_engine_noise_periods",
        noise_periods,
        "Jet engine at slow, normal, fast. Lower period = higher noise.",
    )
    emit("ay_engine_volumes", volumes)

    out_path.write_text("\n".join(lines).rstrip() + "\n", encoding="ascii")
    total = sum(
        len(t)
        for t in (missile, impact, crash, fuelout, ding, siren, splash)
    )
    print(
        f"{out_path}: missile {len(missile)}f, impact {len(impact)}f, "
        f"crash {len(crash)}f, fuelout {len(fuelout)}f, ding {len(ding)}f, "
        f"siren cycle {len(siren)}f, splash {len(splash)}f "
        f"({total} frames total)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
