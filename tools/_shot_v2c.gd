extends Node
## 补拍：更陡的山（CC0岩壁）/ 森林超近 / 水坑

const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")
const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _ed = null

func _snap(cam: Node3D, pos: Vector3, dist: float, path: String) -> void:
	if cam.has_method("focus_on"):
		cam.focus_on(pos)
	if "_distance" in cam:
		cam.set("_distance", dist)
	await get_tree().create_timer(1.8).timeout
	get_viewport().get_texture().get_image().save_png(path)

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout
	var ws: float = Terrain.params.world_size
	var sz: int = Terrain.heightmap_img.get_width()
	for cc in [Vector2(95, 130), Vector2(112, 138), Vector2(82, 142)]:
		var c3: Vector2 = TerrainBrush.world_to_pixel(Vector3(cc.x, 0, cc.y), ws, Terrain.SPLAT_SIZE)
		var r3: float = TerrainBrush.world_radius_to_pixel(13.0, ws, Terrain.SPLAT_SIZE)
		SplatBrush.apply(Terrain.splat_img, c3, r3, SplatBrush.Layer.FOREST, 1.0)
	Terrain.refresh_splat_texture()
	# 更陡的山：半径 14m，抬 1.3（≈20.8m，贴住高度域上限）
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
		await _snap(cam, Vector3(96, 0, 134), 10.0, "C:/Users/shy/桌面/Godot/_shot_forest_close.png")
		await _snap(cam, Vector3(190, 0, 100), 38.0, "C:/Users/shy/桌面/Godot/_shot_rock_close.png")
		await _snap(cam, Vector3(120, 0, 105), 15.0, "C:/Users/shy/桌面/Godot/_shot_water_close.png")
	get_tree().quit(0)
