extends Node3D
var m = null
var t = 0
func _ready():
	m = load("res://scenes/Main.tscn").instantiate()
	add_child(m)
func _process(_d):
	t += 1
	if t != 40:
		return
	# 找一块离基地 10 米左右、可建的空地
	var g = GameManager.grid
	var best = null
	for gx in range(10, g.map_size.x - 6, 2):
		for gz in range(10, g.map_size.y - 6, 2):
			var p = Vector2i(gx, gz)
			if g.is_placeable(p, Vector2i(2, 2)):
				best = p
				break
		if best != null:
			break
	print("[BUILD] 候选格=", best, " 可建=", (g.is_placeable(best, Vector2i(2,2)) if best != null else false))
	var wp: Vector3 = g.grid_to_world(best)
	print("[BUILD] 目标世界坐标=", wp)
	m.start_build_mode("house")
	print("[BUILD] build_mode 已进入=", m._build_mode)
	m._place_building("house", wp)
	print("[BUILD] 建筑数=", GameManager.all_buildings.size())
	get_tree().quit()
