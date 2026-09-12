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
        if raw[i + 3] == 0:
            continue
        raw[i], raw[i + 1], raw[i + 2] = despill(raw[i], raw[i + 1], raw[i + 2])
    return Image.frombytes("RGBA", image.size, bytes(raw))


def cut(image: Image.Image) -> Image.Image:
    rgb = image.convert("RGB")
    w, h = rgb.size
    raw = rgb.tobytes()
    px = [(raw[i], raw[i + 1], raw[i + 2]) for i in range(0, len(raw), 3)]
    mask = background_mask(px, w, h)

    out = bytearray(w * h * 4)
    for i, pixel in enumerate(px):
        if mask[i]:
            continue
        out[i * 4 : i * 4 + 4] = bytes((*despill(*pixel), 255))
    return Image.frombytes("RGBA", (w, h), bytes(out))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument(
        "--height",
        type=int,
        default=0,
        help="Scale the trimmed result to this pixel height, preserving aspect. "
        "Lanczos softens the hard alpha edge into a usable one, so scale here rather "
        "than feathering by hand.",
    )
    args = parser.parse_args()

    result = cut(Image.open(args.source))
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
        f"{args.destination}  {result.width}x{result.height}  fill {opaque / total:.1%}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
