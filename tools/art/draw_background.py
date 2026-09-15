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
ROCK_FAR = (22, 47, 61)
ROCK_NEAR = (12, 28, 38)
# What a ravine shows. Without it the cuts revealed the lighter far ridge behind and
# read as pale spikes hanging in the landscape rather than as notches carved into it.
DEEP = (10, 22, 32)
KELP_FAR = (20, 58, 68)
KELP_NEAR = (12, 40, 46)
CORAL = (28, 44, 62)

# Where the floor sits, as a fraction of height: its highest crest and its lowest
# trough. Deliberately close together — the floor undulates gently and has no real
# slopes.
#
# A dramatic version of this came first and looked wrong: rocks and kelp sample the
# heightmap at a single x and then draw a shape that assumes level ground beneath, so on
# any real gradient they hung in the water with nothing under them. Seating objects
# against a slope properly is issue #4; until then there are no slopes to get wrong.
FLOOR_HIGH = 0.58
FLOOR_LOW = 0.90


def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


# No ravines for now. A cut needs a dark layer behind it or it reveals the lighter far
# ridge, and its walls are the steepest ground in the map — exactly what nothing is
# seated against correctly yet. Tracked in issue #4; the machinery below still works if
# entries are put back.
# Gentler than the seating experiment that proved the fix: at 0.36-0.44 deep these read
# as slots cut in the ground with kelp growing out of a slit, not as dips in a sea bed.
RAVINES = ((0.21, 0.115, 0.20), (0.57, 0.100, 0.24), (0.85, 0.125, 0.17))


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

    # Every ground object is drawn BEFORE the floor it stands on, and buried into it.
    # The floor polygon then occludes whatever lies below the surface at every column,
    # which is what makes objects sit correctly on a slope without any of them having to
    # know the slope exists.
    def far_ground(x: float) -> float:
        return floor_height(x + w * 0.09, w, h, seed) - h * 0.035

    def near_ground(x: float) -> float:
        return floor_height(x, w, h, seed)

    _kelp(image, rng, w, h, stands=int(w / 520), near=False, ground=far_ground)
    _rocks(image, rng, w, h, far=True, rng_ground=far_ground)
    _far_floor(image, w, h, seed)

    _kelp(image, rng, w, h, stands=int(w / 420), near=True, ground=near_ground)
    _rocks(image, rng, w, h, far=False, rng_ground=near_ground)
    _corals(image, rng, w, h, near_ground)
    _near_floor(image, w, h, seed)

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
    far = [(x, floor_height(x + w * 0.09, w, h, seed) - h * 0.035) for x in range(0, w + step, step)]
    d.polygon([(0.0, float(h))] + far + [(float(w), float(h))], fill=FLOOR_FAR)


# No separate "deep" layer. One existed to stop a ravine revealing the lighter ridge
# behind it, but it filled the whole uncarved landform, so a dip showed the dark fill
# rising to the uncarved crest and read as a dark hill standing in front of the floor
# rather than as a cut into it. A dip is now simply a dip in the floor's silhouette, with
# the distant ridge visible through it — which is what looking into one would show.


