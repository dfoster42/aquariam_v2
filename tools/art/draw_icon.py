#!/usr/bin/env python3
"""Draw the app icon and the iOS size set.

Deterministic, drawn rather than generated, for the same reason as the backdrop: an
icon is geometry. Shares the tank's palette so the icon and the app look related.

    python3 tools/art/draw_icon.py --out-dir build/ios_icons
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

# Every size the iOS exporter asks for, plus the project icon.
# Exactly the sizes Godot 4.6's iOS exporter asks for. Read out of the engine binary
# rather than guessed: an older, smaller set is widely documented and it is wrong for
# 4.6, which drops ipad_76x76 and adds ios_128/136/192 and notification_114.
IOS_SIZES = [40, 58, 60, 76, 80, 87, 114, 120, 128, 136, 152, 167, 180, 192, 1024]

WATER_TOP = (10, 32, 52)
WATER_BOTTOM = (24, 74, 100)
BODY = (240, 120, 34)
BAND = (246, 248, 250)
INK = (14, 26, 38)


def draw(size: int = 1024) -> Image.Image:
    s = size
    image = Image.new("RGB", (s, s), WATER_TOP)
    d = ImageDraw.Draw(image)
    for y in range(s):
        t = y / max(1, s - 1)
        d.line([(0, y), (s, y)], fill=tuple(
            int(round(WATER_TOP[i] + (WATER_BOTTOM[i] - WATER_TOP[i]) * t)) for i in range(3)))

    # One clownfish, facing left, filling the middle — the app's own subject.
    cx, cy = s * 0.46, s * 0.50
    bw, bh = s * 0.30, s * 0.20
    outline = max(2, int(s * 0.012))

    # Tail first so the body overlaps its root.
    d.polygon([(cx + bw * 0.75, cy), (cx + bw * 1.5, cy - bh * 0.75),
               (cx + bw * 1.35, cy), (cx + bw * 1.5, cy + bh * 0.75)],
              fill=BODY, outline=INK, width=outline)
    d.ellipse([cx - bw, cy - bh, cx + bw, cy + bh], fill=BODY, outline=INK, width=outline)

    # Two white bands, clipped to the body. Drawn unclipped they poke past the outline
    # as small white nubs at the top and bottom of the fish.
    bands = Image.new("RGB", (s, s), BODY)
    bd = ImageDraw.Draw(bands)
    for offset, width in ((-0.34, 0.13), (0.28, 0.11)):
        band_x = cx + bw * offset
        half = bw * width
        bd.ellipse([band_x - half, cy - bh, band_x + half, cy + bh], fill=BAND)

    mask = Image.new("L", (s, s), 0)
    inset = outline * 0.5
    ImageDraw.Draw(mask).ellipse(
        [cx - bw + inset, cy - bh + inset, cx + bw - inset, cy + bh - inset], fill=255)
    image.paste(bands, (0, 0), mask)
    d.ellipse([cx - bw, cy - bh, cx + bw, cy + bh], outline=INK, width=outline)

    eye = s * 0.028
    d.ellipse([cx - bw * 0.72 - eye, cy - bh * 0.30 - eye,
               cx - bw * 0.72 + eye, cy - bh * 0.30 + eye], fill=BAND, outline=INK, width=max(1, outline // 2))
    d.ellipse([cx - bw * 0.72 - eye * 0.45, cy - bh * 0.30 - eye * 0.45,
               cx - bw * 0.72 + eye * 0.45, cy - bh * 0.30 + eye * 0.45], fill=INK)
    return image


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    master = draw(1024)
    for size in IOS_SIZES:
        path = args.out_dir / f"icon_{size}.png"
        (master if size == 1024 else master.resize((size, size), Image.LANCZOS)).save(path)
    # iOS tinted icons are composited from a greyscale image; handing it the colour one
    # produces a muddy tile on the home screen.
    master.convert("L").convert("RGB").save(args.out_dir / "icon_1024_tinted.png")
    print(f"{len(IOS_SIZES) + 1} icons -> {args.out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
