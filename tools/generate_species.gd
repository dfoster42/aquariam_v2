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
## Prey see further than the shark does (240 and 230 against 150). That is the lever
## that makes the tank survive a predator which actually connects: prey break for open
## water before the shark has even registered them, so a catch takes a long pursuit or a
## cornering against the glass rather than being the default outcome of proximity.
##
## Capacities are set for what looks right on a phone, not for what the engine can carry:
## the tank fills to the sum of the prey capacities within a few minutes and holds there,
## so those numbers are the population the player actually sees. They scale with the
## world: the map is roughly 3.4x the area of the original single-screen tank, and the
## camera shows about 40% of its width at once, so the same on-screen density needs
## proportionally more fish in total.

func _initialize() -> void:
	var clownfish := _make("Clownfish", "res://assets/textures/clownfish.png", 80.0, 36.0, 240.0)
	clownfish.maturity = 25.0
	clownfish.breed_cooldown = 22.0
	clownfish.breed_distance = 170.0
	clownfish.capacity = 46
	clownfish.starting_count = 20
	clownfish.hunger_time = 600.0
	clownfish.hungry_below = 0.6
	clownfish.lifespan = 1800.0
	_save(clownfish, "clownfish")

	var anemonefish := _make("Anemonefish", "res://assets/textures/anemonefish.png", 74.0, 44.0, 230.0)
	anemonefish.maturity = 30.0
	anemonefish.breed_cooldown = 26.0
	anemonefish.breed_distance = 170.0
	anemonefish.capacity = 34
	anemonefish.starting_count = 14
	anemonefish.hunger_time = 660.0
	anemonefish.hungry_below = 0.6
	anemonefish.lifespan = 2100.0
	_save(anemonefish, "anemonefish")

	var angelfish := _make("Angelfish", "res://assets/textures/angelfish.png", 66.0, 52.0, 210.0)
	angelfish.maturity = 34.0
	angelfish.breed_cooldown = 30.0
	angelfish.breed_distance = 160.0
	angelfish.capacity = 22
	angelfish.starting_count = 8
	angelfish.lifespan = 2400.0
	angelfish.hunger_time = 700.0
	angelfish.hungry_below = 0.6
	_save(angelfish, "angelfish")

	# Small, quick and skittish: the hardest of the prey for a shark to run down, and
	# the one that most obviously uses cover.
	var yellowtang := _make("Yellow Tang", "res://assets/textures/yellowtang.png", 92.0, 40.0, 260.0)
	yellowtang.maturity = 26.0
	yellowtang.breed_cooldown = 24.0
	yellowtang.breed_distance = 175.0
	yellowtang.capacity = 26
	yellowtang.starting_count = 10
	yellowtang.lifespan = 1900.0
	yellowtang.hunger_time = 560.0
	yellowtang.hungry_below = 0.6
	_save(yellowtang, "yellowtang")

	# breed_distance 0: sharks never pair. A predator that breeds on the same terms as
	# its prey overruns the tank, and arriving only by tap keeps the player in charge
	# of how much pressure the tank is under.
	# Slower and shorter-sighted than the first pass. Once hunting steered the shark's
	# mouth onto its prey rather than its centre, the same numbers took the tank from
	# 16 fish to 3: a predator that actually connects needs far less of an edge.
	var shark := _make("Shark", "res://assets/textures/shark.png", 86.0, 90.0, 150.0)
	shark.maturity = 40.0
	shark.breed_distance = 0.0
	shark.capacity = 12
	shark.starting_count = 3
	# Sharks are driven by prey, not pellets: hunger_time 0 means never hungry, so they
	# ignore food and keep hunting.
	shark.hunger_time = 0.0
	shark.lifespan = 0.0
	shark.eats = [
		load("res://resources/species/clownfish.tres"),
		load("res://resources/species/anemonefish.tres"),
		load("res://resources/species/angelfish.tres"),
		load("res://resources/species/yellowtang.tres"),
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
