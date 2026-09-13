#!/usr/bin/env python3
"""Key a generated JPEG onto a real alpha channel, then trim and scale it.

`generate.py` can only return JPEG, so the render arrives with no transparency. The
sprout-party pipeline solved that by flood-filling a near-white background and snapping
everything else onto a four-tone palette. Neither half transfers here:

* **Luminance cannot separate these subjects.** That pipeline drew one hue family
  (green plants) on a pale ground, so a brightness threshold was enough. A tank holds a
  near-white belly, a mid-grey shark and a black-and-orange clownfish; any luma cut that
  removes the background removes part of a fish too.
* **The palette must stay open.** Snapping to a fixed ramp is what makes a plant
  catalogue coherent. Fish species differ *by* colour, so the tones have to survive.

So the background is keyed on chroma instead: the brief asks for flat magenta, which the
model draws reliably, and which no fish in the catalogue comes near on any channel. That
is the sprout-party soil-marker trick — "unambiguous by construction rather than by
threshold" — applied to the whole background rather than one bar.

Reachability still does the real work: the fill enters from the border and stops at the
fish's dark outline, so a magenta-ish pixel *inside* the art is never touched.
"""

from __future__ import annotations

import argparse
import sys
from collections import deque
from pathlib import Path

from PIL import Image

# How magenta a pixel is: high red and blue, low green. Pure #FF00FF scores 255.
# White, black and mid-grey all score 0; orange and blue score negative. The widest
# separation available from a single subtraction.
KEY_STRONG = 70
# The JPEG edge between magenta and outline is a ramp. The first pass stops partway
# down it and leaves a pink fringe, so the mask's own edge is re-seeded at a looser
# threshold — the same two-pass shape sprout-party needed around its soil marker.
KEY_WEAK = 24
# Below this, despill leaves the pixel alone; above it, red and blue are pulled back
# toward green. Without this every fish ships with a pink rim.
DESPILL_FLOOR = 8
# How far from the keyed background despill is allowed to reach, in pixels.
#
# Despill must NOT be applied to the whole subject. A maroon anemonefish body is around
# (140, 30, 60), which scores +30 on the magenta test and was crushed to (38, 30, 38) —
# the fish came out solid black and the judge, having nothing to compare against,
# reported it as a "black anemonefish" and passed every colour-related item. Only the
# JPEG ramp along the silhouette is really contaminated, and it is only a few pixels
# wide, so that is all despill is allowed to touch.
DESPILL_REACH = 3


def keyness(r: int, g: int, b: int) -> int:
    return min(r, b) - g


def background_mask(px: list[tuple[int, int, int]], w: int, h: int) -> bytearray:
    """Flood fill the magenta ground inward from the border."""
    mask = bytearray(w * h)
    queue: deque[int] = deque()

    def consider(i: int, threshold: int) -> None:
        if mask[i]:
            return
        if keyness(*px[i]) < threshold:
            return
        mask[i] = 1
        queue.append(i)

    def drain(threshold: int) -> None:
        while queue:
            i = queue.popleft()
            x, y = i % w, i // w
            if x > 0:
                consider(i - 1, threshold)
            if x < w - 1:
                consider(i + 1, threshold)
            if y > 0:
                consider(i - w, threshold)
            if y < h - 1:
                consider(i + w, threshold)

    for x in range(w):
        consider(x, KEY_STRONG)
        consider((h - 1) * w + x, KEY_STRONG)
    for y in range(h):
        consider(y * w, KEY_STRONG)
        consider(y * w + (w - 1), KEY_STRONG)
    drain(KEY_STRONG)

    for i in range(w * h):
        if mask[i]:
            queue.append(i)
    drain(KEY_WEAK)
    return mask


def despill(r: int, g: int, b: int) -> tuple[int, int, int]:
    """Pull residual magenta out of a surviving pixel without shifting its hue."""
    excess = keyness(r, g, b)
    if excess <= DESPILL_FLOOR:
        return r, g, b
    ceiling = g + DESPILL_FLOOR
    return min(r, ceiling), g, min(b, ceiling)


