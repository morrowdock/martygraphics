# SPDX-License-Identifier: Apache-2.0
"""MP4 fast start in pure Python: move the 'moov' box before 'mdat' and fix chunk offsets.

    python3 -m mgrender.faststart <file.mp4>     # rewrites in place when needed
"""
import os
import struct
import sys

CONTAINERS = {b"moov", b"trak", b"mdia", b"minf", b"stbl", b"edts", b"mvex", b"dinf"}


def boxes(data, start=0, end=None):
    """Yield (type, offset, size, header_size) for the boxes in data[start:end]."""
    end = len(data) if end is None else end
    pos = start
    while pos + 8 <= end:
        size, kind = struct.unpack_from(">I4s", data, pos)
        header = 8
        if size == 1:
            size = struct.unpack_from(">Q", data, pos + 8)[0]
            header = 16
        elif size == 0:
            size = end - pos
        if size < header or pos + size > end:
            raise ValueError(f"bad MP4 box {kind!r} at {pos}")
        yield kind, pos, size, header
        pos += size


def is_faststart(data):
    order = [k for k, *_ in boxes(data)]
    if b"moov" not in order or b"mdat" not in order:
        raise ValueError("MP4 has no moov or mdat box")
    return order.index(b"moov") < order.index(b"mdat")


def _shift_offsets(moov, shift, lo, hi):
    """Add shift to every chunk offset that points into [lo, hi), the bytes that move."""
    moov = bytearray(moov)

    def walk(start, end):
        for kind, pos, size, header in boxes(moov, start, end):
            if kind in CONTAINERS:
                walk(pos + header, pos + size)
            elif kind in (b"stco", b"co64"):
                count = struct.unpack_from(">I", moov, pos + header + 4)[0]
                base = pos + header + 8
                fmt, width = (">I", 4) if kind == b"stco" else (">Q", 8)
                for i in range(count):
                    value = struct.unpack_from(fmt, moov, base + i * width)[0]
                    if lo <= value < hi:
                        value += shift
                    if kind == b"stco" and value > 0xFFFFFFFF:
                        raise ValueError("stco offset overflow; file too large for 32-bit chunk offsets")
                    struct.pack_into(fmt, moov, base + i * width, value)

    walk(8 if struct.unpack_from(">I", moov, 0)[0] != 1 else 16, len(moov))
    return bytes(moov)


def faststart_bytes(data):
    """Return the fast-start version of data (or data itself when it already is)."""
    if is_faststart(data):
        return data
    top = list(boxes(data))
    moov = next(b for b in top if b[0] == b"moov")
    first_mdat = next(i for i, b in enumerate(top) if b[0] == b"mdat")
    moov_bytes = data[moov[1]: moov[1] + moov[2]]
    # The bytes from the first mdat up to the old moov position move back by the moov size.
    moov_bytes = _shift_offsets(moov_bytes, moov[2], top[first_mdat][1], moov[1])
    head = [data[o: o + s] for k, o, s, _ in top[:first_mdat]]
    tail = [data[o: o + s] for k, o, s, _ in top[first_mdat:] if k != b"moov"]
    return b"".join(head + [moov_bytes] + tail)


def faststart_file(path):
    """Rewrite path in place for fast start. Return True when it changed the file."""
    with open(path, "rb") as f:
        data = f.read()
    out = faststart_bytes(data)
    if out is data:
        return False
    tmp = path + ".faststart.tmp"
    with open(tmp, "wb") as f:
        f.write(out)
    os.replace(tmp, path)
    return True


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(("rewrote " if faststart_file(p) else "already fast start: ") + p)
