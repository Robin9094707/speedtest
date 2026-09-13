#!/usr/bin/env python3
"""Render the app's vector-style gauge icon with only Python's standard library."""
from pathlib import Path
import json
import math
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1] / "Speedtest/Resources/Assets.xcassets"
folder = ROOT / "AppIcon.appiconset"
folder.mkdir(parents=True, exist_ok=True)
ROOT.joinpath("Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
folder.joinpath("Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2))


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


rows = bytearray()
for y in range(1024):
    rows.append(0)
    for x in range(1024):
        dx, dy = x - 512, y - 495
        distance = math.hypot(dx, dy)
        angle = math.degrees(math.atan2(dy, dx)) % 360
        sweep = (angle - 135) % 360
        glow = math.exp(-((x - 780)**2 + (y - 150)**2) / 260000)
        r, g, b = 7 + 12 * glow, 14 + 39 * glow, 29 + 47 * glow
        # Recessed glass dial and a bright cyan-to-violet sweep.
        if distance < 378:
            sheen = max(0, 1 - distance / 378)
            r += 4 + 4 * sheen; g += 9 + 7 * sheen; b += 15 + 9 * sheen
        if abs(distance - 359) < 2:
            r, g, b = 62, 82, 103
        if sweep <= 270 and abs(distance - 311) < 17:
            t = sweep / 270
            r, g, b = 42 + 145 * t, 222 - 75 * t, 250
        if sweep <= 270 and 261 < distance < 277 and abs(sweep / 27 - round(sweep / 27)) < 0.055:
            r, g, b = 155, 183, 204
        # Needle pointing to ~800 Mbit/s on the 270 degree scale.
        a = math.radians(351)
        along = dx * math.cos(a) + dy * math.sin(a)
        across = abs(-dx * math.sin(a) + dy * math.cos(a))
        if 0 <= along <= 245 and across < 14 * (1 - along / 280):
            r, g, b = 192, 246, 255
        if distance < 31:
            r, g, b = (207, 251, 255) if distance < 19 else (48, 108, 132)
        # Three minimal bars: the app's small signature below the dial.
        if 772 < y < 800 and (428 < x < 468 or 492 < x < 532 or 556 < x < 596):
            r, g, b = 102, 216, 237
        rows.extend((int(min(255, r)), int(min(255, g)), int(min(255, b))))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1024, 1024, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
folder.joinpath("AppIcon.png").write_bytes(png)
print("Rendered opaque 1024px AppIcon.png")
