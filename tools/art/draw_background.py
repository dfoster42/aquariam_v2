#!/usr/bin/env python3
"""Draw the tank backdrop directly, without a generative model.

The backdrop is flat scenery — graded water, a sculpted sea floor, rocks and kelp —
which is a shape language a drawing library expresses exactly and a prompt only
approximates. The source pipeline's rule was that geometry is arithmetic, not
adjectives; a backdrop is almost entirely geometry, so none of it is left to a render.
It also costs no image-generation quota, which the fish sprites need.

Deterministic: the same seed always draws the same map.

    python3 tools/art/draw_background.py --out build/background.jpg --width 3240 --height 2160

Rules that came from drawing it wrong first:

* **Everything below the waterline is a silhouette.** Giving the sand, rocks and weed
  their own local colour reproduced exactly the contrast problem the original
  photograph had. Scenery is drawn as progressively darker, bluer shapes; the contrast
  in the frame belongs to the fish.
* **Banded water reads as stripes.** Four flat rectangles with a small blur left four
  visible seams. The water is a per-row gradient.
* **The floor needs relief, not a line.** A single wavy edge across the bottom reads as
  a hem. The floor is a heightmap with shelves and ravines cut into it, so panning
  across the map actually shows something.

ImageDraw does not antialias, so everything is drawn at SUPERSAMPLE times the final size
and reduced with Lanczos; at final size every blade of kelp has stepped diagonals.
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

SUPERSAMPLE = 2

WATER_TOP = (8, 28, 46)
WATER_BOTTOM = (22, 68, 92)

# Silhouettes, tinted toward the water they sit in so distance reads as haze.
FLOOR_FAR = (24, 52, 68)
FLOOR_NEAR = (19, 38, 50)
FLOOR_CREST = (38, 64, 78)
# Rocks must be darker than the floor they stand on, or they read as pale slabs lying on
# top of it. The far ones are also drawn BEFORE the near floor so it occludes their feet
# and they sit *in* the landscape rather than on it.
ROCK_FAR = (21, 44, 58)
ROCK_NEAR = (12, 28, 38)
# What a ravine shows. Without it the cuts revealed the lighter far ridge behind and
# read as pale spikes hanging in the landscape rather than as notches carved into it.
DEEP = (10, 22, 32)
KELP_FAR = (20, 58, 68)
KELP_NEAR = (12, 40, 46)
CORAL = (28, 44, 62)

# Where the floor sits, as a fraction of height: its highest crest and its lowest trough.
FLOOR_HIGH = 0.46
FLOOR_LOW = 0.94


def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


# Cuts at fixed fractions of the width, so panning reliably finds them.
# (centre, half-width, depth). Wide and shallow: the first pass used 0.03-wide cuts
# 0.55-0.75 deep and they drew as black needles running off the bottom of the frame —
# cracks rather than canyons, and nothing a fish could swim into.
RAVINES = ((0.22, 0.085, 0.34), (0.58, 0.070, 0.40), (0.83, 0.095, 0.28))


def terrain_level(x: float, w: int, rng_seed: int) -> float:
    """The landform at a given x, before anything is carved into it, 0..1.

    Deliberately analytic rather than sampled from noise — a floor built from noise
    wobbles at pixel scale and reads as texture rather than landscape.
    """
    t = x / max(1.0, w)
    base = (0.52 * math.sin(t * math.tau * 1.1 + rng_seed)
            + 0.30 * math.sin(t * math.tau * 2.7 + rng_seed * 2.0)
            + 0.18 * math.sin(t * math.tau * 5.3 + rng_seed * 3.0))
    return (base + 1.0) * 0.5


def ravine_depth(x: float, w: int) -> float:
    """How far the floor is cut away at a given x, in level units."""
    t = x / max(1.0, w)
    cut = 0.0
    for centre, width, depth in RAVINES:
        d = abs(t - centre) / width
        if d < 1.0:
            # Smoothstep rather than a squared falloff: squared comes to a point at the
            # bottom, which is what made these read as needles.
            cut += depth * (1.0 - (d * d * (3.0 - 2.0 * d)))
    return cut


def floor_height(x: float, w: int, h: int, rng_seed: int, carved: bool = True) -> float:
    """The sea floor's y at a given x. `carved` includes the ravines cut into it."""
    level = terrain_level(x, w, rng_seed)
    if carved:
        level += ravine_depth(x, w)
    level = min(max(level, 0.0), 1.35)
    return h * (FLOOR_HIGH + (FLOOR_LOW - FLOOR_HIGH) * level)


def draw(width: int, height: int, seed: int = 7) -> Image.Image:
    rng = random.Random(seed)
    w, h = width * SUPERSAMPLE, height * SUPERSAMPLE
    image = Image.new("RGB", (w, h), WATER_TOP)
    _water(image, w, h)

    # Back to front. Far rocks go before the near floor so their bases are buried.
    _kelp(image, rng, w, h, stands=int(w / 520), near=False)
    _far_floor(image, w, h, seed)
    _rocks(image, rng, w, h, seed, far=True)
    _deep(image, w, h, seed)
    _near_floor(image, w, h, seed)
    _rocks(image, rng, w, h, seed, far=False)
    _kelp(image, rng, w, h, stands=int(w / 420), near=True)
    _corals(image, rng, w, h, seed)

    return image.resize((width, height), Image.LANCZOS)


def _water(image, w, h):
    d = ImageDraw.Draw(image)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=_lerp(WATER_TOP, WATER_BOTTOM, t * t))


