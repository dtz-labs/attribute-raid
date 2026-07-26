#!/usr/bin/env python3
"""Freeze ZEsarUX on a bridge scene and save a rendered screenshot.

Connects to a running ZEsarUX with the ZRCP remote protocol enabled
(--enable-remoteprotocol --remoteprotocol-port 10000), polls the game's
bridge state, and the moment the requested scene is on screen freezes the
CPU (enter-cpu-step), dumps the display file and reports which entities
are live. The dump is rendered to OUT_PREFIX.png and kept raw in
OUT_PREFIX.raw; the emulator is then resumed.

Usage:
    zrcp_bridge_screenshot.py MAP OUT_PREFIX MODE [MIN_Y] [PORT]

MAP        .map file of the running binary (symbol addresses are read
           from it, so the tool survives layout changes)
OUT_PREFIX output path prefix for the .png and .raw files
MODE       now       - freeze and capture immediately
           intact    - wait for an intact bridge span
           destroyed - wait for the destroyed road remnant
           any       - wait for either
MIN_Y      wait until bridge_y >= MIN_Y (default 24; scenes are also
           skipped past y=120 and at cell-aligned phases, so captures
           show the worst-case attribute straddle)
PORT       ZRCP port (default 10000)

The PNG renderer decodes the standard ULA screen only; on a Timex
hi-colour build the .raw dump is still valid but the .png colours are
meaningless. Works best with the autopilot bench builds, e.g.:
    make OUTDIR=build-bench-std DEFINES="-D AUTOPILOT=1 -D AUTOPILOT_NOFIRE=1" standard
(AUTOPILOT_NOFIRE keeps the plane from shooting, so an intact bridge
survives long enough to be inspected.)
"""
import socket
import struct
import sys
import time
import zlib

SYMBOLS = [
    "bridge_active",
    "destroyed_road_active",
    "bridge_y",
    "bridge_col",
    "bridge_width",
    "ship0_active",
    "ship1_active",
    "enemy_plane_active",
    "helicopter_active",
    "fuel_active",
    "balloon_active",
    "tank_active",
]

ENTITY_FLAGS = SYMBOLS[5:]


def read_map(path):
    syms = {}
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2 and parts[1] in SYMBOLS:
                syms[parts[1]] = int(parts[0], 16)
    missing = [s for s in SYMBOLS if s not in syms]
    if missing:
        raise SystemExit(f"symbols missing from {path}: {', '.join(missing)}")
    return syms


class Zrcp:
    def __init__(self, port):
        self.s = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.buf = b""
        self._read_prompt()

    def _read_prompt(self):
        while not self.buf.rstrip(b" ").endswith(b">"):
            chunk = self.s.recv(65536)
            if not chunk:
                raise RuntimeError("ZRCP connection closed")
            self.buf += chunk
        out, self.buf = self.buf, b""
        return out

    def cmd(self, line):
        self.s.sendall(line.encode() + b"\n")
        return self._read_prompt().decode(errors="replace")

    def peek(self, addr, length=1):
        r = self.cmd(f"read-memory {addr} {length}")
        hexpart = "".join(
            ch for ch in r.split("\n")[0].strip() if ch in "0123456789abcdefABCDEF"
        )
        return bytes.fromhex(hexpart[: length * 2])


def png_write(path, w, h, rgb_rows):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + row for row in rgb_rows)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def zx_rgb(idx, bright):
    v = 0xFF if bright else 0xD7
    return ((v if idx & 2 else 0), (v if idx & 4 else 0), (v if idx & 1 else 0))


def render(dump, path, scale=3):
    pixels = dump[0:0x1800]
    attrs = dump[0x1800:0x1B00]
    rows = []
    for y in range(192):
        addr = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
        row = bytearray()
        for col in range(32):
            b = pixels[addr + col]
            a = attrs[(y // 8) * 32 + col]
            ink = zx_rgb(a & 7, a & 64)
            paper = zx_rgb((a >> 3) & 7, a & 64)
            for bit in range(7, -1, -1):
                row += bytes(ink if (b >> bit) & 1 else paper) * scale
        for _ in range(scale):
            rows.append(bytes(row))
    png_write(path, 256 * scale, 192 * scale, rows)


def capture(z, syms, prefix):
    z.cmd("enter-cpu-step")
    try:
        dump = z.peek(0x4000, 0x1B00)
        # Read each symbol on its own: the state block's layout is not a
        # contract, and a byte inserted into it used to silently shift these.
        st = [z.peek(syms[n])[0] for n in SYMBOLS[:5]]
        live = [n for n in ENTITY_FLAGS if z.peek(syms[n])[0]]
    finally:
        render(dump, prefix + ".png")
        with open(prefix + ".raw", "wb") as f:
            f.write(dump)
        z.cmd("exit-cpu-step")
    print(
        f"captured: active={st[0]} destroyed={st[1]} "
        f"bridge_y={st[2]} (mod8={st[2] % 8}) "
        f"bridge_col={st[3]} bridge_width={st[4]} "
        f"entities={live if live else 'NONE'}"
    )


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    syms = read_map(sys.argv[1])
    prefix, mode = sys.argv[2], sys.argv[3]
    min_y = int(sys.argv[4]) if len(sys.argv) > 4 else 24
    port = int(sys.argv[5]) if len(sys.argv) > 5 else 10000
    z = Zrcp(port)
    if mode == "now":
        capture(z, syms, prefix)
        return 0
    deadline = time.time() + 600
    while time.time() < deadline:
        active = z.peek(syms["bridge_active"])[0]
        destroyed = z.peek(syms["destroyed_road_active"])[0]
        by = z.peek(syms["bridge_y"])[0]
        want = (
            (mode == "intact" and active)
            or (mode == "destroyed" and destroyed)
            or (mode == "any" and (active or destroyed))
        )
        # Catch the band mid-cell (worst attribute straddle) and mid-screen.
        if want and min_y <= by <= 120 and by % 8 not in (0, 1):
            capture(z, syms, prefix)
            return 0
        time.sleep(0.15)
    print("timeout: requested bridge scene never appeared")
    return 1


if __name__ == "__main__":
    sys.exit(main())
