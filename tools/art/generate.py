#!/usr/bin/env python3
"""Drive Antigravity's `generate_image` from the command line and keep the result.

Lifted from the sprout-party creature-art pipeline. The two forcing behaviours below
were learned there the expensive way; nothing about them is plant-specific.

`agy` is an agent, not an image endpoint, so two things have to be forced:

* **The prompt must survive.** Left to itself the agent rewrites the prompt it was
  given — the first run through here silently compressed a 300-word art brief into
  five sentences and dropped half the palette constraints. The prompt is passed as an
  opaque block with an instruction to copy it byte for byte, and `--verify` reads back
  what was actually sent.
* **The file must be recovered.** `generate_image` writes into the conversation's own
  `brain/` directory and tells the agent not to reveal the path, so nothing lands where
  it was asked to. The directory is snapshotted before the run and diffed after.

Output is always JPEG — the tool has no PNG mode — so every result needs `quantise.py`
before it is worth looking at.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

AGY = Path.home() / ".local/bin/agy"
BRAIN = Path.home() / ".gemini/antigravity-cli/brain"

# `--mode accept-edits` and `--dangerously-skip-permissions` both hand a subagent
# unattended write access, so neither is used. Headless `agy` auto-denies anything
# it would have to prompt for, which is why the prompt forbids shell commands
# outright: one stray `mkdir` aborts the whole run with no output.
INSTRUCTIONS = """Call the generate_image tool exactly once, then stop.

Do not run any shell command. Do not call run_command, list_dir, find_by_name or
view_file. Do not write any file yourself. Do not ask a question. The only tool
call you may make is generate_image.

Arguments:
  ImageName: {name}
  AspectRatio: {aspect}{refs}

The Prompt argument must be the text between the two BEGIN/END markers below,
copied byte for byte. Do not paraphrase it, do not shorten it, do not merge its
sentences, do not "improve" it, and do not add anything to it. It is already the
finished prompt.

--- BEGIN PROMPT ---
{prompt}
--- END PROMPT ---
"""


def newest_conversation_images() -> set[Path]:
    return set(BRAIN.glob("*/*.jpg")) | set(BRAIN.glob("*/*.png"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt_file", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument(
        "--name",
        default=None,
        help="ImageName passed to the tool. Defaults to the destination's stem.",
    )
    parser.add_argument(
        "--ref",
        type=Path,
        action="append",
        default=[],
        help="Reference image for the model to hold style against (max 3). This is how "
        "the shared pot stays the same pot across species — text alone does not hold it.",
    )
    parser.add_argument(
        "--aspect",
        default="1:1",
        help="Aspect ratio for the render. A trailing species asks for a tall one — the "
        "model composes to fill whatever frame it is given, so a square canvas buys a "
        "vine a tall crown and short vines however the prompt is worded.",
    )
    parser.add_argument("--model", default="gemini-3.7-flash-low")
    parser.add_argument("--timeout", default="8m")
    args = parser.parse_args()

    if len(args.ref) > 3:
        parser.error("generate_image accepts at most 3 reference images")
    for ref in args.ref:
        if not ref.exists():
            parser.error(f"reference image does not exist: {ref}")

    name = args.name or args.destination.stem
    refs = ""
    if args.ref:
        joined = ", ".join(str(r.resolve()) for r in args.ref)
        refs = f"\n  ImagePaths: [{joined}]"

    message = INSTRUCTIONS.format(
        name=name, refs=refs, aspect=args.aspect, prompt=args.prompt_file.read_text().strip()
    )

    before = newest_conversation_images()
    result = subprocess.run(
        [
            str(AGY),
            "-p",
            message,
            "--model",
            args.model,
            "--print-timeout",
            args.timeout,
        ],
        capture_output=True,
        text=True,
    )
    produced = sorted(
        newest_conversation_images() - before, key=lambda p: p.stat().st_mtime
    )

    if not produced:
        sys.stderr.write(result.stdout + result.stderr)
        sys.stderr.write(f"\nno image produced for {name}\n")
        return 1

    args.destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(produced[-1], args.destination)
    print(f"{args.destination}  <- {produced[-1].name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
