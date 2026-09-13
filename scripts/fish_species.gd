class_name FishSpecies
extends Resource
## Data-driven definition of a single aquarium species.
##
## Each species is a .tres file under res://resources/species/. Adding a new
## fish requires no code — create a resource, set its texture and stats, and
## list which other species it preys on.

@export var display_name: String = "Fish"
@export var texture: Texture2D

@export_group("Movement")
## Pixels travelled per second.
@export_range(0.0, 500.0, 1.0) var speed: float = 30.0
## On-screen height in pixels; width follows the texture's aspect ratio.
@export_range(4.0, 512.0, 1.0) var size: float = 48.0

@export_group("Senses")
## Radius in pixels within which this species notices predators and prey.
@export_range(0.0, 1000.0, 1.0) var sight: float = 100.0

@export_group("Life cycle")
## Seconds from birth to death of old age. 0 means the species does not age out.
@export_range(0.0, 3600.0, 5.0) var lifespan: float = 0.0
## Seconds before a fish can breed. Also the age at which it reaches full size.
@export_range(0.0, 600.0, 1.0) var maturity: float = 45.0
## Seconds a parent must wait between spawnings.
@export_range(1.0, 600.0, 1.0) var breed_cooldown: float = 40.0
## How close two mature adults must be to pair. 0 disables breeding entirely,
## which is how a predator is kept from multiplying without being fed.
@export_range(0.0, 400.0, 5.0) var breed_distance: float = 0.0
## Carrying capacity for this species. Breeding stops at the cap; the tank does not.
@export_range(0, 500, 1) var capacity: int = 40
## How many of this species a fresh tank opens with. Seeding an equal number of every
## species gives a new tank as many sharks as clownfish, and the prey are eaten before
## any of them can pair.
@export_range(0, 100, 1) var starting_count: int = 3

@export_group("Diet")
## Species this fish hunts. The reverse (who hunts this fish) is derived at
## runtime by Aquarium, so predator/prey never fall out of sync.
@export var eats: Array[FishSpecies] = []
