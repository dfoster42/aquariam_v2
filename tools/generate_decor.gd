extends SceneTree
## One-shot generator for the starting DecorKind resources.
## Run: godot --headless --script res://tools/generate_decor.gd

func _initialize() -> void:
	var kelp := DecorKind.new()
	kelp.display_name = "Kelp"
	kelp.texture = load("res://assets/textures/kelp.png")
	kelp.size = 300.0
	# Roughly the plant's own drawn width, so cover looks like the plant rather than an
	# invisible bubble around it.
	kelp.shelter_radius = 130.0
	ResourceSaver.save(kelp, "res://resources/decor/kelp.tres")

	var anemone := DecorKind.new()
	anemone.display_name = "Anemone"
	anemone.texture = load("res://assets/textures/anemone.png")
	anemone.size = 150.0
	anemone.shelter_radius = 90.0
	ResourceSaver.save(anemone, "res://resources/decor/anemone.tres")

	print("decor saved")
	quit()
