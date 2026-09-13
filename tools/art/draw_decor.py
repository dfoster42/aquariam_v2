#!/usr/bin/env python3
"""Draw placeable decor sprites.

Drawn rather than generated, for the same reason as the backdrop: a clump of kelp is
geometry, and it costs none of the image-generation quota the fish need.

    python3 tools/art/draw_decor.py --out-dir assets/textures

Decor is lighter and greener than the backdrop's silhouettes, because it sits in front
of them and has to read as a distinct object rather than as more scenery. It stays well
below the fish in saturation so it never competes with them.
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

SUPERSAMPLE = 4
INK = (14, 36, 34, 255)


def _blade(d, base, height, lean, half, colour, curve=0.6, blunt=0.0):
    """One curved blade. `blunt` keeps a minimum width at the tip — kelp comes to a
    point, but an anemone's tentacles do not, and pointed ones read as spines."""
    bx, by = base
    tip_x = bx + lean * height
    ctrl_x = bx + lean * height * 0.25
    ctrl_y = by - height * curve
    left, right = [], []
    steps = 22
    for i in range(steps + 1):
        t = i / steps
        mt = 1.0 - t
        x = mt * mt * bx + 2 * mt * t * ctrl_x + t * t * tip_x
        y = mt * mt * by + 2 * mt * t * ctrl_y + t * t * (by - height)
        taper = half * max(blunt, (1.0 - t) ** 0.7)
        left.append((x - taper, y))
        right.append((x + taper, y))
    d.polygon(left + list(reversed(right)), fill=colour, outline=INK, width=max(1, int(half * 0.22)))


def kelp(width: int = 420, height: int = 720, seed: int = 3) -> Image.Image:
    """A clump of broad kelp blades rising from a common root."""
    rng = random.Random(seed)
    w, h = width * SUPERSAMPLE, height * SUPERSAMPLE
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)

    tones = [(42, 96, 68, 255), (52, 112, 78, 255), (34, 82, 60, 255), (60, 124, 86, 255)]
    root = (w * 0.5, h * 0.985)

    blades = []
    for i in range(11):
        spread = (i - 5) / 5.0
        blades.append({
            "lean": spread * rng.uniform(0.30, 0.52),
            "height": h * rng.uniform(0.55, 0.97) * (1.0 - abs(spread) * 0.32),
            "half": w * rng.uniform(0.040, 0.072),
            "tone": tones[i % len(tones)],
            "x": root[0] + spread * w * rng.uniform(0.05, 0.12),
        })
    # Back blades first so the front ones overlap them.
    blades.sort(key=lambda b: -b["height"])
    for b in blades:
        _blade(d, (b["x"], root[1]), b["height"], b["lean"], b["half"], b["tone"])

    return image.resize((width, height), Image.LANCZOS)


def anemone(width: int = 360, height: int = 320, seed: int = 5) -> Image.Image:
    """A low anemone: a squat body with short waving tentacles."""
    rng = random.Random(seed)
    w, h = width * SUPERSAMPLE, height * SUPERSAMPLE
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)

    body = (122, 74, 96, 255)
    tips = [(158, 96, 118, 255), (138, 84, 108, 255), (172, 110, 128, 255)]
    root = (w * 0.5, h * 0.97)

    for i in range(16):
        spread = (i - 7.5) / 7.5
        _blade(
            d,
            (root[0] + spread * w * 0.28, root[1] - h * 0.10),
            h * rng.uniform(0.42, 0.72) * (1.0 - abs(spread) * 0.28),
            spread * rng.uniform(0.7, 1.15),
            w * rng.uniform(0.026, 0.042),
            tips[i % len(tips)],
            curve=0.80,
            blunt=0.45,
        )
    d.ellipse([root[0] - w * 0.30, root[1] - h * 0.22, root[0] + w * 0.30, root[1] + h * 0.10],
              fill=body, outline=INK, width=max(1, int(w * 0.010)))
    return image.resize((width, height), Image.LANCZOS)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    for name, image in (("kelp", kelp()), ("anemone", anemone())):
        path = args.out_dir / f"{name}.png"
        image.crop(image.getbbox()).save(path, optimize=True)
        final = Image.open(path)
        print(f"{path}  {final.width}x{final.height}  {path.stat().st_size / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
