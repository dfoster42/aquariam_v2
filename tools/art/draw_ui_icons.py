#!/usr/bin/env python3
"""Draw the flat white UI glyphs the tank controls use.

Drawn, not generated, for the same reason as the app icon: a speaker and a pause bar
are geometry, and a generated one comes back at a different weight every time. These
are pure white on transparent so the theme can tint them — a disabled or accented
button changes `modulate` and nothing here has to know about it.

Every glyph is drawn at SUPERSAMPLE times the target and reduced with LANCZOS. PIL's
`ellipse` and `polygon` are hard-edged, and a 48px speaker drawn directly reads as a
staircase on a phone screen.

    python3 tools/art/draw_ui_icons.py
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

SIZE = 96
SUPERSAMPLE = 4
WHITE = (255, 255, 255, 255)
CLEAR = (255, 255, 255, 0)


def _canvas() -> tuple[Image.Image, ImageDraw.ImageDraw, int]:
    s = SIZE * SUPERSAMPLE
    image = Image.new("RGBA", (s, s), CLEAR)
    return image, ImageDraw.Draw(image), s


def _finish(image: Image.Image) -> Image.Image:
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def _speaker(d: ImageDraw.ImageDraw, s: int) -> None:
    """The cone, shared by both sound states so they cannot drift apart."""
    d.rectangle([s * 0.16, s * 0.38, s * 0.34, s * 0.62], fill=WHITE)
    d.polygon(
        [(s * 0.34, s * 0.40), (s * 0.55, s * 0.20), (s * 0.55, s * 0.80), (s * 0.34, s * 0.60)],
        fill=WHITE,
    )


def sound_on() -> Image.Image:
    image, d, s = _canvas()
    _speaker(d, s)
    # Two arcs rather than a filled wedge: a wedge at this size fuses into the cone.
    for radius, width in ((0.13, 0.05), (0.24, 0.05)):
        box = [
            s * (0.58 - radius), s * (0.5 - radius),
            s * (0.58 + radius), s * (0.5 + radius),
        ]
        d.arc(box, start=-55, end=55, fill=WHITE, width=int(s * width))
    return _finish(image)


def sound_off() -> Image.Image:
    image, d, s = _canvas()
    _speaker(d, s)
    d.line([(s * 0.62, s * 0.36), (s * 0.86, s * 0.64)], fill=WHITE, width=int(s * 0.06))
    d.line([(s * 0.86, s * 0.36), (s * 0.62, s * 0.64)], fill=WHITE, width=int(s * 0.06))
    return _finish(image)


def pause() -> Image.Image:
    image, d, s = _canvas()
    d.rounded_rectangle([s * 0.26, s * 0.20, s * 0.42, s * 0.80], radius=s * 0.05, fill=WHITE)
    d.rounded_rectangle([s * 0.58, s * 0.20, s * 0.74, s * 0.80], radius=s * 0.05, fill=WHITE)
    return _finish(image)


def play() -> Image.Image:
    image, d, s = _canvas()
    d.polygon([(s * 0.28, s * 0.18), (s * 0.80, s * 0.50), (s * 0.28, s * 0.82)], fill=WHITE)
    return _finish(image)


def tanks() -> Image.Image:
    """A tank, not a stack of documents.

    Two offset rounded rectangles is the universal "copy" glyph and read as exactly
    that — the switcher holds aquariums, so the glyph is one: a frame, a waterline,
    and a fish behind it.
    """
    image, d, s = _canvas()
    stroke = int(s * 0.07)
    d.rounded_rectangle(
        [s * 0.12, s * 0.20, s * 0.88, s * 0.80], radius=s * 0.10,
        outline=WHITE, width=stroke)
    # Waterline, inset so it stops short of the glass on both sides.
    d.line([(s * 0.22, s * 0.36), (s * 0.78, s * 0.36)], fill=WHITE, width=int(s * 0.05))
    d.ellipse([s * 0.28, s * 0.50, s * 0.62, s * 0.68], fill=WHITE)
    d.polygon(
        [(s * 0.60, s * 0.59), (s * 0.74, s * 0.47), (s * 0.74, s * 0.71)], fill=WHITE)
    return _finish(image)


def close() -> Image.Image:
    image, d, s = _canvas()
    d.line([(s * 0.26, s * 0.26), (s * 0.74, s * 0.74)], fill=WHITE, width=int(s * 0.085))
    d.line([(s * 0.74, s * 0.26), (s * 0.26, s * 0.74)], fill=WHITE, width=int(s * 0.085))
    return _finish(image)


def feed() -> Image.Image:
    """Falling pellets. The picker's one non-creature tool needs a glyph of its own."""
    image, d, s = _canvas()
    for cx, cy, r in ((0.30, 0.26, 0.085), (0.62, 0.40, 0.105), (0.38, 0.60, 0.070),
                      (0.68, 0.74, 0.085)):
        d.ellipse(
            [s * (cx - r), s * (cy - r), s * (cx + r), s * (cy + r)], fill=WHITE)
    return _finish(image)


