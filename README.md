# Aquarium

A living aquarium for mobile and desktop, built in [Godot 4.6](https://godotengine.org).

A rewrite of an earlier Go/Fyne prototype. Fyne capped out around 50 fish at 6 Hz;
this runs hundreds at 60 fps and exports to iOS, Android, desktop and web.

## Running

Open the project in Godot 4.6 and press F5, or:

```bash
godot --path . res://scenes/aquarium.tscn
```

Tap (or click) anywhere to drop a fish of the currently selected species.

## Tests

A headless functional check of spawning, movement, tank bounds and predation:

```bash
godot --headless --script res://test/smoke_test.gd
```

Exits non-zero on failure, so it drops straight into CI.

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

## Layout

```
scenes/            aquarium.tscn (main), fish.tscn
scripts/           aquarium.gd, fish.gd, fish_species.gd
scripts/systems/   spatial_hash.gd
resources/species/ one .tres per species
assets/textures/   sprites and tank backdrop
test/              headless checks
tools/             one-shot generators and the screenshot capture
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
