extends Node
## 水面验证探针 v4：挖湖+刻河，正常水面 (-5m) 截图。

const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout
	var ws: float = Terrain.params.world_size
	var img: Image = Terrain.heightmap_img
	var sz: int = img.get_width()
	# 挖湖：中心 (82,92) 半径 11m，压低 8.8m → 湖底 -6.9m（水下 1.9m）
	var c1: Vector2 = TerrainBrush.world_to_pixel(Vector3(82, 0, 92), ws, sz)
	var r1: float = TerrainBrush.world_radius_to_pixel(11.0, ws, sz)
	TerrainBrush.apply(img, c1, r1, 0.55, TerrainBrush.Mode.LOWER, 0.0)
	# 刻河：向南一串重叠坑，压到 -5.4m
	var zz: float = 100.0
	while zz < 152.0:
		var c2: Vector2 = TerrainBrush.world_to_pixel(Vector3(82, 0, zz), ws, sz)
		var r2: float = TerrainBrush.world_radius_to_pixel(5.5, ws, sz)
		TerrainBrush.apply(img, c2, r2, 0.46, TerrainBrush.Mode.LOWER, 0.0)
		zz += 4.0
	Terrain.heightmap_tex.update(img)
	print("[SHOT] 湖底 %.2fm / 河底 %.2fm / 水面 %.1fm" % [
		Terrain.get_height(82, 92), Terrain.get_height(82, 120), Terrain.params.water_level])
	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null:
		if cam.has_method("focus_on"):
			cam.focus_on(Vector3(82, 0, 100))
		if "_distance" in cam:
			cam.set("_distance", 42.0)
		await get_tree().create_timer(2.2).timeout
	get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_water.png")
	get_tree().quit(0)
