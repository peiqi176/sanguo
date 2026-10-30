extends Node
## 自动修路验收探针：进游戏主场景 → 扫 splat2 找到程序生成的土路/石板路
## → 自建相机飞到路上空俯拍（游戏机位看不到全貌）。

const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _main = null

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.5).timeout
	# 关战争迷雾（同 _shot_terrain）
	var stack: Array = [_main]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			var mi := nd as MeshInstance3D
			var mats: Array = []
			if mi.material_override != null:
				mats.append(mi.material_override)
			for i in range(mi.get_surface_override_material_count()):
				var m2: Material = mi.get_surface_override_material(i)
				if m2 != null:
					mats.append(m2)
			for m in mats:
				if m is ShaderMaterial:
					(m as ShaderMaterial).set_shader_parameter("fog_enabled", 0.0)
		for c in nd.get_children():
			stack.append(c)

	var ws: float = Terrain.params.world_size
	var ssz: int = Terrain.SPLAT_SIZE
	var s2: Image = Terrain.splat2_img
	if s2 == null:
		print("[SHOT] no splat2")
		get_tree().quit(1)
		return
	# 扫描两条路：g=土路，r=石板。取包围盒中心 + 一个抽样点
	var dirt_pts: Array[Vector2] = []
	var pave_pts: Array[Vector2] = []
	var step: int = maxi(ssz / 256, 1)
	for py in range(0, ssz, step):
		for px in range(0, ssz, step):
			var c: Color = s2.get_pixel(px, py)
			if c.g > 0.25:
				dirt_pts.append(Vector2(px, py))
			elif c.r > 0.25:
				pave_pts.append(Vector2(px, py))
	print("[SHOT] dirt px=%d paved px=%d (ws=%.0f)" % [dirt_pts.size(), pave_pts.size(), ws])
	if dirt_pts.is_empty() and pave_pts.is_empty():
		print("[SHOT] 生成的地图上没有路！")
		get_tree().quit(1)
		return

	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()

	# 俯瞰全图一张
	var h0: float = Terrain.get_height(ws * 0.5, ws * 0.5)
	cam.global_position = Vector3(ws * 0.5, h0 + ws * 0.72, ws * 0.5 + ws * 0.10)
	cam.look_at(Vector3(ws * 0.5, h0, ws * 0.5))
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_roads_map.png")
	print("[SHOT] map saved")

	for spec in [["dirt", dirt_pts], ["paved", pave_pts]]:
		var pts: Array[Vector2] = spec[1]
		if pts.is_empty():
			print("[SHOT] %s: 无" % spec[0])
			continue
		var c0: Vector2 = pts[pts.size() / 2]
		var wx: float = c0.x / float(ssz - 1) * ws
		var wz: float = (0.5 - c0.y / float(ssz - 1)) * ws + ws * 0.5
		var hh: float = Terrain.get_height(wx, wz)
		cam.global_position = Vector3(wx, hh + 34.0, wz + 12.0)
		cam.look_at(Vector3(wx, hh, wz))
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_roads_%s.png" % spec[0])
		print("[SHOT] %s saved at (%.0f, %.0f)" % [spec[0], wx, wz])
	get_tree().quit(0)
