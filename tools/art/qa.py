#!/usr/bin/env python3
"""Have a second model grade a sprite before it is allowed into the project.

    python3 tools/art/qa.py clownfish            # a shipped sprite, by species
    python3 tools/art/qa.py --image path/to.png  # any edited or keyed image

**The model that produced the image does not grade it.** Ported from the sprout-party
creature-art pipeline, where every serious defect shipped past the producing agent's own
inspection and was caught by a person looking at the picture. Measuring pixels ("worst
residual magenta: 8") says the keyer behaved; it says nothing about whether the drawing
reads as a fish.

Four behaviours carried over, each learned there rather than here:

* **A fixed rubric, not "does this look right".** An open question invites agreement.
* **The filename is a leak.** A descriptive name measurably inflated the pass rate over
  there, so every subject is written as `subject.png` in a directory of its own.
* **Sample twice and union the failures.** The judge is inattentive rather than wrong,
  and which item it misses moves between runs. Any pass that fails an item fails it.
* **No parsable JSON is a failure, not a pass.** The same silence `generate.py` guards
  against, where the agent reports success and produces no file.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

AGY = Path.home() / ".local/bin/agy"
DEFAULT_MODEL = "gemini-3.7-flash-low"
DEFAULT_TIMEOUT = "6m"
DEFAULT_SAMPLES = 2

# The sprite is drawn over the tank, so it is graded over the tank rather than over
# white: a pale fringe is invisible on white and obvious on blue.
GROUND = (0x1B, 0x4B, 0x6B)
# What the game actually draws a fish at, in logical pixels — `size` on its
# FishSpecies resource. Several defects are invisible here and obvious at full size;
# "does it still read as that fish" is only answerable here. Both sizes go to the judge.
SPRITE_PX = {"clownfish": 36, "anemonefish": 44, "shark": 90}
DEFAULT_SPRITE_PX = 48

# Ordered worst-first. Each item names a defect this pipeline can actually produce —
# a rubric of plausible-sounding checks passes everything.
RUBRIC: tuple[tuple[str, str], ...] = (
    ("one_fish", "Exactly one fish. Not two, not a shoal, not a fish plus a smaller companion."),
    ("side_profile", "A strict side view, facing left, body level. Not three-quarter, not head-on, not tilted."),
    ("nothing_cut", "No part of the fish or its fins is sliced off by a straight horizontal or vertical edge."),
    ("fins_attached", "Every fin and the tail joins the body. Nothing floats detached."),
    ("no_pink_fringe", "No magenta, pink or purple edging anywhere along the outline, and no magenta patches. The fish's own colours are fine; a rim of pink that follows the silhouette is not."),
    ("nothing_but_fish", "Only the fish. No bubbles, water, plants, coral, rocks, sand, tank walls, shadow or reflection."),
    ("no_text", "No lettering, numerals, watermark, signature, border or frame."),
    ("reads_at_sprite_size", "In the small version it still reads as a fish of that kind, not a coloured blob."),
)

# A background is judged against what it has to do for the app — stay out of the fish's
# way — not against the sprite rubric, which would fail it on every item.
BACKGROUND_RUBRIC: tuple[tuple[str, str], ...] = (
    ("no_fish", "No fish anywhere in the scene. Fish are drawn on top at runtime; one painted in is a permanent duplicate."),
    ("muted", "The scene is low contrast and muted. Nothing in it is as bright or as saturated as a cartoon fish would be."),
    ("open_middle", "The middle of the frame is open water, with scenery kept low and to the sides."),
    ("flat_vector", "Flat vector illustration with simple shapes and flat colour, not a photograph and not a painterly render."),
    ("full_bleed", "The scene fills the whole frame edge to edge, with no border, no frame, no letterboxing and no background showing behind it."),
    ("no_text", "No lettering, numerals, watermark or signature."),
)

BACKGROUND_PROMPT = """You are inspecting a background image for a 2D aquarium game. It
is a flat vector illustration of an underwater scene. Brightly coloured cartoon fish are
drawn on top of it at runtime, so its job is to stay out of their way.

Full size: {full}
Small size (roughly how it is seen on a phone): {small}

Open and look at those two image files. They are the only files you may open.

Do not run any shell command. Do not call run_command, list_dir, find_by_name or
view_file on anything else. Do not write any file. Do not ask a question. Judge only what
you can see in the two images — their filenames carry no information about them.

