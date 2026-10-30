extends Node
## 道路自动过渡带 + 有机笔刷 视觉终验探针（带窗口跑，几秒自退）。

const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")
const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(8.0).timeout

	Terrain.ensure_splat2()
	var ws: float = Terrain.params.world_size
	var ssz: int = Terrain.SPLAT_SIZE
	SplatBrush.stroke_seed = 7

	var steps: int = 90
	for i in range(steps + 1):
		var f: float = float(i) / float(steps)
		var x: float = 60.0 + f * 180.0
		var z: float = 150.0 + sin(f * 6.283) * 35.0
		var px: Vector2 = TerrainBrush.world_to_pixel(Vector3(x, 0, z), ws, ssz)
		var pr: float = TerrainBrush.world_radius_to_pixel(4.5, ws, ssz)
		SplatBrush.paint_road(Terrain.splat_img, Terrain.splat2_img, px, pr,
				SplatBrush.Layer.ROAD, 0.55)

	for i in range(14):
		var ang: float = float(i) * 0.45
		var x: float = 150.0 + cos(ang) * 6.0 + sin(i * 1.7) * 3.0
		var z: float = 80.0 + sin(ang) * 5.0
		var px2: Vector2 = TerrainBrush.world_to_pixel(Vector3(x, 0, z), ws, ssz)
		var pr2: float = TerrainBrush.world_radius_to_pixel(7.0, ws, ssz)
		SplatBrush.apply(Terrain.splat_img, px2, pr2, SplatBrush.Layer.DIRT, 0.22)

	Terrain.refresh_splat_texture()
	Terrain.refresh_splat2_texture()

	# ---- 白带区域高度采样 ----
	for hp in [Vector2(80, 130), Vector2(100, 135), Vector2(120, 140), Vector2(90, 120), Vector2(110, 155), Vector2(130, 150)]:
		print("[HEIGHT] world=%s h=%.2f" % [hp, Terrain.get_height(hp.x, hp.y)])
	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null and cam.has_method("focus_on"):
		cam.focus_on(Vector3(120, 0, 180))
		if "_distance" in cam:
			cam.set("_distance", 30.0)
		await get_tree().create_timer(3.0).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_road_close.png")
		print("[SHOT] road+brush saved")
	get_tree().quit(0)
