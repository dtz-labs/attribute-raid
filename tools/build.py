#!/usr/bin/env python3
"""Build the Attribute Raid proof of concept.

The development machine used for this project does not provide a Z80
assembler.  This script implements the small assembler subset used by
src/main.asm and writes a Spectrum TAP with a BASIC loader plus a CODE block.
"""

from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path


REG8 = {
    "b": 0,
    "c": 1,
    "d": 2,
    "e": 3,
    "h": 4,
    "l": 5,
    "(hl)": 6,
    "a": 7,
}

REG16 = {
    "bc": 0,
    "de": 1,
    "hl": 2,
    "sp": 3,
}

PUSHPOP = {
    "bc": 0,
    "de": 1,
    "hl": 2,
    "af": 3,
}

JR_COND = {
    "nz": 0x20,
    "z": 0x28,
    "nc": 0x30,
    "c": 0x38,
}


class AsmError(Exception):
    pass


def strip_comment(line: str) -> str:
    in_string = False
    escaped = False
    out = []
    for ch in line:
        if escaped:
            out.append(ch)
            escaped = False
            continue
        if ch == "\\" and in_string:
            out.append(ch)
            escaped = True
            continue
        if ch == '"':
            in_string = not in_string
            out.append(ch)
            continue
        if ch == ";" and not in_string:
            break
        out.append(ch)
    return "".join(out).strip()


def split_operands(text: str) -> list[str]:
    result = []
    current = []
    depth = 0
    in_string = False
    escaped = False
    for ch in text:
        if escaped:
            current.append(ch)
            escaped = False
            continue
        if ch == "\\" and in_string:
            current.append(ch)
            escaped = True
            continue
        if ch == '"':
            in_string = not in_string
            current.append(ch)
            continue
        if not in_string:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == "," and depth == 0:
                result.append("".join(current).strip())
                current = []
                continue
        current.append(ch)
    tail = "".join(current).strip()
    if tail:
        result.append(tail)
    return result


def mem_expr(op: str) -> str | None:
    op = op.strip()
    if op.startswith("(") and op.endswith(")") and op.lower() not in REG8:
        return op[1:-1].strip()
    return None


