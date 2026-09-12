extends SceneTree
## One-shot generator for the starting FishSpecies resources.
## Run: godot --headless --script res://tools/generate_species.gd

func _initialize() -> void:
	var clownfish := _make("Clownfish", "res://assets/textures/clown.png", 55.0, 36.0, 140.0)
	_save(clownfish, "clownfish")

	var anemonefish := _make("Anemonefish", "res://assets/textures/nemo.png", 48.0, 44.0, 130.0)
	_save(anemonefish, "anemonefish")

	var shark := _make("Shark", "res://assets/textures/shark.png", 110.0, 90.0, 260.0)
	shark.eats = [
		load("res://resources/species/clownfish.tres"),
		load("res://resources/species/anemonefish.tres"),
	]
	_save(shark, "shark")

	quit()

func _make(name: String, texture_path: String, speed: float, size: float, sight: float) -> FishSpecies:
	var species := FishSpecies.new()
	species.display_name = name
	species.texture = load(texture_path)
	species.speed = speed
	species.size = size
	species.sight = sight
	return species

func _save(species: FishSpecies, file_name: String) -> void:
	var path := "res://resources/species/%s.tres" % file_name
	var err := ResourceSaver.save(species, path)
	print("%s -> %s (err %d)" % [species.display_name, path, err])
