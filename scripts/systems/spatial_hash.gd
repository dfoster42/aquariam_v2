class_name SpatialHash
extends RefCounted
## Uniform grid for broad-phase neighbour lookups.
##
## Replaces the O(n^2) all-pairs scan the original Go engine ran every tick.
## Rebuilt once per frame by Aquarium, then queried by each fish, so cost grows
## with local density rather than total population.

var _cell_size: float
var _cells: Dictionary = {}

func _init(cell_size: float = 200.0) -> void:
	_cell_size = maxf(cell_size, 1.0)

## Drops all buckets. Call once per frame before re-inserting.
func clear() -> void:
	_cells.clear()

func insert(item: Node2D) -> void:
	var key := _key(item.global_position)
	if not _cells.has(key):
		_cells[key] = []
	_cells[key].append(item)

## Returns every inserted item whose centre lies within `radius` of `centre`,
## excluding `exclude`. Items are not sorted by distance.
func query_radius(centre: Vector2, radius: float, exclude: Node2D = null) -> Array[Node2D]:
	var found: Array[Node2D] = []
	if radius <= 0.0:
		return found

	var min_cell := _key(centre - Vector2(radius, radius))
	var max_cell := _key(centre + Vector2(radius, radius))
	var radius_sq := radius * radius

	for cx in range(min_cell.x, max_cell.x + 1):
		for cy in range(min_cell.y, max_cell.y + 1):
			var bucket: Array = _cells.get(Vector2i(cx, cy), [])
			for item: Node2D in bucket:
				if item == exclude or not is_instance_valid(item):
					continue
				if centre.distance_squared_to(item.global_position) <= radius_sq:
					found.append(item)
	return found

func _key(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / _cell_size), floori(point.y / _cell_size))