class Assembler:
    def __init__(self, source: Path, defines: dict[str, int] | None = None) -> None:
        self.source = source
        self.defines = defines or {}
        self.lines = self._preprocess(source.resolve(), [])
        self.labels: dict[str, int] = {}
        self.origin: int | None = None
        self.pc = 0
        self.pass_no = 1

    def _preprocess(self, source: Path, include_stack: list[Path]) -> list[str]:
        """Expand includes and compile-time conditionals before both passes.

        Supported directives intentionally mirror the small subset this project
        needs: #if, #ifdef, #ifndef, #else, #endif and #include "file".  The
        leading # is optional for compatibility with traditional assemblers.
        """
        if source in include_stack:
            chain = " -> ".join(str(path) for path in [*include_stack, source])
            raise AsmError(f"recursive include: {chain}")
        try:
            raw_lines = source.read_text(encoding="utf-8").splitlines()
        except OSError as exc:
            raise AsmError(f"cannot read include {source}: {exc}") from exc

        output: list[str] = []
        # Each entry is (parent active, condition value, else already seen).
        conditions: list[tuple[bool, bool, bool]] = []
        active = True
        directive_re = re.compile(
            r"^\s*#?\s*(if|ifdef|ifndef|else|endif|include)\b(.*)$",
            re.IGNORECASE,
        )

        for lineno, raw in enumerate(raw_lines, 1):
            match = directive_re.match(raw)
            if not match:
                if active:
                    output.append(raw)
                else:
                    output.append("")
                continue

            directive = match.group(1).lower()
            argument = match.group(2).strip()
            if directive in {"if", "ifdef", "ifndef"}:
                if directive == "if":
                    try:
                        value = eval(
                            argument,
                            {"__builtins__": {}},
                            dict(self.defines),
                        )
                    except Exception as exc:
                        raise AsmError(
                            f"{source}:{lineno}: bad #if expression {argument!r}"
                        ) from exc
                    condition = bool(int(value))
                else:
                    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", argument):
                        raise AsmError(
                            f"{source}:{lineno}: bad #{directive} symbol {argument!r}"
                        )
                    condition = argument in self.defines
                    if directive == "ifndef":
                        condition = not condition
                conditions.append((active, condition, False))
                active = active and condition
                output.append("")
                continue

            if directive == "else":
                if argument:
                    raise AsmError(f"{source}:{lineno}: unexpected text after #else")
                if not conditions:
                    raise AsmError(f"{source}:{lineno}: #else without #if")
                parent_active, condition, else_seen = conditions[-1]
                if else_seen:
                    raise AsmError(f"{source}:{lineno}: duplicate #else")
                conditions[-1] = (parent_active, condition, True)
                active = parent_active and not condition
                output.append("")
                continue

            if directive == "endif":
                if argument:
                    raise AsmError(f"{source}:{lineno}: unexpected text after #endif")
                if not conditions:
                    raise AsmError(f"{source}:{lineno}: #endif without #if")
                parent_active, _, _ = conditions.pop()
                active = parent_active
                output.append("")
                continue

            # #include is ignored inside an inactive branch, just like C.
            if not active:
                output.append("")
                continue
            include_match = re.fullmatch(r'"([^"\n]+)"', argument)
            if not include_match:
                raise AsmError(
                    f"{source}:{lineno}: #include expects a quoted relative path"
                )
            include_path = (source.parent / include_match.group(1)).resolve()
            output.extend(self._preprocess(include_path, [*include_stack, source]))

        if conditions:
            raise AsmError(f"{source}: unterminated conditional block")
        return output

    def assemble(self) -> tuple[int, bytes, dict[str, int]]:
        self.pass_no = 1
        self._run_pass()
        self.pass_no = 2
        data = self._run_pass()
        assert self.origin is not None
        return self.origin, bytes(data), self.labels

    def _run_pass(self) -> bytearray:
        self.pc = 0
        output = bytearray()
        for lineno, raw in enumerate(self.lines, 1):
            line = strip_comment(raw)
            if not line:
                continue
            try:
                emitted = self._line(line)
            except AsmError as exc:
                raise AsmError(f"{self.source}:{lineno}: {exc}") from exc
            if self.origin is not None and self.pass_no == 2:
                output.extend(emitted)
        return output

    def _line(self, line: str) -> bytes:
        while ":" in line:
            before, after = line.split(":", 1)
            label = before.strip()
            if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", label):
                break
            if self.pass_no == 1:
                self.labels[label] = self.pc
            line = after.strip()
            if not line:
                return b""

        parts = line.split(None, 1)
        op = parts[0].lower()
        rest = parts[1].strip() if len(parts) > 1 else ""

        if op == "org":
            value = self.expr(rest)
            if self.origin is None:
                self.origin = value
            self.pc = value
            return b""

        if self.origin is None:
            raise AsmError("missing ORG before code")

        if op == "align":
            args = split_operands(rest)
            boundary = self.expr(args[0])
            fill = self.expr(args[1]) & 0xFF if len(args) > 1 else 0
            count = (-self.pc) % boundary
            self.pc += count
            return bytes([fill]) * count

        if op == "db":
            data = self.data_bytes(rest)
            self.pc += len(data)
            return data

        if op == "dw":
            data = bytearray()
            for item in split_operands(rest):
                value = self.expr(item)
                data.extend(self.u16(value))
            self.pc += len(data)
            return bytes(data)

        if op == "ds":
            args = split_operands(rest)
            count = self.expr(args[0])
            fill = self.expr(args[1]) & 0xFF if len(args) > 1 else 0
            self.pc += count
            return bytes([fill]) * count

        data = self.encode_instruction(op, rest)
        self.pc += len(data)
        return bytes(data)

    def data_bytes(self, rest: str) -> bytes:
        data = bytearray()
        for item in split_operands(rest):
            if item.startswith('"'):
                try:
                    value = ast.literal_eval(item)
                except SyntaxError as exc:
                    raise AsmError(f"bad string literal {item}") from exc
                data.extend(value.encode("ascii"))
            else:
                data.append(self.expr(item) & 0xFF)
        return bytes(data)

    def expr(self, text: str) -> int:
        text = text.strip()
        env = dict(self.defines)
        env.update(self.labels)
        env["HIGH"] = lambda x: (int(x) >> 8) & 0xFF
        env["LOW"] = lambda x: int(x) & 0xFF
        env["$"] = self.pc
        try:
            value = eval(text, {"__builtins__": {}}, env)
        except NameError:
            if self.pass_no == 1:
                return 0
            raise
        except Exception as exc:
            raise AsmError(f"bad expression {text!r}") from exc
        return int(value)

    @staticmethod
    def u8(value: int) -> int:
        return value & 0xFF

    @staticmethod
    def u16(value: int) -> bytes:
        value &= 0xFFFF
        return bytes([value & 0xFF, value >> 8])

    def rel8(self, target: int, size: int) -> int:
        offset = target - (self.pc + size)
        if self.pass_no == 2 and not -128 <= offset <= 127:
            raise AsmError(f"relative jump out of range: {offset}")
        return offset & 0xFF

    def encode_instruction(self, op: str, rest: str) -> bytes:
        args = split_operands(rest) if rest else []

        if op == "nop":
            return b"\x00"
        if op == "di":
            return b"\xf3"
        if op == "ei":
            return b"\xfb"
        if op == "halt":
            return b"\x76"
        if op == "ret":
            if args:
                cond = args[0].lower()
                ret_cond = {
                    "nz": 0xC0,
                    "z": 0xC8,
                    "nc": 0xD0,
                    "c": 0xD8,
                }
                if cond not in ret_cond:
                    raise AsmError(f"unsupported RET condition {cond}")
                return bytes([ret_cond[cond]])
            return b"\xc9"
        if op == "ldir":
            return b"\xed\xb0"
        if op == "rrca":
            return b"\x0f"
        if op == "ex":
            lowered = [a.lower() for a in args]
            if lowered == ["de", "hl"]:
                return b"\xeb"
            if lowered == ["af", "af'"]:
                return b"\x08"

        if op == "call":
            return bytes([0xCD]) + self.u16(self.expr(args[0]))
        if op == "jp":
            if len(args) == 1:
                return bytes([0xC3]) + self.u16(self.expr(args[0]))
            jp_cond = {
                "nz": 0xC2,
                "z": 0xCA,
                "nc": 0xD2,
                "c": 0xDA,
            }
            cond = args[0].lower()
            if cond not in jp_cond:
                raise AsmError(f"unsupported JP condition {cond}")
            return bytes([jp_cond[cond]]) + self.u16(self.expr(args[1]))
        if op == "djnz":
            return bytes([0x10, self.rel8(self.expr(args[0]), 2)])
        if op == "jr":
            if len(args) == 1:
                return bytes([0x18, self.rel8(self.expr(args[0]), 2)])
            cond = args[0].lower()
            if cond not in JR_COND:
                raise AsmError(f"unsupported JR condition {cond}")
            return bytes([JR_COND[cond], self.rel8(self.expr(args[1]), 2)])

        if op == "push":
            rr = args[0].lower()
            if rr not in PUSHPOP:
                raise AsmError(f"unsupported PUSH operand {rr}")
            return bytes([0xC5 + PUSHPOP[rr] * 0x10])
        if op == "pop":
            rr = args[0].lower()
            if rr not in PUSHPOP:
                raise AsmError(f"unsupported POP operand {rr}")
            return bytes([0xC1 + PUSHPOP[rr] * 0x10])

        if op == "inc":
            r = args[0].lower()
            if r in REG8:
                return bytes([0x04 + REG8[r] * 8])
            if r in REG16:
                return bytes([0x03 + REG16[r] * 0x10])
        if op == "dec":
            r = args[0].lower()
            if r in REG8:
                return bytes([0x05 + REG8[r] * 8])
            if r in REG16:
                return bytes([0x0B + REG16[r] * 0x10])

        if op == "add":
            dst, src = args[0].lower(), args[1].lower()
            if dst == "a":
                if src in REG8:
                    return bytes([0x80 + REG8[src]])
                return bytes([0xC6, self.u8(self.expr(args[1]))])
            if dst == "hl" and src in REG16:
                return bytes([0x09 + REG16[src] * 0x10])

        if op in {"sub", "cp", "and", "or", "xor"}:
            return self.encode_alu(op, args[0])

        if op == "srl":
            r = args[0].lower()
            if r in REG8:
                return bytes([0xCB, 0x38 + REG8[r]])

        if op == "rr":
            r = args[0].lower()
            if r in REG8:
                return bytes([0xCB, 0x18 + REG8[r]])

        if op == "bit":
            bit = self.expr(args[0])
            r = args[1].lower()
            if r in REG8:
                return bytes([0xCB, 0x40 + bit * 8 + REG8[r]])

        if op == "out":
            port, src = args[0], args[1].lower()
            if src == "a" and port.lower() == "(c)":
                return b"\xed\x79"
            if src == "a" and port.startswith("(") and port.endswith(")"):
                return bytes([0xD3, self.u8(self.expr(port[1:-1]))])

        if op == "in":
            dst, port = args[0].lower(), args[1].lower()
            if dst == "a" and port == "(c)":
                return b"\xed\x78"

        if op == "ld":
            return self.encode_ld(args[0], args[1])

        raise AsmError(f"unsupported instruction: {op} {rest}")

    def encode_alu(self, op: str, arg: str) -> bytes:
        reg_bases = {
            "sub": 0x90,
            "cp": 0xB8,
            "and": 0xA0,
            "or": 0xB0,
            "xor": 0xA8,
        }
        imm_bases = {
            "sub": 0xD6,
            "cp": 0xFE,
            "and": 0xE6,
            "or": 0xF6,
            "xor": 0xEE,
        }
        low = arg.lower()
        if low in REG8:
            return bytes([reg_bases[op] + REG8[low]])
        return bytes([imm_bases[op], self.u8(self.expr(arg))])

    def encode_ld(self, dst: str, src: str) -> bytes:
        dst_l = dst.lower()
        src_l = src.lower()

        if dst_l in REG8:
            if src_l in REG8:
                return bytes([0x40 + REG8[dst_l] * 8 + REG8[src_l]])
            if src_l == "(de)" and dst_l == "a":
                return b"\x1a"
            mem = mem_expr(src)
            if mem is not None and dst_l == "a":
                return bytes([0x3A]) + self.u16(self.expr(mem))
            return bytes([0x06 + REG8[dst_l] * 8, self.u8(self.expr(src))])

        if dst_l in REG16:
            mem = mem_expr(src)
            if mem is not None:
                if dst_l == "hl":
                    return bytes([0x2A]) + self.u16(self.expr(mem))
                if dst_l == "de":
                    return bytes([0xED, 0x5B]) + self.u16(self.expr(mem))
                if dst_l == "sp":
                    return bytes([0xED, 0x7B]) + self.u16(self.expr(mem))
            if dst_l == "sp" and src_l == "hl":
                return b"\xf9"
            return bytes([0x01 + REG16[dst_l] * 0x10]) + self.u16(self.expr(src))

        if dst_l == "(de)" and src_l == "a":
            return b"\x12"

        if dst_l == "(hl)":
            if src_l in REG8:
                return bytes([0x70 + REG8[src_l]])
            return bytes([0x36, self.u8(self.expr(src))])

        mem = mem_expr(dst)
        if mem is not None:
            if src_l == "a":
                return bytes([0x32]) + self.u16(self.expr(mem))
            if src_l == "hl":
                return bytes([0x22]) + self.u16(self.expr(mem))
            if src_l == "de":
                return bytes([0xED, 0x53]) + self.u16(self.expr(mem))
            if src_l == "sp":
                return bytes([0xED, 0x73]) + self.u16(self.expr(mem))

        raise AsmError(f"unsupported LD operands: {dst}, {src}")


