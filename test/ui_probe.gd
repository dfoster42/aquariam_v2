extends SceneTree

var _started := false

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		root.add_child(load("res://scenes/main.tscn").instantiate())
		return false
	var ui := root.get_node("Main/UI")
	print("viewport: ", root.get_visible_rect().size)
	var queue: Array = [ui]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		for c in n.get_children():
			queue.push_back(c)
		var ctl := n as Control
		if ctl == null:
			print("  (%s) %s" % [n.get_class(), n.name])
			continue
		print("  %-12s %-10s rect=%s min=%s vis=%s filter=%d" % [
			ctl.name, ctl.get_class(), ctl.get_rect(), ctl.get_combined_minimum_size(),
			ctl.visible, ctl.mouse_filter])
	return true
