extends Node
## 水坑终验（新水位 -2m + 水色修正）

const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout
	var ws: float = Terrain.params.world_size
	var sz: int = Terrain.heightmap_img.get_width()
	var wc: Vector2 = TerrainBrush.world_to_pixel(Vector3(120, 0, 105), ws, sz)
	var wr: float = TerrainBrush.world_radius_to_pixel(8.0, ws, sz)
	TerrainBrush.apply(Terrain.heightmap_img, wc, wr, 0.28, TerrainBrush.Mode.LOWER, 0.0)
	Terrain.heightmap_tex.update(Terrain.heightmap_img)
	Terrain._refresh_biome_from_height()
	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null and cam.has_method("focus_on"):
		cam.focus_on(Vector3(120, 0, 105))
		if "_distance" in cam:
			cam.set("_distance", 15.0)
		await get_tree().create_timer(1.8).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_water_close.png")
		print("[SHOT] saved, 坑底 %.2fm / 水面 %.1fm" % [Terrain.get_height(120, 105), Terrain.params.water_level])
	get_tree().quit(0)
