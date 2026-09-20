# Aquarium

A living aquarium for mobile and desktop, built in [Godot 4.6](https://godotengine.org).

A rewrite of an earlier Go/Fyne prototype. Fyne capped out around 50 fish at 6 Hz.

## Measured performance

`tools/benchmark.gd`, vsync disabled, Apple M5 Pro desktop, Compatibility renderer,
against the shipping build — five species, the 3240x2160 map:

| fish | mean frame | fps |
| ---: | ---: | ---: |
| 54 | 0.90 ms | 1107 |
| 99 | 1.48 ms | 677 |
| 198 | 2.21 ms | 453 |
| 372 | 4.59 ms | 218 |
| 634 | 9.61 ms | 104 |
| 818 | 17.10 ms | 58 |

**About 630 fish at 60 fps**, and 20 plants costs nothing measurable — the ceiling is the
same with and without them.

Cost grows around n^1.5, not linearly. That is density rather than a defect in the
spatial grid: the map is a fixed size, so doubling the population doubles how many
neighbours fall inside each fish's sight radius.

**These are desktop numbers and nothing else.** A real phone has not been measured: iOS
needs a signing identity and the Android emulator renders through SwiftShader, a software
rasteriser, so its frame times mean nothing about hardware.

The benchmark fills the tank in the proportions it actually settles at, weighted by each
species' capacity. Cycling the species list round-robin instead made one spawned fish in
five a shark, and the tank ate itself faster than it could be filled — a run targeting
1500 stalled near 580, so every number described a collapsing tank.

```bash
godot --script res://tools/benchmark.gd            # add -- --decor N for plants
```

## Running

Open the project in Godot 4.6 and press F5, or:

```bash
godot --path . res://scenes/aquarium.tscn
```

Tap (or click) the tank to place whatever the picker has armed. Drag to pan, pinch to
zoom (mouse wheel on desktop). The dock along the bottom is a scrolling strip of tiles —
each species, each plant, and Feed — and the line above it says in words what a tap on
the water will do. The top bar shows the population, and mutes, switches tank, or pauses.

A tap and a drag share one finger, so a press stays provisional until it either moves
past `DRAG_SLOP` or is released still enough and soon enough to count as a tap. Only the
release spawns.

## Undo, and removing things

The picker's last tile arms **Remove**: the next tap takes out the nearest fish, plant or
pellet. The **undo** button in the top bar takes back the last thing placed — or puts
back the last thing removed.

Undo is a stack of **actions, not snapshots**. The tank is a running simulation, so a
fish placed a minute ago may since have bred, been eaten, or died of old age. Restoring a
saved state would make undo silently revive everything that had died in between, which
is a much stranger promise than the button makes. An entry instead says "this object was
added" or "this object was removed, here is what it was", and undoing one takes the
object back out or puts it back.

Three things fall out of that, and each is a test in `edit_test`:

**An entry can go stale, and that is not an error.** A fish eaten before it could be
undone is gone; the entry is dropped and the button undoes the most recent thing it still
can. Staleness is `is_inside_tree()`, not `is_instance_valid()` — removal detaches on the
spot, while a queued free stays "valid" until the end of the frame.

**Undoing a removal creates a new instance**, so any older entry naming the original is
re-pointed at it. Without that, "place a fish, delete it, undo, undo" leaves the fish in
the tank: the second undo would find an entry naming the freed original, judge it stale,
and drop it.

**Only the player's own taps are recorded.** Breeding and restoring both go through
`spawn()`, so recording happens in `place_selected()` — a tank that bred while nobody was
looking would otherwise fill the stack with fish the player never placed.

Removing a fish does not emit `fish_died`. That signal means the *ecosystem* lost a fish,
and the simulation tests count predation from it; a fish the player deleted is neither
eaten nor old, so removal and dying share the bookkeeping and not the signal.

The grab radius is in **screen** units and converted by the camera's zoom
(`CameraRig.world_per_screen_unit()`). A finger is a fixed size on the glass while the
world under it is not: at the widest zoom one screen unit is about eight world units, at
the tightest about a third of one, so a world-space constant would grab a fish three body
lengths away when zoomed out and miss the one under the finger zoomed in. A tap that
reaches nothing removes nothing.

Candidates are scored on distance relative to their own grab radius rather than on
distance alone, so a shark is not picked over the clownfish under the finger purely by
being bigger. Plants are measured against the rectangle they occupy, because decor is
rooted at its base and stands upward — measuring to its origin would mean tapping a
kelp's foot exactly.

Undo is in memory only. It is not saved, and `clear_tank()` empties it: every entry names
a node that is gone, and restoring a removal into a deliberately emptied tank would be a
surprise.

## Feeding

Arm **Feed** in the picker and tap to drop pellets. They sink, hungry fish break off to
chase them, and eating refills the fish. Sharks ignore food entirely — `hunger_time` 0
means never hungry, so they stay driven by prey.

**Hunger does not kill.** Starvation would punish an ambient app for the thing ambient
apps are for, and a tank that dies out unattended is a tank nobody reopens. A hungry fish
breeds half as often instead, so feeding is a reward for attention rather than a tax on
absence.

## Life cycle

Fish age. Age drives size, so juveniles are visibly smaller, and it drives breeding and
death. Two mature adults of a species within its `breed_distance` produce one offspring
and both go on cooldown, capped by a per-species carrying capacity. Sharks have
`breed_distance` 0 and never pair, so predation pressure is something the player adds by
tapping rather than something that compounds on its own.

Prey see much further than the shark does (240 and 230 against 150). That is the lever
that keeps the tank alive against a predator that actually connects: prey break for open
water before the shark has registered them, so a catch takes a long pursuit or a
cornering against the glass. `test/ecosystem_test.gd` is what tuned these numbers.

A predator bites with its **mouth**, not its centre. Measured centre to centre, prey were
only caught once they had reached the middle of the shark — its sprite is ~213px long, so
the mouth sits ~106px ahead of the point being measured. Hunting also steers the mouth
onto the prey rather than the centre, because aiming the centre makes the mouth sweep
past on a tangent.

A fish's facing is tracked separately from its sprite. `flip_h` snaps the instant a
heading crosses vertical while `rotation` eases, so a mouth derived from sprite state
teleported a body length sideways and sharks could bite prey behind their own tails.

## Decor, and shelter

Plants are placeable the same way fish are: one `DecorKind` .tres per item in
`available_decor`, no code per item. The picker holds fish and decor in one button
group, so a tap only ever places one kind of thing.

**Plants hide prey from sharks.** A plant with a `shelter_radius` conceals prey inside
it: a predator skips sheltered prey when choosing a target, checked while hunting rather
than at the bite, so a shark does not swim to a plant and loiter beside it. Fleeing prey
also break for cover when any is in sight — without that, plants would only shelter the
prey that happened to drift into one and the player could never see cover working.

Concealment is computed once per frame for every fish, not per predator: a fish with ten
hunters near it would otherwise test its surroundings ten times for the same answer.
Decor never moves, so its spatial grid is rebuilt only when the set changes.

Plants wave, and the simulation knows nothing about it. `shaders/sway.gdshader` bends
each sprite by offsetting its texture lookup, scaled by height so the tips move and the
base stays planted. A Sprite2D is a four-vertex quad, so displacing its corners would
shear the whole sprite rather than bend it; sampling along a curve gives a real bend from
the same quad.

Each plant's phase comes from its own world position, read from `MODEL_MATRIX` in
`vertex()`. That is what keeps it cheap: every plant shares **one** material, so they
still batch, while no two sway together. A duplicated material per plant carrying a
random phase would break batching for the same result.

Measured on an M5 Pro with vsync off: the 60 fps ceiling is the same at 0 plants and
at 20, and 80 plants roughly halves it.

The shader itself is free: at matched fish counts, sway on versus off measured 9.35 vs
9.47 ms, 16.76 vs 15.91 ms and 24.64 vs 22.77 ms — inside the noise and the differing
fish counts. What costs is 80 large sprites' worth of fill rate, not the waving. At a
realistic 20 plants there is no measurable cost at all.

Decor textures carry 10% transparent padding either side, because the shader samples
past the sprite's edge at full lean and would otherwise clip the tips.

Decor is saved with the tank, and restored *before* the fish, so a reloaded tank's
shelter is in effect on the first frame rather than one frame late.

## Colonies, territory, and the god-sim prototype

An experiment, not a direction that has been committed to. The question it exists to
answer is narrow: **is any of this worth watching?**

The tank as it stands is unclippable. It is calm, it is pretty, and nothing that happens
in it changes it — a fish spawns, breeds, is eaten, and the tank afterwards is
indistinguishable from the tank before. Nothing accumulates, so nothing can be lost, so
there is no moment worth showing anyone. A colony is the first object here that does
accumulate.

A `Faction` is a colour and a fish. A `Colony` is one faction's foothold: it holds
`biomass`, grows logistically, claims ground, releases fish tinted to match, and can be
destroyed. `Territory` computes who owns what as a 90x60 influence grid over the map and
paints it as one filtered texture — that layer is the entire reason the rest is legible.
Without it a disaster kills an object; with it a disaster opens a hole that the
neighbours visibly flow into.

Three things were wrong on the first try, and each was found by measuring rather than by
thinking about it.

**Colonies that only grow in place never make a map.** Three reefs left alone held 12.8%
of the ground each with 61.8% open water between them, and striking one moved its
neighbours by 0.2 points. They were never touching, so there was no border to redraw.
Colonies now spread — a mature one with room pays biomass to found a daughter just past
its own edge — and open water fell to 18.8%.

**A point strike is a pinprick against a faction that has spread.** Bleaching one colony
of a faction holding a third of the map moved that share by 0.8 points, because the
faction had a dozen others and none of them cared. A disaster has to travel the way the
thing it is destroying travelled: `bleach()` runs breadth-first across touching colonies
of *one* faction, losing strength at each hop. It burns out on purpose — one tap should
not flatten a map-spanning faction — and it stops dead at a rival's border, because a
disaster that flattens everyone equally erases the map instead of redrawing it.

**A hard claim threshold is a visible staircase.** The faintest claimed cell drew at
0.14 alpha against open water's zero, and the whole outer border came out as a cliff
that no amount of texture filtering could soften. Alpha is now remapped from the claim
threshold rather than from zero, so it reaches zero exactly where the claim does.

With all three in place: Deep Blue held 32.8% of the map, was bleached for 236 biomass,
and went to 0.0% while Kelp Court climbed 15.3% to 24.1%. That before-and-after is the
thing the experiment was for.

```bash
godot --headless --script res://test/colony_test.gd        # the five checks
godot --script res://tools/colony_demo.gd -- --out-dir /tmp/shots
```

The demo fast-forwards through the tank's own `_tick_colonies` rather than waiting for
frames. The first version of it waited 240 frames — four seconds — for growth that takes
a minute, photographed three untouched seed colonies, and reported that nothing happened.

**Known gaps.** Colonies are saved with their biomass but offline progression ignores
them, so a tank left overnight comes back with its map exactly as it was. Remove mode
does not take out a colony — `strike` and `bleach` are the verbs for that — though undo
does take back one you just placed. The Strike tile borrows the Remove glyph, and the
faction tiles borrow the anemone.

## The simulation knows where the ground is

`tools/art/draw_background.py` draws a sculpted sea floor, and for a long time it had the
only copy of that curve. Nothing in the tank knew the floor existed, so:

- decor floated in mid-water, because a plant went wherever the finger landed
- colonies floated in mid-water, for the same reason
- **fish swam through the 13-36% of every column painted as solid rock**

Nobody noticed the third one because nothing else knew either. `scripts/systems/seabed.gd`
is a transliteration of `terrain_level`, `ravine_depth` and `floor_height`, and it is exact
rather than approximate: the Python takes `t = x / width`, so the curve is scale-invariant
in x, and `_fit_background()` computes a cover scale of exactly 1.0 — backdrop pixel
(x, y) *is* world (x, y). The shipped floor spans y 1380.6 to 1871.2, and water is
**76.6%** of the tank's rectangle.

The two implementations share no source of truth, so `test/seabed_test.gd` pins them
together against values dumped from the Python. If the art is redrawn with different
constants, that test is what says so, rather than the floor silently sliding out from
under everything.

**The three ravines are live.** `draw_background.py` carries a comment saying "No ravines
for now" — it refers only to a deleted dark-fill layer, while `RAVINES` has three entries
and `floor_height` defaults to carved. There are real basins at x roughly 680, 1847 and
2754, and a port that believed the comment would have missed them.

### A claim is a vector, not a distance

`Colony.influence_at()` took a scalar distance, which can only ever describe a circle.
Territory had already computed the offset vector and threw the direction away on the next
line. It now takes the whole offset and divides per axis by a `Faction.shape`, so a claim
can be a crust hugging the floor or a plume rising off a vent. Measured, the old circular
claim was a 922-unit disc inside a 1384-unit water column — it was not merely reading as
top-down, it was geometrically incapable of reading as anything else.

Two things fell out of that change:

**Anisotropy made the rebuild cheaper.** The search box is per-axis now, so a wide flat
strip or a tall narrow one both visit fewer cells than the square that bounded the old
disc.

**The claims had been rectangles all along.** Territory only visits cells within `REACH`
extents, and an inverse square has not decayed anywhere near `MIN_CLAIM` by then — at
biomass 130 the influence at the box edge was still 19 against a threshold of 3. Every
mature colony's territory was a hard-edged rectangle the size of its search box, which
the floor mask made obvious by clipping the bottom off it. Influence now tapers to
nothing over the outer quarter of the box, so the claim ends where the falloff says.

### Shares are fractions of the sea

Territory divided every share by `_cols * _rows`, ground included. A faction holding every
drop of water on the map could never report above 0.766, and `open_water()` counted bedrock
as open. Cells are masked once at startup — the floor never moves — and every share is
divided by the water cells. The earlier "32.8% of the map" figures were understated by
about 30% for this reason.

### Disasters travel along the border you can see

`bleach()` decided which colonies touched by comparing the sum of two radii against their
separation. That test could only describe circles, and it judged contact by geometry
nobody can see — two colonies whose discs overlapped counted as touching even with a third
faction's territory wedged between them. Adjacency is now built from shared territory-cell
edges during the same pass that paints them, so a bleach runs along the line on screen.

### Colony age survives a relaunch

It did not. `colony.gd`'s own docstring says age "is what makes a colony you have had for
six minutes a different thing from a fresh one", and the save wrote faction, position and
biomass only.

### Ground and water

The rule the faction scheme turns on: **water is only claimable above ground you hold.**

A **benthic** faction owns an interval of the seabed and extrudes a column of water upward
from it. Its strength is a rectangle you can read without any UI — *width* is how much
floor it holds, earned by growing and strictly zero-sum, since the seabed is 3240 units
long and every unit gained is a unit someone lost; *height* is capped by what the faction
is, so a reef never becomes a kelp forest. Two axes, two different actions.

A **pelagic** faction owns a band of open water and nothing permanent. Above the tallest
column everything is a commons, and only a shoal lives there — but a shoal with no reef
rooted on the floor beneath it bleeds `decay_unsupported` biomass a second. So the open
ocean is genuinely open, genuinely valuable, and genuinely indefensible. Support is
deliberately **any** benthic claim, not the shoal's own: a shoal riding a rival's floor is
the case worth having, because striking that reef starves the shoal several seconds later
and in a different part of the frame, without ever targeting it.

The roster that falls out:

| faction | grip | column | ground it can take |
| --- | ---: | ---: | --- |
| Coral | 3.4 | 430 | the shelf, above 0.82 of map height |
| Kelp Court | 1.4 | 1000 | almost any floor — a sliver of ground, most of the water |
| Vent | 1.1 | 1900 | the three ravines only |
| Deep Blue | — | band at 0.28 | the commons, while someone holds the floor below |

**The ravines are the strategic feature, and they were already drawn.** A vent is gated on
how deeply the ground is *carved*, not on how deep it is — depth cannot tell a basin from
the landform's own low ground, and the floor at x=0 is deeper than two of the three
basins. Carving picks out three discrete stretches, x 480-880, 1660-2020 and 2560-2940.
They are the deepest ground on the map, so a column rising out of one reaches higher than
anything else in the game. That is the payoff for being confined to 37% of the seabed.

Four things were wrong first, each found by looking at it:

**A shoal was drawing an anemone in mid-water.** Seating the colonies fixed the benthic
ones and left the pelagic ones hanging at their band altitude, still drawing the seabed
sprite — so the floating anemones the whole exercise was meant to remove came straight
back, in the one place the geometry could not fix them. A pelagic faction owns nothing
permanent, so it draws nothing: its claim is the band, and the fish it releases are what
you see. `colony_test` now asserts that anything drawing a sprite is on the floor.

**A column with a flat lid and full-width sides is a rectangle.** It drew as a block of
colour standing on the seabed. The claim now narrows as it rises — a reef is widest where
it is attached — and the taper is what stops it reading as architecture.

**A band that fades over one cell is a painted bar.** The pelagic vertical profile faded
over the outer sliver of its half-thickness, which at a 36-unit cell is about one cell.
It now fades over most of it.

**Pressure was measuring the wrong denominator.** `Territory.pressure_for` is
`owned / reached`, and `reached` counted every cell the search box touched rather than
every cell the colony could actually claim. A pelagic band is thin inside a box 2.4
extents tall, so it scored a structurally tiny pressure, its growth ceiling collapsed to
the `MIN_PRESSURE` floor, and a shoal shrank to a fifth of its size no matter how much
open water it held. "Reached" has to mean "what I would own if nobody opposed me".

The held seabed is painted as a bright rind rather than as more wash, because it is the
only zero-sum ground in the game and it is where every border between two benthic factions
actually is. It traces the terrain silhouette exactly, so you read the ground through the
colour.

Measured on the shipped map: a vent held 38.7% of the sea, was bleached for 103 biomass,
and went to 0.0% — while the kelp faction it had been crushing went 1.5% to 28.5%, flooding
up into the column it had been squeezed out of.

### Destruction takes time, and leaves a mark

An outside model was asked for feedback on screenshots of this, with no steer about what
to look for. Its sharpest finding: **the disaster is invisible.** The frame captured
immediately after a faction was destroyed was indistinguishable from the frame two minutes
later — "the consequence could just as easily be the result of the faction slowly losing
over time. The tap-to-destroy, which is your core player verb, has no visual payoff."

That was correct, and worse than it looked. `damage()` subtracted biomass, the colony fell
below `MIN_BIOMASS` inside the same call, and the territory pass a quarter-second later
simply showed a different owner. There was no moment of destruction to photograph because
there was no moment. The share numbers moved dramatically — 38.7% to 0.0% — and the
*frames* did not, which is the difference between a measurement and a clip.

Three changes, and none of them is an animation bolted on top:

**A wound drains rather than subtracts.** `damage()` now schedules biomass to bleed away
over `DRAIN_DURATION`. Because influence is proportional to biomass and the territory pass
runs four times a second throughout, the claim *retreats* instead of vanishing — the map
animates itself, with no animation code. The colony bleaches toward bone as it drains,
because size alone is not readable over a second and a half.

**A bleach travels.** The breadth-first search already knew each colony's hop distance from
the origin and threw it away, applying every colony's damage in the same call. A disaster
that is conceptually a thing *spreading* therefore arrived everywhere at once and could
never be watched spreading. Damage is now scheduled by hop, so the wave crosses the map at
`BLEACH_HOP_DELAY` a step. That cost one integer.

**Where it lands is marked.** `scripts/shockwave.gd` draws an expanding, fading ring —
geometry rather than art, for the same reason the UI glyphs are drawn. A strike is marked
whether or not it connects, because a tap that shows nothing is a tap the player cannot
tell from one the game missed.

### Lifting the blanket

The same review called the territory washes "a blanket thrown over your game" —
simultaneously the most visually dominant element and the least interesting one, flat
opaque fields burying the fish, the colonies and the terrain underneath.

The cause was arithmetic, not taste. Alpha was `MAX_ALPHA * sqrt(influence / FULL_INFLUENCE)`
against an absolute `FULL_INFLUENCE` of 40, and a mature colony carries a biomass of 130 —
so it was above that ceiling across nearly its whole claim and drew as a flat slab with a
thin fringe. Alpha is now taken relative to **each colony's own peak**, so every claim has a
centre and an edge, with an absolute term left in so a seedling still paints more faintly
than an established reef. `MAX_ALPHA` came down from 0.5 to 0.34.

`CELL` also went from 36 to 24 world units — 12,150 cells rather than 5,400. At 36 the
stair-stepping was plainly visible at the zoom a player actually holds, and the seabed
crust showed it worst because it traces a slope. **The rebuild cost under a full colony
load has not been measured at the finer size**, only that the test suite still passes.

### What a territory rebuild costs

`tools/territory_benchmark.gd`. The cell size was cut from 36 world units to 24 on how it
looked, with nobody knowing what it cost. It cost a great deal.

| | ns per cell visited | 40 colonies at CELL 24 |
| --- | ---: | ---: |
| as written | ~920 | ~212 ms (projected) |
| search box bounded to the real claim | ~920 | 136.7 ms |
| `REACH` 2.4 -> 1.7 | ~920 | 115.9 ms |
| packed arrays and a static kernel | **288** | **35.7 ms** |

35.7 ms four times a second is 14.3% of the machine at the worst case the cap allows —
forty colonies, every one of them mature. It is 6x cheaper than the same grid written the
obvious way, and still cheaper than the *coarser* grid was before any of this.

Three findings, and only one of them is about the cell size:

**The search box was 2.4x too tall.** Territory bounded its search at `extent * REACH` on
both axes. That is right laterally, where the inverse-square tail lives, and wrong
vertically, because a claim is hard zero above its lid and below the floor. A vent with a
1900-unit column had 4560 units of water scanned for it — the whole height of the map —
almost all of it cells it could never claim. Colonies now state their own non-zero region
through `reach_box()` rather than having Territory guess it.

**The cost was per-cell overhead, not cell count.** At ~920 ns for every cell looked at
against maybe a tenth of that in actual arithmetic, the rest was interpreter: an instance
method call, two `Vector2` constructions, and two `Dictionary` operations on every cell.
Ownership moved to `PackedInt32Array`/`PackedFloat32Array` indexed by cell, the per-colony
counters became locals, and the kernel became a static function taking plain floats.
288 ns/cell.

**Anisotropy really did make it cheaper**, as claimed earlier — but the claim was made
about a rebuild that was three times more expensive than it needed to be, which is not
much of a defence.

### Balance is measured, not eyeballed

`tools/balance.gd` runs many randomised starts and reports each faction's mean share, its
range, and how often it is wiped out.

It exists because balance was being read off `tools/colony_demo.gd`, which plants the same
factions at the same positions every run — so it measures the layout, not the factions. On
that fixed layout Kelp held 30% and Coral 4%, and two rounds of tuning went into "fixing"
a Coral that was not broken: it had been seeded between two rivals, and its other colony
sat at the map edge where it could only spread one way. Randomised, the same build reads
Coral 15.7% and Kelp 11.9%, and the actual outlier was the Vent at 32.4%.

Two real defects did come out of it:

**A faction was punished for succeeding.** Daughters were founded 1.2 extents from their
parent, well inside its 1.7-extent claim, so siblings spent their lives taking cells off
each other. Every cell a daughter took was one the parent had "lost", pressure collapsed
for both, and since spreading itself requires pressure above a half, whichever faction
spread first drove everyone's pressure down and locked the rest out permanently. The map
settled into stunted colonies at a quarter of their capacity. Daughters now clear the
parent's claim.

**Making pressure faction-wide is a runaway, and was tried.** Counting every cell a faction
holds anywhere as friendly means the more ground it has the faster it grows and spreads:
one faction pinned at pressure 1.00, reached thirty-six colonies and 55% of the sea while
every rival sat at 0.00 and died. Pressure stays per colony; the self-punishment is fixed
where it is caused.

After that, and dropping the vent's column from 1900 to 1400 — it still tops out highest
in the game, because it starts from the deepest ground — 20 runs of 7 simulated minutes:

| faction | mean share | range | wiped out |
| --- | ---: | :---: | ---: |
| Coral | 17.6% | 0.4-41.7% | 0/20 |
| Kelp Court | 17.0% | 0.1-36.0% | 0/20 |
| Vent | 15.0% | 0.0-37.5% | 0/20 |
| Deep Blue | 15.1% | 8.5-18.9% | 0/20 |

The ranges are wide on purpose: where you are seeded matters, and three basins is a small
number to share. What matters is that the means are within 2.6 points and nothing is
eliminated.

## Multiple aquariums

Tanks are slots on disk:

```
user://tanks/index.json   the slot list, and which one is active
user://tanks/<id>.json    one tank
```

**A new aquarium opens empty.** The player fills it by tapping the water, and the dock's
hint line is the instruction. It used to be stocked with 55 fish — the sum of every
species' `starting_count` — which made "start a new aquarium" mean "start someone
else's". `Aquarium.seed_starting_population()` still exists, but nothing in the app
calls it: it is how the simulation tests and `tools/screenshot.gd` stand a tank up.

An emptied tank stays empty across an absence, too. `Offline.project()` returns a
population of zero unchanged, so no length of absence conjures a fish from nothing.

The Tanks button lists them with live fish counts, switches, creates and deletes. A new
tank takes the first "Aquarium N" that is free rather than one past the slot count,
which repeated a name as soon as a tank was deleted.
Switching saves the current tank first, then reloads the scene — the Aquarium already
builds itself from the active slot in `_ready`, so there is no second "load a different
tank" path that could drift from the one used at launch. Deleting the only tank is
refused, since it would leave the app with nowhere to save.

A pre-slots `user://tank.json` is migrated into a slot named "My Aquarium" rather than
stranded.

Offline progression is per-slot: each tank carries its own `saved_at`, so a tank left
alone for a week catches up on its own terms while the others do not.

## Offline progression

The tank is credited for time the app was closed, as a population model rather than a
fast-forwarded simulation — see `scripts/systems/offline.gd` for why. Absences are capped
at 8 hours and guarded against a clock that moved backwards.

A long absence is a generational turnover: the target population is computed from who was
alive during the absence, the old are reaped, and the shortfall is made up by their
descendants with ages spread across the run-up to maturity. Done in the other order, a
three-hour absence returned a tank containing one immortal shark.

**Saving does not rely on being told the app is closing.** On iOS, backgrounding produced
no `NOTIFICATION_APPLICATION_PAUSED` at the node and wrote no save — measured on an
iPhone 17 Pro simulator, with the platform log confirming the scene had backgrounded. A
mobile OS can also kill a suspended app outright. `autosave_interval` (15s) is the
mechanism; the lifecycle hooks are a bonus.

## Tests

A headless functional check of spawning, movement, tank bounds and predation:

```bash
godot --headless --script res://test/smoke_test.gd
```

Ten files, all run by CI:

| test | covers |
| --- | --- |
| `smoke_test` | spawning, movement, bounds, predation, pause, selection, tap-to-spawn, safe-area insets, save/restore round trip |
| `bite_test` | a predator catches with its mouth, not its centre or its tail |
| `slots_test` | slots, switching, renaming, deletion, migration |
| `offline_test` | the offline population model in isolation |
| `offline_restore_test` | a real absence, including one longer than any fish lives |
| `ecosystem_test` | 15 simulated minutes; the tank must neither die out nor run away |
| `feeding_test` | pellets sink, hungry fish eat, full fish and sharks ignore them, hunger slows breeding |
| `settings_test` | the mute survives a relaunch |
| `edit_test` | undo, remove mode, and what must NOT be undoable |
| `shelter_test` | prey hides in cover, and does not flee the cover it is already in |

Tests disable `autosave_interval`. Several tanks can be alive at once in a test, and each
writing to the same save made the suite flaky — a run would fail three checks and then
pass unchanged on the next invocation.

The smoke test's UI checks are the ones that catch an overhaul: every visible control
inside the viewport, every blocking control declared in `ui_blocker`, the middle of the
tank tappable, the switcher closed at launch, and the safe-area arithmetic — including
the desktop-shaped safe area that must be capped rather than obeyed.

**Not covered by tests:** the Android build (verified by hand on an emulator, not in CI —
the runner would need the whole SDK), and the delete-confirmation dialog, which is a
Godot `ConfirmationDialog` and cannot be driven headlessly. `slots_test` covers the
store-level delete and rename it wraps.

CI runs the suite on every push and pull request. Note that `godot --script` exits **0** on a
script parse error — measured, not assumed — so a broken test file would otherwise pass
silently. The workflow greps for the test's own `RESULT: PASS` line; that is what
actually gates the build.

## Persistence

The tank is written to `user://tank.json` when the app closes or is backgrounded, and
restored on launch. When there is nothing to restore the tank simply opens empty —
nothing is seeded.

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
| Android | **works**; APK runs on an emulator, OpenGL ES 3.1 |

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

### Android

Builds and runs. The toolchain installs entirely in user space, so none of it needs a
password:

```bash
# JDK 17 to ~/.jdks/temurin17, Android SDK to ~/Library/Android/sdk
# then point Godot at both in editor_settings-4.6.tres:
#   export/android/android_sdk_path, export/android/java_sdk_path,
#   export/android/debug_keystore (+ _user / _pass)
godot --headless --export-debug "Android" build/android/Aquarium.apk
adb install -r build/android/Aquarium.apk
```

Two traps worth knowing. Godot's editor settings are versioned — 4.6 reads
`editor_settings-4.6.tres`, and writing `editor_settings-4.tres` gets you "A valid Java
SDK path is required" with a perfectly valid JDK sitting at the path you set. And a debug
keystore has to exist; `keytool -genkeypair` makes one.

Verified on a Pixel 7 emulator running Android 14: the app launches, reports
`OnGodotMainLoopStarted`, picks OpenGL ES 3.1, and runs the full tank at 94 fish.

### A renderer note

A Godot maintainer notes on that thread that OpenGL on iOS "is deprecated for a long
time... Apple can remove it in any iOS update or stop accepting apps using it". That is
worth knowing before shipping to the App Store, and a released iOS build probably wants
`rendering/renderer/rendering_method.mobile="mobile"` (Metal) with web staying on
`gl_compatibility` — but note that this would end simulator testing, since Metal is
exactly what the simulator cannot do.

## Interface

Everything the controls are made of comes from one generated theme,
`resources/ui/aquarium_theme.tres`. It is written by `tools/generate_theme.gd` rather
than authored, for the same reason the species resources are: a `StyleBoxFlat`
serialises to two dozen opaque keys and an exported array of them cannot be hand-written
at all. **Edit that script and re-run it** — editing the `.tres` is editing a build
artefact.

```bash
godot --headless --script res://tools/generate_theme.gd
```

The palette is the app icon's: deep water, and the accent is the icon's clownfish
orange. Every surface is translucent, because the tank is the content — an opaque bar
over it would be a chrome app with an aquarium inside rather than an aquarium with
controls floating on it.

### Sizes are in points, not units

The project lays out in a 720-unit-wide viewport and ships to a phone about 400 points
wide, so **one unit is about 0.56 of a point**. This is not a detail. Sized as though a
unit were a pixel, the 48-unit buttons measured **27 points** across on an iPhone 17
Pro — every control was around 60% of the size it looked in a desktop window, and the
body font came out under 10 points. The theme now writes its metrics in points and
converts through `UNITS_PER_POINT`, so they can be checked against a human-factors
guideline (44pt minimum touch target) instead of against a screenshot.

The lesson generalises: **a desktop window at a different scale is not a preview.** Both
of the sizing bugs above looked correct in the 540x960 window and wrong on the phone.

### The picker scrolls, and its tiles pass touches

The roster is eight entries and growing; a row of text buttons stopped fitting a phone's
width at six. The strip is a `ScrollContainer`, and each tile sets
`MOUSE_FILTER_PASS` rather than the `Button` default of STOP — a control that stops the
press keeps every later event in the gesture too, so a swipe beginning on a tile (which
is most of the strip) never reaches the `ScrollContainer` and the picker could not be
scrolled by the only means a phone has. Verified on the simulator: the same drag scrolls
with PASS and does nothing with STOP.

### Blocking taps is declared, not assumed

A `Control` defaults to `MOUSE_FILTER_STOP`, and one full-rect container left at the
default silently swallows every tap meant for the tank — fish just stop spawning, with
no error. Containers that must not block set `mouse_filter = 2` (IGNORE).

Some controls block on purpose: the dock, the population chip, the switcher. Those join
the **`ui_blocker` group**, and `test/smoke_test.gd` asserts that every visible blocking
control is declared *and* that the blockers together leave the middle of the screen
tappable — declaring one is not enough, or a dock that grew to fill the view would pass
by being honest about it.

### Safe area is only asked of handhelds

`DisplayServer.get_display_safe_area()` means "the part of the screen a notch does not
cover" on iOS and Android. On macOS it means the screen minus the menu bar and the
Dock — 66 and 180 in screen pixels, wherever the window happens to be. Fed into the
layout that produced a 330-unit-tall control bar over a 1280-unit tank.

So `TankUI` asks only on iOS and Android, and `safe_insets` additionally caps each inset
at 12% of that screen dimension. An iPhone 15 Pro's notch and home indicator are 5.5%
each, so the cap is generous for anything a phone reports and rejects a platform that
means something else by the phrase.

The dock's *panel* is deliberately not inset: the bar runs to the bottom of the glass,
under the home indicator, and only its contents step up out of the way. Insetting the
panel too leaves a strip of bare tank below a floating bar.

### Looking at it

```bash
godot --script res://tools/screenshot.gd -- --out-dir /tmp/shots
```

Runs the tank in a window, lets it settle, and captures three states — the tank, the
picker scrolled to its end, and the switcher — in one run. Several shots per run rather
than one relaunch each, because the controls are only worth judging over moving water
and a fresh tank behind every shot makes two of them impossible to compare.

## Layout notes

The tank is a map — 3240x2160 world units, several screens wide — not the viewport. The
camera shows a portrait slice and pans across it, so fish swim to the edge of the *map*
while the view moves independently. On a portrait phone the camera frames roughly 37% of
the map's width at its widest zoom.

`tools/art/draw_background.py` draws the terrain: a gently undulating sea floor, a
hazier ridge behind it, rocks and coral bedded into the ground, and stands of kelp.

The floor has real relief — rolling ground with dips cut into it — and objects sit on it
correctly. Three things make that work, and each replaced something that did not:

**The floor is drawn last, over everything standing on it.** Rocks, kelp and coral are
drawn first and buried, so the floor occludes whatever falls below the surface at every
column. That is what removes floating and contact gaps outright: no object has to know
the ground's shape to sit on it.

**A mound tilts, it does not trace.** The ground is sampled at the rock's left and right
edges and the shape is tilted along that line. A flat-bottomed mound seated at one
sampled y lifts off the ground at one end on any gradient; a crown tracing the ground
column by column never floats but stretches into a smear several times its own size on a
slope. The lean is also clamped, because across a cliff the two samples differ by far
more than the rock is tall.

**Kelp blades each sample their own x.** A stand spanning a gradient follows it instead
of standing on one shared level.

There is no separate dark layer behind the dips. One existed to stop a dip revealing the
lighter ridge behind it, but it filled the whole uncarved landform, so a dip showed dark
fill rising to the uncarved crest and read as a dark hill in front of the floor rather
than a cut into it. A dip is now simply a dip in the silhouette.

Rocks must also be darker than the floor they stand on, and the far ones drawn *before*
the near floor, or they read as pale slabs lying on top of the landscape.

Populations scale with the map: it is roughly 3.4x the area of the original
single-screen tank, so the same on-screen density needs proportionally more fish.

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

**The UI glyphs are drawn too.** `tools/art/draw_ui_icons.py` writes the speaker, pause,
play, tank, close, feed and fish glyphs to `assets/textures/ui/` as flat white on
transparent, so the theme tints them and nothing here has to know about a disabled or
accented state. A speaker and a pause bar are geometry, and a generated one comes back
at a different weight every time.

```bash
python3 tools/art/draw_ui_icons.py
```

Each is drawn at 4x and reduced with Lanczos; PIL's `ellipse` and `polygon` are
hard-edged and a 48px speaker drawn directly is a staircase on a phone. Two were
re-drawn after looking at them at the size they are actually used: the switcher's first
glyph was two offset rounded rectangles, which is the universal *copy* icon and read as
exactly that, and the population chip's fish was an ellipse with a triangle stuck to it,
which reads as a **video camera** at 26px. Points at both ends — the body is the overlap
of two circles — and a punched-out eye are what make it a fish.

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
