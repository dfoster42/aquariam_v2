class_name TankHistory
extends RefCounted
## The player's recent placements and removals, so they can be taken back.
##
## Not a stack of snapshots. The tank is a running simulation — a fish added a minute ago
## may since have bred, been eaten, or died of old age — so an entry records the ACTION
## rather than the world, and undoing one means "take that object back out if it is still
## there" or "put that object back". Restoring whole states would make undo silently
## revive everything that had died in between, which is a different and much stranger
## promise than the button makes.
##
## This class knows about Nodes and Dictionaries and nothing about the tank. Aquarium
## interprets the entries; keeping the interpretation there avoids two `class_name`
## scripts referring to each other.

enum Action { ADDED, REMOVED }

## How far back undo reaches. Deep enough to cover a burst of taps, shallow enough that
## the entries cannot accumulate without bound in a tank left open for days.
const MAX_ENTRIES: int = 60

var _entries: Array[Dictionary] = []

func clear() -> void:
	_entries.clear()

## Records that `node` was just placed. The instance id is kept beside the reference so
## a later entry can be re-pointed at a replacement — see `replace_node`.
func note_added(node: Node2D) -> void:
	if node == null:
		return
	_push({"action": Action.ADDED, "node": node, "id": node.get_instance_id()})

## Records that something was just taken out, with everything needed to put it back.
## `was_id` is the removed node's instance id, so undoing this entry can re-point any
## older ADDED entry that referred to it.
func note_removed(data: Dictionary, was_id: int) -> void:
	var entry := data.duplicate()
	entry["action"] = Action.REMOVED
	entry["was_id"] = was_id
	_push(entry)

func _push(entry: Dictionary) -> void:
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)

## Drops entries from the top that can no longer be undone.
##
## Only an ADDED entry goes stale, and only by the tank itself: the fish was eaten, or
## aged out. Pruning from the top alone is enough for the button's state and is O(1)
## amortised — an older stale entry is reached, and dropped, only once undo gets to it.
func prune() -> void:
	while not _entries.is_empty() and not _is_live(_entries[-1]):
		_entries.pop_back()

func can_undo() -> bool:
	prune()
	return not _entries.is_empty()

## The next entry to act on, or an empty dictionary. Removes it from the stack.
func take() -> Dictionary:
	prune()
	if _entries.is_empty():
		return {}
	return _entries.pop_back()

## Re-points every ADDED entry that referred to `old_id` at `node`.
##
## Undoing a removal creates a *new* instance, so without this the sequence "place a
## fish, delete it, undo, undo" leaves the fish in the tank: the second undo would find
## an ADDED entry naming the freed original, judge it stale, and drop it.
func replace_node(old_id: int, node: Node2D) -> void:
	if node == null:
		return
	for entry in _entries:
		if entry.get("action") == Action.ADDED and int(entry.get("id", 0)) == old_id:
			entry["node"] = node
			entry["id"] = node.get_instance_id()

## A REMOVED entry is always actionable. An ADDED one is live while its node is still in
## the tree: removal detaches immediately, so `is_inside_tree` answers this on the same
## frame, where `is_instance_valid` stays true until the queued free actually runs.
static func _is_live(entry: Dictionary) -> bool:
	if entry.get("action") != Action.ADDED:
		return true
	var node: Node2D = entry.get("node")
	return is_instance_valid(node) and node.is_inside_tree()

func size() -> int:
	return _entries.size()
