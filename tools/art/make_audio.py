#!/usr/bin/env python3
"""Generate the tank's ambient audio.

Synthesised rather than sourced, for the same reasons as the art: it is deterministic,
it costs no quota, and it carries no licence question. Standard library only — no numpy
on this machine, and a few seconds of mono audio does not need it.

    python3 tools/art/make_audio.py --out-dir assets/audio

The loop is built to be seamless: every component completes a whole number of cycles
over the loop's length, so the end meets the beginning exactly and there is no click.
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
LOOP_SECONDS = 8.0


def _write(path: Path, samples: list[float]) -> None:
    peak = max(1e-9, max(abs(s) for s in samples))
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s / peak * 0.82)) * 32767))
                      for s in samples)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(frames)


def ambient(seconds: float = LOOP_SECONDS, seed: int = 11) -> list[float]:
    """A low underwater wash: brown noise under a couple of slow swells.

    Brown noise rather than white — white noise reads as static or rain, brown as water
    and distance. It is leaked back toward zero so the random walk cannot drift away
    from the centre over a long loop.
    """
    rng = random.Random(seed)
    count = int(RATE * seconds)
    out: list[float] = []
    brown = 0.0
    low = 0.0
    for i in range(count):
        t = i / RATE
        brown = brown * 0.996 + rng.uniform(-1.0, 1.0) * 0.04
        low += (brown - low) * 0.012          # one-pole low pass
        # Whole numbers of cycles across the loop, so the ends meet.
        swell = 0.55 + 0.45 * math.sin(2.0 * math.pi * (1.0 / seconds) * t)
        deep = 0.30 * math.sin(2.0 * math.pi * (2.0 / seconds) * t + 1.1)
        out.append(low * swell + low * deep * 0.5)

    # Cross-fade the tail over the head so any residual mismatch is inaudible.
    blend = int(RATE * 0.25)
    for i in range(blend):
        a = i / blend
        out[i] = out[i] * a + out[count - blend + i] * (1.0 - a)
    return out[: count - blend]


def plop(seed: int = 3) -> list[float]:
    """A short soft blip for dropping food — a damped sine with a fast decay."""
    rng = random.Random(seed)
    count = int(RATE * 0.18)
    out: list[float] = []
    for i in range(count):
        t = i / RATE
        env = math.exp(-t * 26.0)
        pitch = 430.0 * math.exp(-t * 5.0)
        out.append(math.sin(2.0 * math.pi * pitch * t) * env
                   + rng.uniform(-1.0, 1.0) * env * 0.05)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    for name, samples in (("ambient", ambient()), ("plop", plop())):
        path = args.out_dir / f"{name}.wav"
        _write(path, samples)
        print(f"{path}  {len(samples) / RATE:.2f}s  {path.stat().st_size / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
