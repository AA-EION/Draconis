#!/usr/bin/env python3
"""Deterministic wallpaper for the look comparison: soft colour fields like a
macOS desktop, so glass has something to refract. Pure Python (no Pillow).

usage: wallpaper.py out.png [width height]
"""
import math
import struct
import sys
import zlib


def colour(u, v):
    blobs = [  # x, y, radius, rgb
        (0.15, 0.20, 0.55, (0.20, 0.42, 0.95)),
        (0.80, 0.25, 0.50, (0.62, 0.30, 0.90)),
        (0.55, 0.85, 0.60, (0.10, 0.70, 0.80)),
        (0.95, 0.90, 0.45, (0.95, 0.45, 0.35)),
    ]
    r, g, b = 0.05, 0.06, 0.10
    for x, y, radius, rgb in blobs:
        d = math.hypot(u - x, v - y) / radius
        w = math.exp(-d * d * 2.2)
        r, g, b = r + rgb[0] * w, g + rgb[1] * w, b + rgb[2] * w
    stripe = 0.06 * math.sin(40 * (u + 0.4 * v))
    return [max(0, min(255, int((c + stripe) * 200))) for c in (r, g, b)]


def main():
    out = sys.argv[1]
    w, h = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (2560, 1600)
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            rows.extend(colour(x / w, y / h))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 6)) + chunk(b"IEND", b"")
    with open(out, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main()
