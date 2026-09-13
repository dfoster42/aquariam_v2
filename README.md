# Aquarium

A living aquarium for mobile and desktop, built in [Godot 4.6](https://godotengine.org).

A rewrite of an earlier Go/Fyne prototype. Fyne capped out around 50 fish at 6 Hz.

## Measured performance

`tools/benchmark.gd`, vsync disabled, Apple M5 Pro desktop, Compatibility renderer:

| fish | mean frame | fps |
| ---: | ---: | ---: |
| 50 | 1.10 ms | 912 |
| 100 | 1.75 ms | 572 |
| 197 | 3.66 ms | 273 |
| 347 | 8.48 ms | 118 |
| 524 | 16.85 ms | 59 |
| 781 | 30.97 ms | 32 |
| 1069 | 49.26 ms | 20 |

Roughly **520 fish at 60 fps** on this machine. Phones will be lower; that number has
not been measured on device yet.

Cost grows around n^1.5, not linearly. That is density rather than a defect in the
spatial grid: the tank is a fixed size, so doubling the population doubles how many
neighbours fall inside each fish's sight radius. The grid stops each fish scanning
*every* other fish; it cannot stop the tank getting crowded.

```bash
godot --script res://tools/benchmark.gd
```

## Running

Open the project in Godot 4.6 and press F5, or:

```bash
godot --path . res://scenes/aquarium.tscn
```

Tap (or click) the tank to drop a fish of the selected species. Drag to pan, pinch to
zoom (mouse wheel on desktop). The bottom row picks a species; the top bar shows the
population and pauses the tank.

A tap and a drag share one finger, so a press stays provisional until it either moves
past `DRAG_SLOP` or is released still enough and soon enough to count as a tap. Only the
release spawns.

## Tests

A headless functional check of spawning, movement, tank bounds and predation:

```bash
godot --headless --script res://test/smoke_test.gd
```

It covers spawning, movement, tank bounds, predation, pause, species selection,
tap-to-spawn, and the safe-area inset arithmetic.

CI runs it on every push and pull request. Note that `godot --script` exits **0** on a
script parse error — measured, not assumed — so a broken test file would otherwise pass
silently. The workflow greps for the test's own `RESULT: PASS` line; that is what
actually gates the build.

## Persistence

The tank is written to `user://tank.json` when the app closes or is backgrounded, and
restored on launch; a fresh tank is seeded only when there is nothing to restore.

JSON rather than a `.tres`: a saved Resource is a script-bearing file the engine will
instantiate on load, which turns a save file into a code path. Species are stored by
`resource_path`, so reordering the species list or renaming a display name does not
orphan a tank, and a fish whose species no longer exists is dropped rather than failing
the whole restore.

## Platforms

| target | status |
| --- | --- |
| Web | exports and runs; checked in a browser at 375x812 |
| macOS | exports; universal `x86_64 arm64` |
| iOS simulator | **works**, after patching the export template — see below |
| iOS device | builds `arm64`; needs a paid Apple developer account to sign |
| Android | not attempted; needs a JDK and the Android SDK |

### iOS simulator needs a patched export template

Godot's official iOS template ships a simulator library that is x86_64 only, while its
own xcframework metadata claims otherwise:

```
libgodot.ios.debug.xcframework/Info.plist  -> SupportedArchitectures: [arm64, x86_64]
libgodot.ios.debug.xcframework/ios-arm64_x86_64-simulator/libgodot.a
  lipo -archs -> x86_64
```

Apple-silicon simulators are arm64 and Xcode 26 dropped Rosetta for simulator apps, so a
stock template builds an app that will not install: *"Failed to find matching arch"*.
This is [godot#118161](https://github.com/godotengine/godot/issues/118161), and upstream
intends to delete simulator support rather than fix it
([PR #122365](https://github.com/godotengine/godot/pull/122365)), on the grounds that the
simulator cannot do Metal.

**That reasoning does not apply to this project.** Godot's own `platform/ios/detect.py`
turns Metal and Vulkan *off* for simulator builds and keeps GLES3:

```python
if env["metal"] and env["simulator"]:
    print_warning("iOS Simulator does not support the Metal rendering driver")
    env["metal"] = False
if env["vulkan"] and env["simulator"]:
    ...
if env["opengl3"]:
    env.Append(CPPDEFINES=["GLES3_ENABLED", ...])
```

This project runs the Compatibility renderer, which *is* GLES3. OpenGL is not the
obstacle here — it is the only renderer the simulator supports, and the arm64 slice is
simply missing. Building it is enough:

```bash
tools/patch_ios_simulator_template.sh      # ~4 min per target on 18 cores
```

That clones the matching engine source, builds `libgodot.ios.template_{debug,release}.arm64.simulator.a`
with `scons platform=ios arch=arm64 simulator=yes`, fuses each into the shipped x86_64
slice with `lipo`, and repacks `ios.zip` in place. The stock template is preserved as
`ios.zip.orig`, and the script is idempotent. Prerequisites: Xcode, and
`python3 -m pip install scons`.

Then:

```bash
godot --headless --export-debug "iOS" build/ios/Aquarium.xcodeproj
cd build/ios && xcodebuild -project Aquarium.xcodeproj -scheme Aquarium \
  -sdk iphonesimulator -configuration Debug -derivedDataPath dd \
  -destination "id=<simulator udid>" CODE_SIGNING_ALLOWED=NO build
xcrun simctl install <udid> dd/Build/Products/Debug-iphonesimulator/Aquarium.app
```

Verified on an iPhone 17 Pro simulator running iOS 26.5: the app launches, lays out
under the Dynamic Island, tap-to-spawn works, and pause works.

Two notes on the export preset. `application/targeted_device_family` uses Godot's enum
where **0 is iPhone, 1 is iPad and 2 is both** — setting it to `1` expecting iPhone
produces `TARGETED_DEVICE_FAMILY = "2"` and Xcode then offers no iPhone destinations at
all. And `application/app_store_team_id="0000000000"` is a placeholder so the exporter
will run; it is not a real team ID and must be replaced before any signed build.

### A renderer note

A Godot maintainer notes on that thread that OpenGL on iOS "is deprecated for a long
time... Apple can remove it in any iOS update or stop accepting apps using it". That is
worth knowing before shipping to the App Store, and a released iOS build probably wants
`rendering/renderer/rendering_method.mobile="mobile"` (Metal) with web staying on
`gl_compatibility` — but note that this would end simulator testing, since Metal is
exactly what the simulator cannot do.

## Layout notes

The tank is a fixed world (`tank_size`), not the viewport. A camera looks at part of it,
so fish swim to the edge of the *tank* while the view moves independently.

Every layout container in `ui.tscn` sets `mouse_filter = 2` (IGNORE). A `Control`
defaults to STOP, and one full-rect container left at the default silently swallows
every tap meant for the tank — fish just stop spawning, with no error. The smoke test
asserts this.

`backdrop_tint` multiplies into the backdrop and is white by default. It briefly held a
dimming colour to make the original photograph survivable behind flat vector fish; the
drawn backdrop needs no such help, and applying the old value to it would crush it.

## Adding a species

No code required. Duplicate a resource in `resources/species/`, point it at a
texture, set its stats, then add it to the `Aquarium` node's `available_species`
array in the inspector.

`eats` is the only diet field. Which species *hunt* a given fish is derived from
it at load, so predator and prey can never disagree.

To regenerate the three starting species from scratch:

```bash
godot --headless --script res://tools/generate_species.gd
```

## Art

Sprites are generated through the Antigravity CLI and graded by a second model before
they are allowed into the project.

```bash
python3 tools/art/build.py clownfish                 # cached render, free to re-cut
python3 tools/art/build.py clownfish --force         # re-roll; this is what costs quota
python3 tools/art/build.py shark --ref /tmp/aquarium-art/raw/clownfish.jpg
python3 tools/art/qa.py clownfish shark              # grade shipped sprites
```

The pipeline is adapted from the sprout-party creature-art tooling; the rules it
encodes were learned there, not here.

**The model that made the image does not grade it.** `qa.py` sends the sprite to a
second model against a fixed rubric — an open "does this look right" invites agreement.
It samples twice and unions the failures, because the judge is inattentive rather than
wrong. No parsable JSON is a failure, not a pass. `build.py` stages a render and copies
it into `assets/textures/` only on a clean verdict; `--force-qa` is the only way past
that, and using it belongs in the commit message.

**Every subject reaches the judge as `subject.png`.** The filename is a leak — in the
source pipeline a descriptive name measurably inflated the pass rate.

**The backdrop is drawn, not generated.** `tools/art/draw_background.py` draws it
directly and deterministically:

```bash
python3 tools/art/draw_background.py --out /tmp/aquarium-art/staged/background.jpg
python3 tools/art/qa.py --image /tmp/aquarium-art/staged/background.jpg --kind background
```

Stepped water, a sand floor, rocks and seaweed are almost entirely geometry, and the
source pipeline's rule is that geometry is arithmetic rather than adjectives. Drawing it
is exact, repeatable, and costs no generation quota — which the fish sprites need. It
still goes through the judge, against a background rubric whose items are about staying
out of the fish's way rather than about anatomy.

Two things learned by drawing it wrong first: everything below the waterline is a
silhouette (giving the sand and rocks their own local colour reproduced exactly the
contrast problem the photograph had), and water must be a per-row gradient (four flat
bands leave four visible seams).

`build.py` also understands `kind: background` for a *generated* backdrop, with a brief
at `tools/art/prompts/background.txt`. That path is unused and its generate and judge
steps have never been run — only its downstream half is tested.

Only the render costs quota. It is cached in `/tmp/aquarium-art/raw/`, so re-cutting
after a pipeline change is free. `429 RESOURCE_EXHAUSTED` names a reset time and means
stop; "no image generated in response" is transient and worth one retry.

Transparency comes from a chroma key, not a luminance threshold: briefs ask for flat
magenta, which no fish in the catalogue comes near on any channel. A luma cut would take
the shark's grey back and the clownfish's white bands with it.

**Every sprite faces left.** `scripts/fish.gd` mirrors a fish swimming right, so art
drawn facing right will swim backwards.

## Layout

```
scenes/            aquarium.tscn (main), fish.tscn
scripts/           aquarium.gd, fish.gd, fish_species.gd
scripts/systems/   spatial_hash.gd
resources/species/ one .tres per species
assets/textures/   sprites and tank backdrop
test/              headless checks
tools/             one-shot generators and the screenshot capture
tools/art/         the art pipeline: briefs, generation, keying, QA
```

## Rendering

The project uses the **Compatibility** renderer (OpenGL ES 3.0 / WebGL 2) rather
than Forward+. A 2D sprite scene needs none of what Forward+ adds, Compatibility
has the lowest overhead and widest device floor, and it is the only method that
supports web export. On macOS and iOS, Godot translates it to Metal via ANGLE.

## Notes

Neighbour lookups go through a uniform spatial grid (`scripts/systems/spatial_hash.gd`),
rebuilt once per frame by `Aquarium` and shared by every fish, replacing the
prototype's all-pairs scan.

The simulation runs in `_process`, deliberately not `_physics_process`. The tank has no
collision and no rigid bodies, and the fixed clock was actively harmful: past ~500 fish
a step overran its 16.67 ms budget, so the engine ran extra steps to catch up, which
made the next step later still, until it pinned at `max_physics_steps_per_frame` (8) and
frame time locked to exactly 8 x 16.67 = 133.33 ms. The tank fell 60 fps to 7 fps
between two adjacent benchmark steps. On `_process` a heavy frame is just a longer
frame.
