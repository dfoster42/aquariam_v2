class_name DecorKind
extends Resource
## Data-driven definition of something the player can place in the tank.
##
## Same shape as FishSpecies: one .tres per item, dropped into an exported array, no
## code per item.

@export var display_name: String = "Plant"
@export var texture: Texture2D

@export_group("Appearance")
## On-screen height in pixels; width follows the texture's aspect ratio.
@export_range(8.0, 1024.0, 1.0) var size: float = 180.0
## Drawn behind the fish when false. Most scenery is background; a foreground item
## occludes fish swimming past it.
@export var in_front: bool = false

@export_group("Shelter")
## How far from this item's centre prey is hidden from predators. 0 means the item is
## scenery only.
@export_range(0.0, 400.0, 5.0) var shelter_radius: float = 0.0