def _near_floor(image, w, h, seed):
    d = ImageDraw.Draw(image)
    step = max(2, w // 900)
    near = [(x, floor_height(x, w, h, seed)) for x in range(0, w + step, step)]
    d.polygon([(0.0, float(h))] + near + [(float(w), float(h))], fill=FLOOR_NEAR)
    d.line(near, fill=FLOOR_CREST, width=max(1, int(h * 0.0018)), joint="curve")


def _mound(d, cx, rw, rh, rng, colour, ground, bury=0.9):
    """A boulder that tilts to match the ground and is buried into it.

    Three versions of this got it wrong in different ways:

    * A half-ellipse with a flat bottom at one sampled y. On any gradient one end of that
      flat bottom lifted off the ground and the rock hung in the water.
    * A crown tracing the ground column by column. That never floats, but the rock's
      height then varies with the terrain beneath it, so on a steep slope it stretches
      into a smear several times its own size.
    * This one: the ground is sampled at the rock's left and right edges only and the
      shape is tilted along that line, so it keeps its proportions on any gradient.

    The base runs a full radius below that line. It does not need to match the ground
    exactly, because the floor is drawn afterwards and occludes everything beneath the
    surface — which is what removes the last chance of a visible gap.
    """
    left = ground(cx - rw)
    right = ground(cx + rw)

    # Cap how far it can lean. Across a cliff the two samples differ by far more than
    # the rock is tall, and an unclamped tilt stretches it into a long diagonal streak.
    # A real boulder on that gradient sits at a plausible angle and is mostly buried —
    # which is what this produces, since the floor is drawn over whatever ends up below
    # the surface.
    max_lean = rh * 2.0
    drop = max(-max_lean, min(max_lean, right - left))
    centre = (left + right) * 0.5
    left, right = centre - drop * 0.5, centre + drop * 0.5

    crown = []
    steps = 30
    for i in range(steps + 1):
        a = math.pi + math.pi * i / steps
        x = cx + math.cos(a) * rw
        seat = left + (right - left) * ((x - (cx - rw)) / max(1e-6, 2.0 * rw))
        wobble = 1.0 + math.sin(i * 1.7 + rng.random()) * 0.05
        crown.append((x, seat - abs(math.sin(a)) * rh * wobble))

    base = []
    for x, _ in reversed(crown):
        seat = left + (right - left) * ((x - (cx - rw)) / max(1e-6, 2.0 * rw))
        base.append((x, seat + rh * bury))
    d.polygon(crown + base, fill=colour)


def _rocks(image, rng, w, h, far: bool, rng_ground):
    d = ImageDraw.Draw(image)
    for _ in range(int(w / (300 if far else 190))):
        cx = rng.uniform(0, w)
        scale = rng.uniform(0.6, 1.4) * (0.6 if far else 1.0)
        _mound(d, cx, w * 0.022 * scale, h * 0.026 * scale, rng,
               ROCK_FAR if far else ROCK_NEAR, rng_ground)


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


def _kelp(image, rng, w, h, stands, near, ground):
    """Stands of kelp rooted on the floor, some tall enough to reach midwater.

    Stands, with gaps between them. Scattering blades evenly across the width drew a
    continuous wall of grass — the map had no open water to swim through and no reason
    to pan anywhere in particular.
    """
    d = ImageDraw.Draw(image)
    colour = KELP_NEAR if near else KELP_FAR
    seed = 7
    placed = 0
    attempts = 0
    while placed < stands and attempts < stands * 10:
        attempts += 1
        root_x = rng.uniform(0, w)
        # Not on the steep walls of a dip: a stand rooted there grows out of a slit.
        if ravine_depth(root_x, w) > 0.05:
            continue
        placed += 1
        # A stand, not a lone blade: a few blades from nearly the same root.
        for _ in range(rng.randint(3, 7)):
            tall = rng.random() < 0.28
            blade_h = h * (rng.uniform(0.22, 0.42) if tall else rng.uniform(0.06, 0.18))
            if not near:
                blade_h *= 0.85
            # Each blade samples the ground at its OWN x and roots below it, so a stand
            # spanning a gradient follows it instead of standing on one shared level.
            blade_x = root_x + rng.uniform(-w * 0.006, w * 0.006)
            _blade(
                d,
                base_x=blade_x,
                base_y=ground(blade_x) + h * 0.02,
                height=blade_h,
                lean=rng.uniform(-0.28, 0.28),
                half=w * rng.uniform(0.0016, 0.0034) * (1.0 if near else 0.8),
                colour=colour,
            )


def _corals(image, rng, w, h, ground):
    d = ImageDraw.Draw(image)
    for _ in range(int(w / 420)):
        cx = rng.uniform(0, w)
        for _ in range(rng.randint(4, 8)):
            lobe_x = cx + rng.uniform(-w * 0.012, w * 0.012)
            rx = w * rng.uniform(0.004, 0.008)
            ry = h * rng.uniform(0.008, 0.016)
            _mound(d, lobe_x, rx, ry * 1.5, rng, CORAL, ground)


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
