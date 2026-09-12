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

@export_group("Diet")
## Species this fish hunts. The reverse (who hunts this fish) is derived at
## runtime by Aquarium, so predator/prey never fall out of sync.
@export var eats: Array[FishSpecies] = []
