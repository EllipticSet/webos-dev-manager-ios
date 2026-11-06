#!/usr/bin/python3
"""Builds the fake TV's installed-app list and draws a plain icon for each app."""
import json, os, struct, sys, zlib

source, root = sys.argv[1:3]


def png(hex_color, size=96):
    pixel = bytes.fromhex(hex_color)
    raw = b"".join(b"\0" + pixel * size for _ in range(size))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


apps = []
for app in json.load(open(source)):
    folder = f"{root}/home/apps/{app['id']}"
    os.makedirs(folder, exist_ok=True)
    with open(f"{folder}/icon.png", "wb") as f:
        f.write(png(app.pop("color")))
    apps.append({**app, "type": "web", "folderPath": folder, "icon": "icon.png"})
json.dump(apps, open(f"{root}/default_apps.json", "w"), indent=2)
