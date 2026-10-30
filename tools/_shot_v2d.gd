extends Node
## 终验：岩壁（新雪线）/ 水坑（-2m 新水位）

const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _ed = null

func _snap(cam: Node3D, pos: Vector3, dist: float, path: String) -> void:
	if cam.has_method("focus_on"):
		cam.focus_on(pos)
	if "_distance" in cam:
		cam.set("_distance", dist)
	await get_tree().create_timer(1.8).timeout
	get_viewport().get_texture().get_image().save_png(path)
	print("[SHOT] saved ", path)

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout
	var ws: float = Terrain.params.world_size
	var sz: int = Terrain.heightmap_img.get_width()
	var hc: Vector2 = TerrainBrush.world_to_pixel(Vector3(190, 0, 100), ws, sz)
	var hr: float = TerrainBrush.world_radius_to_pixel(14.0, ws, sz)
	TerrainBrush.apply(Terrain.heightmap_img, hc, hr, 1.30, TerrainBrush.Mode.RAISE, 0.0)
	var wc: Vector2 = TerrainBrush.world_to_pixel(Vector3(120, 0, 105), ws, sz)
	var wr: float = TerrainBrush.world_radius_to_pixel(8.0, ws, sz)
	TerrainBrush.apply(Terrain.heightmap_img, wc, wr, 0.28, TerrainBrush.Mode.LOWER, 0.0)
	Terrain.heightmap_tex.update(Terrain.heightmap_img)
	Terrain._refresh_biome_from_height()
	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null:
		await _snap(cam, Vector3(190, 0, 100), 36.0, "C:/Users/shy/桌面/Godot/_shot_rock_close.png")
		await _snap(cam, Vector3(120, 0, 105), 15.0, "C:/Users/shy/桌面/Godot/_shot_water_close.png")
	get_tree().quit(0)