def fish() -> Image.Image:
    """The population chip's glyph, facing left like the art.

    The body is a lens — the overlap of two circles — not an ellipse. An ellipse with a
    triangle stuck to it reads as a video camera at the 26px this is actually drawn at,
    and it did: two rounds of tweaking the tail did not shift it. Points at both ends
    are what make the silhouette a fish, and the punched-out eye settles it.
    """
    image, _, s = _canvas()
    # Lens geometry: circles of radius R offset D above and below the axis meet at a
    # half-width of sqrt(R^2 - D^2) and a half-height of R - D. R .375 / D .225 gives a
    # body 0.60 wide and 0.30 tall.
    lens = Image.new("L", (s, s), 0)
    for sign in (-1, 1):
        disc = Image.new("L", (s, s), 0)
        ImageDraw.Draw(disc).ellipse(
            [s * (0.38 - 0.375), s * (0.50 + sign * 0.225 - 0.375),
             s * (0.38 + 0.375), s * (0.50 + sign * 0.225 + 0.375)], fill=255)
        lens = disc if sign == -1 else ImageChops.multiply(lens, disc)
    image.paste(WHITE, (0, 0), lens)

    d = ImageDraw.Draw(image)
    d.polygon(
        [(s * 0.72, s * 0.50), (s * 0.94, s * 0.29), (s * 0.94, s * 0.71)], fill=WHITE)
    d.ellipse([s * 0.17, s * 0.455, s * 0.26, s * 0.545], fill=CLEAR)
    return _finish(image)


def undo() -> Image.Image:
    """The reply-arrow form: a head pointing left, a shaft, and a tail curving away.

    Two other forms were drawn and rejected by looking at them small. A near-full circle
    with a gap is the *refresh* glyph and promises something else entirely; a top arc
    with a head hanging under its left tip read as an arch with a triangle beside it,
    because nothing in it travels. Here the shaft and the head are one straight run, so
    the eye follows it.
    """
    image, d, s = _canvas()
    width = int(s * 0.105)
    # Shaft, then the tail curving down and right from its far end.
    d.line([(s * 0.30, s * 0.42), (s * 0.60, s * 0.42)], fill=WHITE, width=width)
    d.arc([s * 0.36, s * 0.42, s * 0.84, s * 0.90], start=270, end=390, fill=WHITE, width=width)
    d.polygon(
        [(s * 0.13, s * 0.42), (s * 0.36, s * 0.27), (s * 0.36, s * 0.57)], fill=WHITE)
    return _finish(image)


def tech() -> Image.Image:
    """A tech tree: a root node branching to two, one of which branches again.

    Drawn as a tree growing upward from a root at the bottom, so it reads as progression
    rather than as a network diagram, which is what three evenly spaced nodes did.
    """
    image, d, s = _canvas()
    width = int(s * 0.07)
    root = (s * 0.50, s * 0.80)
    left = (s * 0.27, s * 0.50)
    right = (s * 0.73, s * 0.50)
    top = (s * 0.73, s * 0.20)
    for a, b in ((root, left), (root, right), (right, top)):
        d.line([a, b], fill=WHITE, width=width)
    for (x, y), r in ((root, 0.105), (left, 0.09), (right, 0.09), (top, 0.09)):
        d.ellipse([x - s * r, y - s * r, x + s * r, y + s * r], fill=WHITE)
    return _finish(image)


def remove() -> Image.Image:
    """A bin. The one glyph in the set that has to say "this destroys something"."""
    image, d, s = _canvas()
    # Handle and lid.
    d.rounded_rectangle(
        [s * 0.38, s * 0.13, s * 0.62, s * 0.22], radius=s * 0.03, fill=WHITE)
    d.rounded_rectangle(
        [s * 0.14, s * 0.24, s * 0.86, s * 0.34], radius=s * 0.04, fill=WHITE)
    # Body, tapered, with two slots punched out.
    d.polygon(
        [(s * 0.22, s * 0.38), (s * 0.78, s * 0.38), (s * 0.71, s * 0.88), (s * 0.29, s * 0.88)],
        fill=WHITE)
    for x in (0.42, 0.58):
        d.line([(s * x, s * 0.47), (s * x, s * 0.79)], fill=CLEAR, width=int(s * 0.07))
    return _finish(image)


GLYPHS = {
    "sound_on": sound_on,
    "sound_off": sound_off,
    "pause": pause,
    "play": play,
    "tanks": tanks,
    "close": close,
    "feed": feed,
    "fish": fish,
    "undo": undo,
    "remove": remove,
    "tech": tech,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=Path("assets/textures/ui"))
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    for name, draw_glyph in GLYPHS.items():
        path = args.out_dir / f"{name}.png"
        image = draw_glyph()
        image.save(path)
        opaque = sum(1 for a in image.tobytes()[3::4] if a > 8)
        print(f"{path}  {SIZE}x{SIZE}  ink {opaque / (SIZE * SIZE):.1%}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