def _far_floor(image, w, h, seed):
    """A hazier ridge behind, offset and lifted so it reads as distance."""
    d = ImageDraw.Draw(image)
    step = max(2, w // 900)
    far = [(x, floor_height(x + w * 0.09, w, h, seed) - h * 0.085) for x in range(0, w + step, step)]
    d.polygon([(0.0, float(h))] + far + [(float(w), float(h))], fill=FLOOR_FAR)


def _deep(image, w, h, seed):
    """Darkness filling the landform before the ravines are cut, so a cut reveals depth
    rather than the pale ridge standing behind it."""
    d = ImageDraw.Draw(image)
    step = max(2, w // 900)
    lip = [(x, floor_height(x, w, h, seed, carved=False) - h * 0.004)
           for x in range(0, w + step, step)]
    d.polygon([(0.0, float(h))] + lip + [(float(w), float(h))], fill=DEEP)


def _near_floor(image, w, h, seed):
    d = ImageDraw.Draw(image)
    step = max(2, w // 900)
    near = [(x, floor_height(x, w, h, seed)) for x in range(0, w + step, step)]
    d.polygon([(0.0, float(h))] + near + [(float(w), float(h))], fill=FLOOR_NEAR)
    d.line(near, fill=FLOOR_CREST, width=max(1, int(h * 0.0018)), joint="curve")


def _mound(d, cx, cy, rw, rh, rng, colour):
    """A rounded boulder sitting ON the ground line — no skirt below it."""
    points = []
    steps = 34
    for i in range(steps + 1):
        a = math.pi + math.pi * i / steps
        wobble = 1.0 + math.sin(i * 1.7 + rng.random()) * 0.05
        points.append((cx + math.cos(a) * rw * wobble, cy + math.sin(a) * rh * wobble))
    points.append((cx + rw, cy))
    d.polygon(points, fill=colour)


def _rocks(image, rng, w, h, seed, far: bool):
    d = ImageDraw.Draw(image)
    for _ in range(int(w / (420 if far else 340))):
        cx = rng.uniform(0, w)
        scale = rng.uniform(0.6, 1.4)
        rw = w * 0.022 * scale
        rh = h * 0.026 * scale
        offset = -h * 0.075 if far else rng.uniform(0.0, h * 0.02)
        cy = floor_height(cx + (w * 0.09 if far else 0.0), w, h, seed, carved=False) + offset
        _mound(d, cx, cy, rw, rh, rng, ROCK_FAR if far else ROCK_NEAR)


def _blade(d, base_x, base_y, height, lean, half, colour):
    """One curved, tapering blade. Straight spikes read as grass, not kelp."""
    tip_x = base_x + lean * height
    ctrl_x = base_x + lean * height * 0.25
    ctrl_y = base_y - height * 0.6
    left, right = [], []
    steps = 18
    for i in range(steps + 1):
        t = i / steps
        mt = 1.0 - t
        x = mt * mt * base_x + 2 * mt * t * ctrl_x + t * t * tip_x
        y = mt * mt * base_y + 2 * mt * t * ctrl_y + t * t * (base_y - height)
        taper = half * (1.0 - t) ** 0.8
        left.append((x - taper, y))
        right.append((x + taper, y))
    d.polygon(left + list(reversed(right)), fill=colour)


def _kelp(image, rng, w, h, stands, near):
    """Stands of kelp rooted on the floor, some tall enough to reach midwater.

    Stands, with gaps between them. Scattering blades evenly across the width drew a
    continuous wall of grass — the map had no open water to swim through and no reason
    to pan anywhere in particular.
    """
    d = ImageDraw.Draw(image)
    colour = KELP_NEAR if near else KELP_FAR
    seed = 7
    for _ in range(stands):
        root_x = rng.uniform(0, w)
        # Rooted on the landform, not in mid-air over a ravine.
        root_y = floor_height(root_x, w, h, seed, carved=False) + rng.uniform(-h * 0.004, h * 0.015)
        # A stand, not a lone blade: a few blades from nearly the same root.
        for _ in range(rng.randint(3, 7)):
            tall = rng.random() < 0.28
            blade_h = h * (rng.uniform(0.22, 0.42) if tall else rng.uniform(0.06, 0.18))
            if not near:
                blade_h *= 0.85
            _blade(
                d,
                base_x=root_x + rng.uniform(-w * 0.006, w * 0.006),
                base_y=root_y,
                height=blade_h,
                lean=rng.uniform(-0.28, 0.28),
                half=w * rng.uniform(0.0016, 0.0034) * (1.0 if near else 0.8),
                colour=colour,
            )


def _corals(image, rng, w, h, seed):
    d = ImageDraw.Draw(image)
    for _ in range(int(w / 420)):
        cx = rng.uniform(0, w)
        cy = floor_height(cx, w, h, seed, carved=False) + h * 0.012
        for _ in range(rng.randint(4, 8)):
            lobe_x = cx + rng.uniform(-w * 0.012, w * 0.012)
            lobe_y = cy - rng.uniform(0.0, h * 0.018)
            rx = w * rng.uniform(0.004, 0.008)
            ry = h * rng.uniform(0.008, 0.016)
            _mound(d, lobe_x, lobe_y + ry, rx, ry * 1.5, rng, CORAL)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--width", type=int, default=3240)
    parser.add_argument("--height", type=int, default=2160)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    image = draw(args.width, args.height, args.seed)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    if args.out.suffix.lower() in (".jpg", ".jpeg"):
        image.save(args.out, quality=86, optimize=True, progressive=True)
    else:
        image.save(args.out, optimize=True)
    print(f"{args.out}  {image.width}x{image.height}  {args.out.stat().st_size / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