Answer each item "pass" or "fail", with one short sentence of evidence naming where you
see it. If you are unsure, answer "fail" and say what is ambiguous.

{items}

Reply with ONE JSON object and no other text:

{{"scene_guess": "<what you think this depicts>", "items": {{{keys}}}}}

Each item's value is an object: {{"verdict": "pass"|"fail", "why": "<one sentence>"}}
"""

PROMPT = """You are inspecting a piece of game art for defects. It is a flat vector
illustration of a single fish, drawn for a 2D aquarium game, with a dark outline and flat
areas of colour.

It was produced by a generator and then cut out of its background automatically. Cutting
mistakes and generation mistakes are what you are looking for. Be harsh. A defect you
excuse is a defect that ships.

Full size: {full}
Sprite size (how small the game actually draws it): {small}

Open and look at those two image files. They are the only files you may open.

Do not run any shell command. Do not call run_command, list_dir, find_by_name or
view_file on anything else. Do not write any file. Do not ask a question. Judge only what
you can see in the two images — their filenames carry no information about them.

Answer each item "pass" or "fail", with one short sentence of evidence naming where you
see it. If you are unsure, answer "fail" and say what is ambiguous.

{items}

Reply with ONE JSON object and no other text:

{{"fish_guess": "<what kind of fish you think this is>", "items": {{{keys}}}}}