def tap_block(flag: int, data: bytes) -> bytes:
    payload = bytes([flag]) + data
    checksum = 0
    for byte in payload:
        checksum ^= byte
    block = payload + bytes([checksum])
    return len(block).to_bytes(2, "little") + block


def zx_header(file_type: int, name: str, length: int, param1: int, param2: int) -> bytes:
    encoded = name.encode("ascii")[:10].ljust(10, b" ")
    return (
        bytes([file_type])
        + encoded
        + length.to_bytes(2, "little")
        + param1.to_bytes(2, "little")
        + param2.to_bytes(2, "little")
    )


def zx_number(value: int) -> bytes:
    return str(value).encode("ascii") + b"\x0e\x00\x00" + value.to_bytes(2, "little") + b"\x00"


def basic_line(number: int, body: bytes) -> bytes:
    content = body + b"\x0d"
    return number.to_bytes(2, "big") + len(content).to_bytes(2, "little") + content


def basic_loader(start: int) -> bytes:
    program = bytearray()
    program.extend(basic_line(10, b"\xfd" + zx_number(start - 1)))
    program.extend(basic_line(20, b'\xef""\xaf'))
    program.extend(basic_line(30, b"\xf9\xc0" + zx_number(start)))
    return bytes(program)


def write_tap(path: Path, code: bytes, start: int) -> None:
    loader = basic_loader(start)
    tap = bytearray()
    tap.extend(tap_block(0x00, zx_header(0, "ATTR-RAID", len(loader), 10, len(loader))))
    tap.extend(tap_block(0xFF, loader))
    tap.extend(tap_block(0x00, zx_header(3, "RAIDCODE", len(code), start, start)))
    tap.extend(tap_block(0xFF, code))
    path.write_bytes(tap)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-D",
        "--define",
        action="append",
        default=[],
        metavar="NAME=VALUE",
        help="define an integer symbol for assembly expressions",
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("outdir", type=Path)
    parser.add_argument(
        "--basename",
        default="attribute-raid",
        help="base name for generated BIN, TAP and MAP files",
    )
    args = parser.parse_args()

    defines = {
        "PROFILE_BORDER": 0,
        "TIMEX_HICOLOR": 0,
        "PLAYFIELD_BOTTOM": 168,
    }
    for item in args.define:
        if "=" in item:
            name, value = item.split("=", 1)
        else:
            name, value = item, "1"
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
            parser.error(f"bad define name: {name!r}")
        defines[name] = int(value, 0)

    args.outdir.mkdir(parents=True, exist_ok=True)
    assembler = Assembler(args.source, defines)
    try:
        origin, code, labels = assembler.assemble()
    except AsmError as exc:
        print(exc, file=sys.stderr)
        return 1

    if not re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", args.basename):
        parser.error(f"bad output basename: {args.basename!r}")

    bin_path = args.outdir / f"{args.basename}.bin"
    tap_path = args.outdir / f"{args.basename}.tap"
    map_path = args.outdir / f"{args.basename}.map"

    bin_path.write_bytes(code)
    write_tap(tap_path, code, origin)

    with map_path.open("w", encoding="ascii") as fh:
        for name, value in sorted(labels.items(), key=lambda item: item[1]):
            fh.write(f"{value:04X} {name}\n")

    print(f"Wrote {tap_path} ({tap_path.stat().st_size} bytes)")
    print(f"Code origin 0x{origin:04X}, size {len(code)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
