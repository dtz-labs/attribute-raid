#!/usr/bin/env python3
"""Zero-interference tail profiler for ZEsarUX via ZRCP cpu-history.

Enlarges the cpu-history ring buffer, then goes silent while the user plays.
After PLAY_SECONDS it freezes emulation (enter-cpu-step), drains the whole
buffer in chunks, resumes (exit-cpu-step), and analyzes the contiguous
instruction trace:

- instruction-share histogram by map symbol,
- frame accounting: interrupts vs frames containing a HALT idle run, so the
  share of frames that overran the 50 Hz budget is measured directly.

Usage: zrcp_tail_profiler.py MAP_FILE PLAY_SECONDS OUT_FILE [PORT]
"""

import bisect
import collections
import socket
import sys
import time

import re

# The prompt is "command> " normally and "command@cpu-step> " in step mode.
PROMPT_RE = re.compile(rb"command[^>\n]*> $")
CHUNK = 50000
MAX_SIZE = 5000000
ISR_ENTRY = 0x0038


def read_until_prompt(sock, buf):
    while True:
        m = PROMPT_RE.search(buf)
        if m:
            return buf[:m.start()], b""
        data = sock.recv(1 << 20)
        if not data:
            raise ConnectionError("ZRCP connection closed")
        buf += data


def command(sock, buf, cmd):
    sock.sendall(cmd + b"\n")
    return read_until_prompt(sock, buf)


def load_symbols(map_path):
    symbols = []
    with open(map_path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 2:
                continue
            try:
                addr = int(parts[0], 16)
            except ValueError:
                continue  # map header lines are not "ADDR name" pairs
            symbols.append((addr, parts[1]))
    symbols.sort()
    if not symbols:
        raise SystemExit(f"no symbols found in {map_path}")
    return symbols


def main():
    map_path = sys.argv[1]
    play_seconds = float(sys.argv[2])
    out_path = sys.argv[3]
    port = int(sys.argv[4]) if len(sys.argv) > 4 else 10000

    symbols = load_symbols(map_path)
    addrs = [a for a, _ in symbols]

    def sym_for(pc):
        if pc < 0x4000:
            return "ROM-interrupt/system"
        if pc < addrs[0]:
            return "below-code(0x4000-0x7FFF)"
        i = bisect.bisect_right(addrs, pc) - 1
        return symbols[i][1]

    sock = socket.create_connection(("127.0.0.1", port), timeout=30)
    sock.settimeout(30)
    buf = b""
    _, buf = read_until_prompt(sock, buf)  # banner

    # PLAY_SECONDS=0 means drain-only: the emulator already holds a recorded
    # buffer (for example after a previous run died mid-drain in step mode).
    if play_seconds > 0:
        # set-max-size works only while history is enabled; starting the
        # recorder briefly enters cpu-step mode, which fails while any menu
        # (like the tape-load progress window) is open - retry until closed.
        for cmd in (b"cpu-history enabled yes",
                    b"cpu-history set-max-size %d" % MAX_SIZE,
                    b"cpu-history get-max-size"):
            resp, buf = command(sock, buf, cmd)
            print(f"{cmd.decode()}: {resp.decode().strip() or 'ok'}", flush=True)

        text = ""
        for _ in range(30):
            resp, buf = command(sock, buf, b"cpu-history started yes")
            text = resp.decode().strip()
            print(f"cpu-history started yes: {text or 'ok'}", flush=True)
            if "Error" not in text or "Already" in text:
                break
            time.sleep(2)
        else:
            raise SystemExit(f"could not start cpu history: {text}")

        resp, buf = command(sock, buf, b"cpu-history clear")
        print(f"cpu-history clear: {resp.decode().strip() or 'ok'}", flush=True)

        print(f"silent for {play_seconds:.0f}s of play", flush=True)
        time.sleep(play_seconds)

    resp, buf = command(sock, buf, b"enter-cpu-step")
    text = resp.decode().strip()
    if text:
        print(f"enter-cpu-step: {text}", flush=True)  # may already be stepped
    try:
        resp, buf = command(sock, buf, b"cpu-history get-size")
        size = int(resp.split()[0])
        size = min(size, MAX_SIZE)
        print(f"draining {size} entries", flush=True)
        trace_new_to_old = []
        start = 0
        while start < size:
            n = min(CHUNK, size - start)
            resp, buf = command(sock, buf, b"cpu-history get-pc %d %d" % (start, n))
            chunk = []
            for tok in resp.split():
                try:
                    chunk.append(int(tok, 16))
                except ValueError:
                    continue  # ignore any status text mixed into the reply
            if not chunk:
                break
            trace_new_to_old.extend(chunk)
            start += n
    finally:
        _, buf = command(sock, buf, b"exit-cpu-step")
        try:
            sock.sendall(b"exit\n")
            sock.close()
        except OSError:
            pass  # session teardown only

    trace = trace_new_to_old[::-1]  # chronological order
    total = len(trace)
    if not total:
        raise SystemExit("empty trace")

    with open(out_path + ".raw", "w") as f:
        f.write("\n".join(f"{pc:04X}" for pc in trace))

    counts = collections.Counter(trace)
    by_symbol = collections.Counter()
    for pc, c in counts.items():
        by_symbol[sym_for(pc)] += c

    # The idle marker is the PC recorded repeatedly while the CPU sits in
    # HALT; identify it as the most frequent PC inside the main_loop region.
    idle_pc, _ = counts.most_common(1)[0]

    interrupts = 0
    frames_with_idle = 0
    idle_run = 0
    saw_idle_this_frame = False
    for pc in trace:
        if pc == idle_pc:
            idle_run += 1
            if idle_run >= 2:
                saw_idle_this_frame = True
        else:
            idle_run = 0
        if pc == ISR_ENTRY:
            interrupts += 1
            if saw_idle_this_frame:
                frames_with_idle += 1
            saw_idle_this_frame = False

    with open(out_path, "w") as f:
        f.write(f"trace: {total} instructions (chronological tail)\n")
        f.write(f"idle marker PC: {idle_pc:04X} ({sym_for(idle_pc)})\n")
        if interrupts:
            over = interrupts - frames_with_idle
            f.write(f"frames (interrupts): {interrupts}, with HALT idle: "
                    f"{frames_with_idle}, overrun: {over} "
                    f"({over / interrupts * 100:.1f}%)\n")
        f.write("\nby symbol (instruction-count share):\n")
        for name, c in by_symbol.most_common(60):
            f.write(f"{c / total * 100:6.2f}%  {c:8d}  {name}\n")
        f.write("\ntop raw PC addresses:\n")
        for pc, c in counts.most_common(40):
            f.write(f"{c / total * 100:6.2f}%  {c:8d}  {pc:04X}  ({sym_for(pc)})\n")
    print(f"done: {total} instructions -> {out_path}", flush=True)


if __name__ == "__main__":
    main()