Each item's value is an object: {{"verdict": "pass"|"fail", "why": "<one sentence>"}}
"""


def flatten(path: Path) -> Image.Image:
    """The sprite as the game draws it: composited over the tank, not over white."""
    sprite = Image.open(path).convert("RGBA")
    flat = Image.new("RGB", sprite.size, GROUND)
    flat.paste(sprite, (0, 0), sprite)
    return flat


def write_pair(image: Image.Image, directory: Path, name: str, sprite_px: int) -> tuple[Path, Path]:
    """Both sizes, under names that say nothing about the subject.

    The filename reaches the judge — it is in the prompt and the judge opens the file.
    Measured in the source pipeline: `bad_detached_vine.png` failed the matching item,
    and the same image copied to `specimen_b.png` passed clean.
    """
    subject = directory / name
    subject.mkdir(parents=True, exist_ok=True)
    full = subject / "subject.png"
    small = subject / "subject_small.png"
    image.save(full)
    width = max(1, round(image.width * sprite_px / image.height))
    image.resize((width, sprite_px), Image.LANCZOS).save(small)
    return full, small


def extract_json(text: str) -> dict | None:
    """The first balanced JSON object in the output. The agent narrates either side."""
    start = text.find("{")
    while start != -1:
        depth = 0
        for i in range(start, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    try:
                        parsed = json.loads(text[start : i + 1])
                    except json.JSONDecodeError:
                        break
                    if isinstance(parsed, dict) and "items" in parsed:
                        return parsed
                    break
        start = text.find("{", start + 1)
    return None


def rubric_for(kind: str) -> tuple[tuple[str, str], ...]:
    return BACKGROUND_RUBRIC if kind == "background" else RUBRIC


def judge_once(full: Path, small: Path, model: str, timeout: str, kind: str = "sprite") -> tuple[dict | None, str]:
    rubric = rubric_for(kind)
    template = BACKGROUND_PROMPT if kind == "background" else PROMPT
    message = template.format(
        full=full.resolve(),
        small=small.resolve(),
        items="\n".join(f"{key}: {description}" for key, description in rubric),
        keys=", ".join(f'"{key}": ...' for key, _ in rubric),
    )
    result = subprocess.run(
        [str(AGY), "-p", message, "--model", model, "--print-timeout", timeout],
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    return extract_json(output), output


def judge(full: Path, small: Path, model: str, timeout: str, samples: int, kind: str = "sprite") -> tuple[dict | None, str]:
    """Sample the judge and union the failures. A pass that returns nothing is dropped."""
    verdicts: list[dict] = []
    transcript: list[str] = []
    for _ in range(max(1, samples)):
        verdict, output = judge_once(full, small, model, timeout, kind)
        transcript.append(output)
        if verdict is not None:
            verdicts.append(verdict)
    if not verdicts:
        return None, "\n".join(transcript)

    merged: dict = {
        "fish_guess": verdicts[0].get("fish_guess", verdicts[0].get("scene_guess", "?")),
        "samples": len(verdicts),
        "items": {},
    }
    for key, _ in rubric_for(kind):
        entries = [v.get("items", {}).get(key) for v in verdicts]
        entries = [e for e in entries if isinstance(e, dict)]
        if not entries:
            merged["items"][key] = {"verdict": "fail", "why": "no pass answered this item"}
            continue
        failed = [e for e in entries if str(e.get("verdict", "")).lower() != "pass"]
        if failed:
            agreement = "" if len(failed) == len(entries) else f" (1 of {len(entries)} passes)"
            merged["items"][key] = {"verdict": "fail", "why": f"{failed[0].get('why', '')}{agreement}"}
        else:
            merged["items"][key] = {"verdict": "pass", "why": entries[0].get("why", "")}
    return merged, "\n".join(transcript)


def report(name: str, verdict: dict, kind: str = "sprite") -> bool:
    items = verdict.get("items", {})
    failures = []
    passes = verdict.get("samples", 1)
    print(f"\n{name}  (judge sees: {verdict.get('fish_guess', '?')}; {passes} pass{'es' if passes != 1 else ''})")
    for key, _ in rubric_for(kind):
        entry = items.get(key)
        if not isinstance(entry, dict):
            failures.append(key)
            print(f"  ?    {key}: the judge did not answer this item")
            continue
        passed = str(entry.get("verdict", "")).lower() == "pass"
        if not passed:
            failures.append(key)
        print(f"  {'pass' if passed else 'FAIL'} {key}: {entry.get('why', '')}")
    print(f"  -> {len(failures)} failing: {', '.join(failures)}" if failures else "  -> clean")
    return not failures


def check_image(
    path: Path,
    name: str,
    sprite_px: int,
    model: str = DEFAULT_MODEL,
    timeout: str = DEFAULT_TIMEOUT,
    samples: int = DEFAULT_SAMPLES,
    raw: bool = False,
    kind: str = "sprite",
) -> tuple[bool, list[str]]:
    """Grade one image. Returns (passed, failing item keys)."""
    with tempfile.TemporaryDirectory(prefix="aquarium-qa-") as tmp:
        preview = 320 if kind == "background" else sprite_px
        full, small = write_pair(flatten(path), Path(tmp), name, preview)
        verdict, output = judge(full, small, model, timeout, samples, kind)
    if raw:
        print(f"--- {name} raw ---\n{output}\n--- end ---")
    if verdict is None:
        print(f"{name}: the judge returned no parsable JSON", file=sys.stderr)
        sys.stderr.write(output[-2000:] + "\n")
        return False, ["no-verdict"]
    passed = report(name, verdict, kind)
    failing = [
        key for key, _ in rubric_for(kind)
        if not isinstance(verdict.get("items", {}).get(key), dict)
        or str(verdict["items"][key].get("verdict", "")).lower() != "pass"
    ]
    return passed, failing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("species", nargs="*")
    parser.add_argument("--image", type=Path, action="append", default=[])
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--timeout", default=DEFAULT_TIMEOUT)
    parser.add_argument("--samples", type=int, default=DEFAULT_SAMPLES)
    parser.add_argument("--raw", action="store_true")
    parser.add_argument(
        "--kind",
        default="sprite",
        choices=["sprite", "background"],
        help="Which rubric to grade against. A backdrop judged on the sprite rubric "
        "fails every item, which says nothing.",
    )
    args = parser.parse_args()

    if not args.species and not args.image:
        parser.error("name at least one species, or pass --image")

    textures = Path(__file__).resolve().parent.parent.parent / "assets/textures"
    targets = [(s, textures / f"{s}.png", SPRITE_PX.get(s, DEFAULT_SPRITE_PX)) for s in args.species]
    targets += [(p.stem, p, SPRITE_PX.get(p.stem, DEFAULT_SPRITE_PX)) for p in args.image]

    clean = True
    for name, path, sprite_px in targets:
        if not path.exists():
            print(f"{name}: no image at {path}", file=sys.stderr)
            clean = False
            continue
        passed, _ = check_image(
            path, name, sprite_px, args.model, args.timeout, args.samples, args.raw, args.kind)
        clean = clean and passed

    print("\nall clean" if clean else "\nat least one image failed")
    return 0 if clean else 1


if __name__ == "__main__":
    sys.exit(main())
