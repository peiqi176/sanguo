extends Node
## Ribbon UI 实拍：进编辑器 → 画一块枯黄草 + 一段大板138石板路 → 逐页签截图
## 验证：①Ribbon 页签布局 ②变种笔刷真的改 splat2.B/A 并在 3D 里生效

const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")
const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(4.5).timeout

	# ---- 画一笔"枯黄草"（中心偏左）与一段"大板138 石板路"（中心偏右）----
	await get_tree().process_frame
	var ws: float = float(Terrain.params.world_size)
	var sp_sz: int = Terrain.splat_img.get_width()
	# 枯黄草：世界坐标偏左 25m
	var grass_c := Vector3(ws * 0.5 - 25.0, 0.0, ws * 0.5)
	var gp := TerrainBrush.world_to_pixel(grass_c, ws, sp_sz)
	var gr := TerrainBrush.world_radius_to_pixel(14.0, ws, sp_sz)
	SplatBrush.stroke_seed = 1234
	for i in range(4):
		SplatBrush.paint_grass_variant(Terrain.splat_img, Terrain.splat2_img, gp, gr, 4, 0.6)
	# 大板138：世界坐标偏右 25m
	var road_c := Vector3(ws * 0.5 + 25.0, 0.0, ws * 0.5)
	var rp := TerrainBrush.world_to_pixel(road_c, ws, sp_sz)
	var rr := TerrainBrush.world_radius_to_pixel(9.0, ws, sp_sz)
	for i in range(4):
		SplatBrush.paint_road(Terrain.splat_img, Terrain.splat2_img, rp, rr,
				SplatBrush.Layer.PAVED, 0.6, 1)
	Terrain.ensure_splat2()
	Terrain.refresh_splat_texture()
	Terrain.refresh_splat2_texture()
	var rc: Color = Terrain.splat2_img.get_pixel(int(rp.x), int(rp.y))
	print("PAINTED road_r=%.3f road_a=%.4f | grass_b=%.4f" % [rc.r, rc.a,
		Terrain.splat2_img.get_pixel(int(gp.x), int(gp.y)).b])

	await get_tree().create_timer(0.6).timeout
	# 特写：镜头正对路心（大板138），验证变种渲染
	if _ed.cam_ctrl != null and _ed.cam_ctrl.has_method("focus_on"):
		_ed.cam_ctrl.set("_distance", 18.0)
		_ed.cam_ctrl.focus_on(Vector3(ws * 0.5 + 25.0, 0.0, ws * 0.5))
		await get_tree().create_timer(0.8).timeout
	_shot("closeup")
	_shot("terrain")
	_ed._ui._show_tab("ground")
	await get_tree().create_timer(0.4).timeout
	_shot("ground")
	_ed._ui._show_tab("road")
	await get_tree().create_timer(0.4).timeout
	_shot("road")
	_ed._ui._show_tab("object")
	await get_tree().create_timer(0.4).timeout
	_shot("object")
	_ed._ui._show_tab("file")
	await get_tree().create_timer(0.4).timeout
	_shot("file")
	print("SHOT ui done")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

func _shot(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://_shot_ui_%s.png" % tag)
	print("SHOT _shot_ui_%s.png %dx%d" % [tag, img.get_width(), img.get_height()])
