extends Node
## 地图编辑器内岩石实拍：加载编辑器 → 用高地笔刷在中心塑一座「山」→ 拍三档
## 目的：确认 CC0 岩石贴图在编辑器里同样生效（编辑器与游戏共用 TerrainMaterial）

const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")
const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(4.0).timeout

	# 塑山：中心抬升但压在雪线（0.92≈14.7m）以下，够陡露岩又不积雪
	var img: Image = Terrain.heightmap_img
	var sz: int = img.get_width()
	var ws: float = float(Terrain.params.world_size)
	var c := Vector2(sz * 0.5, sz * 0.5)
	var r: float = TerrainBrush.world_radius_to_pixel(ws * 0.075, ws, sz)
	for i in range(7):
		TerrainBrush.apply(img, c, r, 0.10, TerrainBrush.Mode.RAISE, 0.0)
	TerrainBrush.apply(img, c, r * 1.7, 0.015, TerrainBrush.Mode.SMOOTH, 0.0)
	if Terrain.heightmap_tex != null:
		Terrain.heightmap_tex.update(img)

	# 编辑器岩石笔刷：在山坡上刷三笔岩石 splat（模拟玩家手刷）
	# ⚠ splat 图分辨率与高度图不同（2048 vs 512），坐标必须用 splat 自己的尺寸算
	var sp: Image = Terrain.splat_img
	var sp_sz: int = sp.get_width()
	var sp_c := Vector2(sp_sz * 0.5, sp_sz * 0.5)
	var sp_r: float = TerrainBrush.world_radius_to_pixel(ws * 0.05, ws, sp_sz)
	for i in range(3):
		SplatBrush.apply(sp, sp_c + Vector2(sp_r * 0.4, sp_r * 0.1), sp_r, SplatBrush.Layer.ROCK, 1.0)
		SplatBrush.apply(sp, sp_c + Vector2(-sp_r * 0.4, -sp_r * 0.1), sp_r * 0.9, SplatBrush.Layer.ROCK, 1.0)
	if Terrain.splat_tex != null:
		Terrain.splat_tex.update(sp)

	# 高度统计（确认真的凸起来了）
	var mn := 999.0
	var mx := -999.0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var v: float = img.get_pixel(x, y).r
			mn = minf(mn, v)
			mx = maxf(mx, v)
	print("[SHOT] 编辑器高度域 min=%.3f max=%.3f → %.1fm~%.1fm" % [
		mn, mx, mn * Terrain.params.max_height, mx * Terrain.params.max_height])

	# 自带相机：从山脚方向朝山顶拍（与游戏段同一套构图）
	var target := Vector3(ws * 0.5, Terrain.get_height(ws * 0.5, ws * 0.5), ws * 0.5)
	var cam3 := Camera3D.new()
	add_child(cam3)
	for d in [[20.0, "far"], [11.0, "close"], [5.5, "macro"]]:
		var dist: float = d[0]
		cam3.position = target + Vector3(-0.55, 0.0, -0.83) * dist + Vector3(0.0, dist * 0.22 + 1.2, 0.0)
		cam3.look_at(target + Vector3(0.0, 1.2, 0.0))
		cam3.current = true
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_edrock_%s.png" % d[1])
	get_tree().quit(0)
