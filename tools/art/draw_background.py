#!/usr/bin/env python3
"""Draw the tank backdrop directly, without a generative model.

The backdrop is flat scenery — graded water, a sand floor, rounded rocks and seaweed —
which is a shape language a drawing library expresses exactly and a prompt only
approximates. The source pipeline's rule was that geometry is arithmetic, not
adjectives; a backdrop is almost entirely geometry, so none of it is left to a render.
It also costs no image-generation quota, which the fish sprites need.

Deterministic: the same seed always draws the same backdrop.

    python3 tools/art/draw_background.py --out /tmp/aquarium-art/staged/background.jpg

Two things learned by drawing it wrong first:

* **Everything below the waterline is a silhouette.** The first attempt gave the sand,
  rocks and weed their own local colour and the result fought the fish exactly as the
  photograph had. Scenery is now drawn as progressively darker, bluer shapes — the
  contrast in the frame belongs to the fish.
* **Banded water reads as stripes.** Four flat rectangles with a small blur left four
  visible seams. The water is a per-row gradient instead, which is free here and is the
  one thing a flat-fill approach cannot fake.

ImageDraw does not antialias, so everything is drawn at SUPERSAMPLE times the final size
and reduced with Lanczos; at final size every blade of weed has stepped diagonals.
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

WIDTH, HEIGHT = 1080, 1920
SUPERSAMPLE = 3

# Water, top to bottom. Deliberately narrow in range: a backdrop that travels far in
# value has somewhere in it that matches any given fish.
WATER_TOP = (8, 28, 46)
WATER_BOTTOM = (22, 68, 92)

# Everything below the waterline is a silhouette, tinted toward the water it sits in so
# distance reads as haze rather than as a different palette.
SAND = (38, 62, 74)
# Only a few values above the sand: at (58, 88, 100) this drew as a bright squiggle
# across the open middle and read as a stray mark rather than as a lit edge.
SAND_CREST = (46, 72, 84)
ROCK_NEAR = (14, 34, 46)
ROCK_FAR = (24, 52, 68)
WEED_NEAR = (12, 40, 46)
WEED_FAR = (20, 58, 68)
CORAL = (28, 44, 62)

FLOOR_Y = 0.86
# Scenery stays out of this horizontal band, so midwater always has plain ground behind
# it. Fractions of the width.
CLEAR_LEFT, CLEAR_RIGHT = 0.34, 0.66


def _lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def draw(seed: int = 7) -> Image.Image:
    rng = random.Random(seed)
    w, h = WIDTH * SUPERSAMPLE, HEIGHT * SUPERSAMPLE
    image = Image.new("RGB", (w, h), WATER_TOP)
    _water(image, w, h)

    # Back to front: far weed hazes into the water, then the floor, then rocks, then
    # near weed and coral in front of them.
    _weeds(image, rng, w, h, count=34, near=False)
    _floor(image, rng, w, h)
    _rocks(image, rng, w, h)
    _weeds(image, rng, w, h, count=30, near=True)
    _corals(image, rng, w, h)

    return image.resize((WIDTH, HEIGHT), Image.LANCZOS)


def _water(image: Image.Image, w: int, h: int) -> None:
    """A per-row vertical gradient. Rectangular bands leave visible seams."""
    d = ImageDraw.Draw(image)
    for y in range(h):
        t = y / max(1, h - 1)
        # Eased so most of the change happens low in the frame, leaving the top calm.
        d.line([(0, y), (w, y)], fill=_lerp(WATER_TOP, WATER_BOTTOM, t * t))


def _floor(image: Image.Image, rng: random.Random, w: int, h: int) -> None:
    """Sand across the bottom with a soft wavy crest."""
    d = ImageDraw.Draw(image)
    base = h * FLOOR_Y
    crest = [(0.0, base)]
    x = 0.0
    while x <= w:
        y = (base
             + math.sin(x / w * math.pi * 2.4) * h * 0.010
             + math.sin(x / w * math.pi * 7.3) * h * 0.004
             + rng.uniform(-h * 0.002, h * 0.002))
        crest.append((x, y))
        x += w / 90.0
    crest.append((float(w), base))
    d.polygon([(0.0, float(h))] + crest + [(float(w), float(h))], fill=SAND)
    d.line(crest[1:-1], fill=SAND_CREST, width=max(1, int(h * 0.0014)), joint="curve")


def _mound(d: ImageDraw.ImageDraw, cx: float, cy: float, rw: float, rh: float,
           rng: random.Random, colour: tuple[int, int, int]) -> None:
    """A rounded boulder sitting ON the ground line — no skirt below it.

    The first version closed the arc with two corner points, which drew a box under
    every rock.
    """
    points = []
    steps = 40
    for i in range(steps + 1):
        a = math.pi + math.pi * i / steps
        wobble = 1.0 + math.sin(i * 1.7 + rng.random()) * 0.045
        points.append((cx + math.cos(a) * rw * wobble, cy + math.sin(a) * rh * wobble))
    points.append((cx + rw, cy))
    d.polygon(points, fill=colour)


def _rocks(image: Image.Image, rng: random.Random, w: int, h: int) -> None:
    d = ImageDraw.Draw(image)
    for cx_frac, scale, far in [
        (0.07, 1.25, False), (0.22, 0.85, True), (0.30, 0.6, False),
        (0.72, 0.75, True), (0.84, 1.2, False), (0.96, 0.9, False),
        (0.50, 0.5, True),
    ]:
        cx = w * cx_frac
        rw = w * 0.16 * scale
        rh = h * 0.052 * scale
        cy = h * (FLOOR_Y + rng.uniform(0.005, 0.03))
        _mound(d, cx, cy, rw, rh, rng, ROCK_FAR if far else ROCK_NEAR)


def _blade(d: ImageDraw.ImageDraw, base_x: float, base_y: float, height: float,
           lean: float, half: float, colour: tuple[int, int, int]) -> None:
    """One curved, tapering blade, sampled from a quadratic bezier.

    Straight spikes read as grass or as needles; the curve is what makes it seaweed.
    """
    tip_x = base_x + lean * height
    ctrl_x = base_x + lean * height * 0.25
    ctrl_y = base_y - height * 0.6
    left, right = [], []
    steps = 16
    for i in range(steps + 1):
        t = i / steps
        mt = 1.0 - t
        x = mt * mt * base_x + 2 * mt * t * ctrl_x + t * t * tip_x
        y = mt * mt * base_y + 2 * mt * t * ctrl_y + t * t * (base_y - height)
        taper = half * (1.0 - t) ** 0.8
        left.append((x - taper, y))
        right.append((x + taper, y))
    d.polygon(left + list(reversed(right)), fill=colour)


def _weeds(image: Image.Image, rng: random.Random, w: int, h: int,
           count: int, near: bool) -> None:
    d = ImageDraw.Draw(image)
    colour = WEED_NEAR if near else WEED_FAR
    placed = 0
    attempts = 0
    while placed < count and attempts < count * 12:
        attempts += 1
        x = rng.uniform(0.0, 1.0)
        if CLEAR_LEFT < x < CLEAR_RIGHT:
            continue
        # Shorter as they approach the clear band, so the middle opens gradually
        # instead of ending at a visible wall of weed.
        gap = min(abs(x - CLEAR_LEFT), abs(x - CLEAR_RIGHT))
        height = h * rng.uniform(0.09, 0.26) * min(1.0, 0.35 + gap * 3.0)
        if not near:
            height *= 0.8
        _blade(
            d,
            base_x=w * x,
            base_y=h * rng.uniform(FLOOR_Y - 0.005, FLOOR_Y + 0.035),
            height=height,
            lean=rng.uniform(-0.32, 0.32),
            half=w * rng.uniform(0.005, 0.011) * (1.0 if near else 0.8),
            colour=colour,
        )
        placed += 1


def _corals(image: Image.Image, rng: random.Random, w: int, h: int) -> None:
    """Low soft-coral mounds. Kept nearly the rocks' value — the first attempt made
    these bright violet and they became the brightest thing in the frame."""
    d = ImageDraw.Draw(image)
    for cx_frac in (0.15, 0.88):
        cx = w * cx_frac
        cy = h * (FLOOR_Y + 0.02)
        for _ in range(7):
            lobe_x = cx + rng.uniform(-w * 0.05, w * 0.05)
            lobe_y = cy - rng.uniform(0.0, h * 0.03)
            rx = w * rng.uniform(0.018, 0.032)
            ry = h * rng.uniform(0.010, 0.020)
            _mound(d, lobe_x, lobe_y + ry, rx, ry * 1.6, rng, CORAL)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    image = draw(args.seed)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    if args.out.suffix.lower() in (".jpg", ".jpeg"):
        image.save(args.out, quality=88, optimize=True, progressive=True)
    else:
        image.save(args.out, optimize=True)
    print(f"{args.out}  {image.width}x{image.height}  {args.out.stat().st_size / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
