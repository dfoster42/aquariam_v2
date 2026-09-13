extends SceneTree
## One-shot generator for the starting FishSpecies resources.
## Run: godot --headless --script res://tools/generate_species.gd
##
## The values here are the tuned ones, not first guesses, and test/ecosystem_test.gd is
## what tuned them. Prey breed and are eaten; sharks do neither, so the tank settles
## instead of draining to zero.
##
## Lifespans are in the tens of minutes, not the single minutes they were first tuned to
## against a 15-minute test. An absence is measured in hours, and a fish that lives seven
## minutes means every adult is dead before the app is next opened.
##
## Capacities are set for what looks right on a phone, not for what the engine can carry:
## the tank fills to the sum of the prey capacities within a few minutes and holds there,
## so those numbers are the population the player actually sees.

func _initialize() -> void:
	var clownfish := _make("Clownfish", "res://assets/textures/clownfish.png", 80.0, 36.0, 140.0)
	clownfish.maturity = 25.0
	clownfish.breed_cooldown = 22.0
	clownfish.breed_distance = 170.0
	clownfish.capacity = 18
	clownfish.starting_count = 8
	clownfish.lifespan = 1800.0
	_save(clownfish, "clownfish")

	var anemonefish := _make("Anemonefish", "res://assets/textures/anemonefish.png", 72.0, 44.0, 130.0)
	anemonefish.maturity = 30.0
	anemonefish.breed_cooldown = 26.0
	anemonefish.breed_distance = 170.0
	anemonefish.capacity = 14
	anemonefish.starting_count = 6
	anemonefish.lifespan = 2100.0
	_save(anemonefish, "anemonefish")

	# breed_distance 0: sharks never pair. A predator that breeds on the same terms as
	# its prey overruns the tank, and arriving only by tap keeps the player in charge
	# of how much pressure the tank is under.
	var shark := _make("Shark", "res://assets/textures/shark.png", 95.0, 90.0, 200.0)
	shark.maturity = 40.0
	shark.breed_distance = 0.0
	shark.capacity = 8
	shark.starting_count = 1
	shark.lifespan = 0.0
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
