extends Node
## 综合验证：蜿蜒土路+石板路+森林+新水位(-2m)+CC0岩壁

const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")
const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _ed = null

func _stroke_line(pts: Array, radius: float, layer: int) -> void:
	var ws: float = Terrain.params.world_size
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var steps: int = int(a.distance_to(b) / 1.5)
		for s in range(steps + 1):
			var p: Vector2 = a.lerp(b, float(s) / max(steps, 1))
			var c: Vector2 = TerrainBrush.world_to_pixel(Vector3(p.x, 0, p.y), ws, Terrain.SPLAT_SIZE)
			var r: float = TerrainBrush.world_radius_to_pixel(radius, ws, Terrain.SPLAT_SIZE)
			SplatBrush.apply(Terrain.splat2_img, c, r, layer, 0.9, Terrain.splat2_img)

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout
	var ws: float = Terrain.params.world_size
	# 蜿蜒土路：S 形曲线（验证可以画弯路）
	var s_curve: Array = []
	for i in range(21):
		var t: float = i / 20.0
		s_curve.append(Vector2(60 + t * 90, 90 + sin(t * 6.28) * 14))
	_stroke_line(s_curve, 3.0, SplatBrush.Layer.ROAD)
	# 石板路：另一条直线
	_stroke_line([Vector2(60, 55), Vector2(150, 68)], 3.5, SplatBrush.Layer.PAVED)
	Terrain.refresh_splat2_texture()
	# 森林
	for cc in [Vector2(95, 130), Vector2(112, 138), Vector2(82, 142)]:
		var c3: Vector2 = TerrainBrush.world_to_pixel(Vector3(cc.x, 0, cc.y), ws, Terrain.SPLAT_SIZE)
		var r3: float = TerrainBrush.world_radius_to_pixel(13.0, ws, Terrain.SPLAT_SIZE)
		SplatBrush.apply(Terrain.splat_img, c3, r3, SplatBrush.Layer.FOREST, 1.0)
	Terrain.refresh_splat_texture()
	# 陡山（看 CC0 岩壁）
	var sz: int = Terrain.heightmap_img.get_width()
	var hc: Vector2 = TerrainBrush.world_to_pixel(Vector3(190, 0, 100), ws, sz)
	var hr: float = TerrainBrush.world_radius_to_pixel(18.0, ws, sz)
	TerrainBrush.apply(Terrain.heightmap_img, hc, hr, 0.95, TerrainBrush.Mode.RAISE, 0.0)
	# 浅坑验证新水位：压 4.5m → -2.6m < -2m 出水
	var wc: Vector2 = TerrainBrush.world_to_pixel(Vector3(120, 0, 105), ws, sz)
	var wr: float = TerrainBrush.world_radius_to_pixel(8.0, ws, sz)
	TerrainBrush.apply(Terrain.heightmap_img, wc, wr, 0.28, TerrainBrush.Mode.LOWER, 0.0)
	Terrain.heightmap_tex.update(Terrain.heightmap_img)
	Terrain._refresh_biome_from_height()
	print("[SHOT] 坑底 %.2fm / 水面 %.1fm → %s" % [
		Terrain.get_height(120, 105), Terrain.params.water_level,
		"出水" if Terrain.get_height(120, 105) < Terrain.params.water_level else "没水"])
	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null:
		if cam.has_method("focus_on"):
			cam.focus_on(Vector3(115, 0, 85))
		if "_distance" in cam:
			cam.set("_distance", 85.0)
		await get_tree().create_timer(2.2).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_v2.png")
		if cam.has_method("focus_on"):
			cam.focus_on(Vector3(100, 0, 134))
		cam.set("_distance", 30.0)
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_v2_forest.png")
	get_tree().quit(0)
