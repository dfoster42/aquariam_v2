#!/usr/bin/env python3
"""Build one aquarium sprite end to end: brief -> render -> keyed PNG in the project.

Only the render costs quota, so it is cached in RAW_DIR and everything downstream is
free and rerunnable. `build.py <id>` after a pipeline change re-cuts from the cached
JPEG without calling the model; `--force` is the only thing that spends.

A species brief carries two directives on its first lines:

    aspect: 16:9     the frame shape handed to the model
    height: 300      the pixel height of the finished sprite

Aspect is here rather than in the shared style block because it is the one geometric
lever a prompt actually holds — the model composes to fill whatever frame it is given,
so a long shark asks for a wide canvas and a deep-bodied clownfish does not. Height is
applied downstream by cutout.py, where it is exact.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

import qa

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
PROMPTS = HERE / "prompts"
RAW_DIR = Path("/tmp/aquarium-art/raw")
STAGE_DIR = RAW_DIR / "staged"
TEXTURES = PROJECT / "assets/textures"


def read_brief(species: str) -> tuple[str, str, int, str]:
    """Brief plus its directives. `kind:` selects the pipeline.

    A sprite is keyed out of flat magenta and ships as a trimmed PNG. A background is
    opaque by definition — there is nothing to key, and running the keyer over one
    would punch holes wherever the art happened to go purple — so it ships as a JPEG
    and carries its own style block and its own rubric.
    """
    path = PROMPTS / "species" / f"{species}.txt"
    if not path.exists():
        path = PROMPTS / f"{species}.txt"
    if not path.exists():
        sys.exit(f"no brief for {species}")

    aspect, height, kind, body = "1:1", 0, "sprite", []
    for line in path.read_text().splitlines():
        if line.startswith("aspect:"):
            aspect = line.split(":", 1)[1].strip()
        elif line.startswith("height:"):
            height = int(line.split(":", 1)[1].strip())
        elif line.startswith("kind:"):
            kind = line.split(":", 1)[1].strip()
        else:
            body.append(line)

    if not height:
        sys.exit(f"{path} has no `height:` directive")
    text = "\n".join(body).strip()
    if kind == "sprite":
        text = f"{(PROMPTS / 'style.txt').read_text().strip()}\n\n{text}"
    return f"{text}\n", aspect, height, kind


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("species", nargs="+")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-roll the render. Without it a cached raw JPEG is reused for free.",
    )
    parser.add_argument(
        "--force-qa",
        action="store_true",
        help="Ship a sprite the judge failed. The only way past a fail, and using it "
        "belongs in the commit message: the next person to wonder why a fish looks "
        "wrong should find the answer in git rather than in the tank.",
    )
    parser.add_argument(
        "--samples",
        type=int,
        default=qa.DEFAULT_SAMPLES,
        help="Judge passes per sprite. Any pass that fails an item fails the sprite.",
    )
    parser.add_argument(
        "--ref",
        type=Path,
        action="append",
        default=[],
        help="Reference image the model holds style against (max 3). This is how a "
        "catalogue stays one set — text alone does not hold a style across renders.",
    )
    args = parser.parse_args()

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    STAGE_DIR.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    for species in args.species:
        prompt, aspect, height, kind = read_brief(species)
        raw = RAW_DIR / f"{species}.jpg"

        if args.force or not raw.exists():
            brief_file = RAW_DIR / f"{species}.prompt.txt"
            brief_file.write_text(prompt)
            command = [
                sys.executable, str(HERE / "generate.py"),
                str(brief_file), str(raw),
                "--name", species,
                "--aspect", aspect,
            ]
            for ref in args.ref:
                command += ["--ref", str(ref)]
            print(f"generating {species} at {aspect} ...")
            if subprocess.run(command).returncode != 0:
                print(f"  {species}: generation failed, skipping", file=sys.stderr)
                continue
        else:
            print(f"{species}: reusing cached render ({raw})")

        # Cut to a staging path first. A sprite reaches assets/textures/ only after a
        # second model has looked at it — measuring pixels says the keyer behaved, not
        # that the drawing reads as a fish.
        if kind == "background":
            staged = STAGE_DIR / f"{species}.jpg"
            image = Image.open(raw).convert("RGB")
            width = max(1, round(image.width * height / image.height))
            image.resize((width, height), Image.LANCZOS).save(
                staged, quality=88, optimize=True, progressive=True)
            print(f"{staged}  {width}x{height}")
        else:
            staged = STAGE_DIR / f"{species}.png"
            subprocess.run([
                sys.executable, str(HERE / "cutout.py"),
                str(raw), str(staged), "--height", str(height),
            ], check=True)

        passed, failing = qa.check_image(
            staged, species, qa.SPRITE_PX.get(species, qa.DEFAULT_SPRITE_PX),
            samples=args.samples, kind=kind,
        )
        if not passed and not args.force_qa:
            print(
                f"  {species}: refused — {', '.join(failing)}. Staged render left at "
                f"{staged}. Re-roll with --force, or ship it anyway with --force-qa.",
                file=sys.stderr,
            )
            failures.append(species)
            continue
        if not passed:
            print(f"  {species}: FAILED QA ({', '.join(failing)}) and shipped under --force-qa")

        TEXTURES.mkdir(parents=True, exist_ok=True)
        shipped = TEXTURES / staged.name
        shutil.copy2(staged, shipped)
        print(f"  {species}: shipped to {shipped}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