def despill_image(image: Image.Image) -> Image.Image:
    """Run despill over a whole RGBA image, in place of a per-pixel call site.

    Needed a second time after any resize: Lanczos has negative lobes, and its
    overshoot on the hard alpha edge pushes red and blue past their inputs while
    green sits at zero, reintroducing magenta the first pass had already removed.
    """
    raw = bytearray(image.convert("RGBA").tobytes())
    for i in range(0, len(raw), 4):
        # Only the soft alpha edge. Ringing happens where the resize blended against
        # transparency; a fully opaque interior pixel is the artist's colour and must
        # not be touched.
        if not 0 < raw[i + 3] < 250:
            continue
        raw[i], raw[i + 1], raw[i + 2] = despill(raw[i], raw[i + 1], raw[i + 2])
    return Image.frombytes("RGBA", image.size, bytes(raw))


def near_background(mask: bytearray, w: int, h: int, reach: int) -> bytearray:
    """Pixels within `reach` of the keyed background — the only ones despill may touch."""
    band = bytearray(mask)
    for _ in range(reach):
        grown = bytearray(band)
        for i in range(w * h):
            if band[i]:
                continue
            x, y = i % w, i // w
            if ((x > 0 and band[i - 1]) or (x < w - 1 and band[i + 1])
                    or (y > 0 and band[i - w]) or (y < h - 1 and band[i + w])):
                grown[i] = 1
        band = grown
    return band


def cut(image: Image.Image) -> Image.Image:
    rgb = image.convert("RGB")
    w, h = rgb.size
    raw = rgb.tobytes()
    px = [(raw[i], raw[i + 1], raw[i + 2]) for i in range(0, len(raw), 3)]
    mask = background_mask(px, w, h)
    edge = near_background(mask, w, h, DESPILL_REACH)

    out = bytearray(w * h * 4)
    for i, pixel in enumerate(px):
        if mask[i]:
            continue
        colour = despill(*pixel) if edge[i] else pixel
        out[i * 4 : i * 4 + 4] = bytes((*colour, 255))
    return Image.frombytes("RGBA", (w, h), bytes(out))


def subject_mean(pixels: list[tuple[int, int, int]]) -> tuple[float, float, float]:
    chosen = [p for p in pixels if keyness(*p) < KEY_STRONG]
    if not chosen:
        return (0.0, 0.0, 0.0)
    return tuple(sum(c[i] for c in chosen) / len(chosen) for i in range(3))


def colour_drift(source: Image.Image, result: Image.Image) -> float:
    """How far the subject's mean colour moved, 0-255 per channel, worst channel.

    A guard against the keyer eating the art rather than the background. Despill once
    ran over every opaque pixel, which crushed a maroon fish to near-black; the judge
    looked at the result, had nothing to compare it with, and passed every colour item.
    A number catches what a second opinion cannot.
    """
    before = subject_mean([tuple(p) for p in source.convert("RGB").get_flattened_data()])
    opaque = [(p[0], p[1], p[2]) for p in result.convert("RGBA").get_flattened_data() if p[3] > 200]
    if not opaque:
        return 0.0
    after = tuple(sum(c[i] for c in opaque) / len(opaque) for i in range(3))
    return max(abs(before[i] - after[i]) for i in range(3))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument(
        "--max-drift",
        type=float,
        default=12.0,
        help="Fail if the subject's mean colour moves more than this per channel.",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=0,
        help="Scale the trimmed result to this pixel height, preserving aspect. "
        "Lanczos softens the hard alpha edge into a usable one, so scale here rather "
        "than feathering by hand.",
    )
    args = parser.parse_args()

    source = Image.open(args.source)
    result = cut(source)
    drift = colour_drift(source, result)
    if drift > args.max_drift:
        sys.stderr.write(
            f"{args.source}: keying shifted the subject's mean colour by {drift:.1f} "
            f"per channel (limit {args.max_drift}). The key is eating the art, not the "
            f"background.\n")
        return 1
    box = result.getbbox()
    if box is None:
        sys.stderr.write(f"{args.source}: keyed to nothing — the render is all background\n")
        return 1
    # Trim to drawn content so a sprite's declared size is the fish, not the canvas.
    result = result.crop(box)

    if args.height and result.height != args.height:
        width = max(1, round(result.width * args.height / result.height))
        result = despill_image(result.resize((width, args.height), Image.LANCZOS))

    args.destination.parent.mkdir(parents=True, exist_ok=True)
    result.save(args.destination, optimize=True)

    opaque = sum(1 for a in result.tobytes()[3::4] if a > 8)
    total = result.width * result.height
    print(
        f"{args.destination}  {result.width}x{result.height}  "
        f"fill {opaque / total:.1%}  colour drift {drift:.1f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
