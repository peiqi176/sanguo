extends Node
## 土路/石板/沙地 换贴图验收探针：编辑器里刷三层 → 三机位实拍

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

	# S 形土路（路芯+路肩三段式）
	var steps: int = 90
	for i in range(steps + 1):
		var f: float = float(i) / float(steps)
		var x: float = 60.0 + f * 180.0
		var z: float = 150.0 + sin(f * 6.283) * 35.0
		var px: Vector2 = TerrainBrush.world_to_pixel(Vector3(x, 0, z), ws, ssz)
		var pr: float = TerrainBrush.world_radius_to_pixel(4.5, ws, ssz)
		SplatBrush.paint_road(Terrain.splat_img, Terrain.splat2_img, px, pr,
				SplatBrush.Layer.ROAD, 0.55)

	# 沙地一片
	for i in range(4):
		var p1: Vector2 = TerrainBrush.world_to_pixel(Vector3(150.0, 0, 195.0), ws, ssz)
		SplatBrush.apply(Terrain.splat_img, p1 + Vector2(float(i) * 3.0, float(i) * 2.0),
				TerrainBrush.world_radius_to_pixel(14.0, ws, ssz), SplatBrush.Layer.SAND, 1.0)

	# 石板路一条（斜穿）
	for i in range(26):
		var f2: float = float(i) / 25.0
		var x2: float = 120.0 + f2 * 70.0
		var z2: float = 118.0 - f2 * 24.0
		var p2: Vector2 = TerrainBrush.world_to_pixel(Vector3(x2, 0, z2), ws, ssz)
		SplatBrush.apply(Terrain.splat_img, p2,
				TerrainBrush.world_radius_to_pixel(4.5, ws, ssz), SplatBrush.Layer.PAVED, 1.0,
				Terrain.splat2_img)

	Terrain.refresh_splat_texture()
	Terrain.refresh_splat2_texture()

	# 诊断开关（命令行 user args 带 --debug-gsel 时把 gsel 拍成灰度图）
	if "--debug-gsel" in OS.get_cmdline_user_args():
		var stack: Array = [_ed]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				var m: Material = n.material_override
				if m is ShaderMaterial and m.get_shader_parameter("tex_grass") != null:
					m.set_shader_parameter("debug_gsel", 1.0)
					print("[SHOT] debug_gsel on ", n.name)
					break
			stack.append_array(n.get_children())

	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam == null or not cam.has_method("focus_on"):
		print("[SHOT] no camera")
		get_tree().quit(1)
		return
	for shot in [[Vector3(120, 0, 185), 26.0, "road"], [Vector3(150, 0, 197), 16.0, "sand"], [Vector3(152, 0, 110), 16.0, "paved"]]:
		cam.focus_on(shot[0])
		if "_distance" in cam:
			cam.set("_distance", shot[1])
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_layer_%s.png" % shot[2])
		print("[SHOT] %s saved" % shot[2])
	get_tree().quit(0)
