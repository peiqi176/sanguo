extends Node
## 拼图层（splat）实机截图：程序化刷几块有语义的地表，然后按命令行视角拍照。
##
## 用法：
##   godot --path . res://tools/_shot_splat.tscn -- --out=splat_road
## 场景里做的事：
##   1. 等 Main 就绪（地形/材质/资源点都进树）
##   2. 程序化刷四块拼图：一条穿图的土路、河湾沙洲、坡脚裸岩、林下地表
##   3. 55~72 帧用自建相机对准 --aimx/--aimz 拍照 → docs/shot_<out>.png
##
## 这份"刷法"同时就是笔刷算子的实机回归：
##   如果 SplatBrush / shader 通道语义对不上，图上会立刻看出颜色错层。

const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")
const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")

var _t: int = 0
var _main = null
var _cam: Camera3D = null
var _pitch: float = 45.0
var _yaw: float = 45.0
var _dist: float = 60.0
var _out: String = "splat"
var _aim_x: float = -1.0
var _aim_z: float = -1.0
var _painted: bool = false
var _fill: bool = false
var _focus: String = ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = str(a)
		if s.begins_with("--pitch="): _pitch = float(s.substr(8))
		elif s.begins_with("--yaw="): _yaw = float(s.substr(6))
		elif s.begins_with("--dist="): _dist = float(s.substr(7))
		elif s.begins_with("--out="): _out = s.substr(6)
		elif s.begins_with("--aimx="): _aim_x = float(s.substr(7))
		elif s.begins_with("--aimz="): _aim_z = float(s.substr(7))
		elif s.begins_with("--focus="): _focus = s.substr(8)
		elif s == "--fill": _fill = true

	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	var cc = _main.get_node_or_null("CameraController")
	if cc != null:
		cc.edge_scroll = false

	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.2
	_cam.far = 900.0
	add_child(_cam)

## 世界坐标 → 拼图像素（与笔刷/材质同一套映射）
func _px(ws: float, ssz: int, x: float, z: float) -> Vector2:
	return TerrainBrush.world_to_pixel(Vector3(x, 0, z), ws, ssz)

func _paint_splat() -> void:
	var ws: float = Terrain.params.world_size
	Terrain.ensure_splat()
	var img: Image = Terrain.splat_img
	var ssz: int = img.get_width()

	if _fill:
		# 对照实验：整张拼图填成"泥土"，若画面不变黄则问题在 shader/绑定侧
		img.fill(Color(0.0, 0.9, 0.0, 0.0))
		Terrain.refresh_splat_texture()
		print("[SHOT-SPLAT] FILL 对照：整图 G=0.9")
		return

	# 1) 一条横穿地图的土路（从西侧到东侧，带轻微弯曲）——最能暴露"笔刷有没有刷出硬边圆饼"
	var z_road: float = ws * 0.5
	for i in range(220):
		var t: float = float(i) / 219.0
		var x: float = ws * (0.06 + 0.88 * t)
		var z: float = z_road + sin(t * 7.0) * ws * 0.045
		var c: Vector2 = _px(ws, ssz, x, z)
		SplatBrush.apply(img, c, ssz * 0.014, SplatBrush.Layer.DIRT, 0.85)
		SplatBrush.apply(img, c, ssz * 0.02, SplatBrush.Layer.DIRT, 0.25)

	# 2) 河湾沙洲：找一块水边（高度接近水面的点），刷一大片沙地
	var water: float = Terrain.params.water_level
	var placed_sand: bool = false
	for i in range(4000):
		var x: float = randf_range(ws * 0.1, ws * 0.9)
		var z: float = randf_range(ws * 0.1, ws * 0.9)
		var h: float = Terrain.get_height(x, z)
		if h > water + 0.35 and h < water + 1.1:
			var c2: Vector2 = _px(ws, ssz, x, z)
			SplatBrush.apply(img, c2, ssz * 0.05, SplatBrush.Layer.SAND, 0.9)
			placed_sand = true
			break

	# 3) 坡脚裸岩：找一块坡度大的点刷岩石层
	var placed_rock: bool = false
	for i in range(4000):
		var x2: float = randf_range(ws * 0.15, ws * 0.85)
		var z2: float = randf_range(ws * 0.15, ws * 0.85)
		var h0: float = Terrain.get_height(x2, z2)
		var hx: float = Terrain.get_height(x2 + 3.0, z2)
		var hz: float = Terrain.get_height(x2, z2 + 3.0)
		var slope: float = sqrt(pow(hx - h0, 2.0) + pow(hz - h0, 2.0)) / 3.0
		if slope > 0.55:
			var c3: Vector2 = _px(ws, ssz, x2, z2)
			SplatBrush.apply(img, c3, ssz * 0.035, SplatBrush.Layer.ROCK, 0.95)
			placed_rock = true
			break

	# 4) 林下地表：找森林区（moisture 高的地方不好直接查，就选地图东北角一块）刷深色地被
	var c4: Vector2 = _px(ws, ssz, ws * 0.78, ws * 0.24)
	SplatBrush.apply(img, c4, ssz * 0.04, SplatBrush.Layer.FOREST, 0.85)

	# 5) 正中心一块 15m 半径的沙盘（对照实验：如果它都不显示，说明 shader/绑定有问题）
	var c5: Vector2 = _px(ws, ssz, ws * 0.5, ws * 0.5)
	SplatBrush.apply(img, c5, ssz * 0.075, SplatBrush.Layer.SAND, 1.0)

	Terrain.refresh_splat_texture()
	# 把 CPU 侧拼图导出成可见 PNG（排查"画了但没上传"时用，正常跑可忽略）
	var dbg: Image = img.duplicate()
	var vis: Image = Image.create(dbg.get_width(), dbg.get_height(), false, Image.FORMAT_RGBA8)
	for yy in range(dbg.get_height()):
		for xx in range(dbg.get_width()):
			var cc: Color = dbg.get_pixel(xx, yy)
			vis.set_pixel(xx, yy, Color(cc.r, cc.g, cc.b, 1.0))
	vis.save_png("res://docs/splat_debug_cpu.png")
	var cc2: Color = img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	print("[SHOT-SPLAT] 中心像素 R=%.2f G=%.2f B=%.2f A=%.2f" % [cc2.r, cc2.g, cc2.b, cc2.a])
	print("[SHOT-SPLAT] 拼图 %d²，沙洲=%s 裸岩=%s，painted=%.1f%%" % [
		ssz, str(placed_sand), str(placed_rock),
		SplatBrush.painted_ratio(img) * 100.0])
	# ---- 绑定探针：材质里的 splat uniform 必须还是同一个纹理对象 ----
	var probe_node: MeshInstance3D = null
	for n in _main.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).mesh is PlaneMesh \
				and (n as MeshInstance3D).material_override is ShaderMaterial:
			probe_node = n
			break
	if probe_node != null:
		var m: Material = probe_node.material_override
		if m is ShaderMaterial:
			var bound: Texture2D = (m as ShaderMaterial).get_shader_parameter("splat")
			var same: bool = (bound == Terrain.splat_tex)
			var road_px: Vector2 = _px(ws, ssz, ws * 0.5, ws * 0.5 + sin(0.5 * 7.0) * ws * 0.045)
			var rd: Color = img.get_pixel(int(road_px.x), int(road_px.y))
			print("[SHOT-SPLAT] 材质绑定同一纹理=%s  道路像素 G=%.2f（应≈0.85）tex=%s" % [
				str(same), rd.g, str(Terrain.splat_tex)])
		else:
			print("[SHOT-SPLAT] ⚠ 地形材质不是 ShaderMaterial: ", m)
	else:
		print("[SHOT-SPLAT] ⚠ 没找到 TerrainMesh（探针跳过，不影响截图）")

func _aim() -> Vector3:
	var ws: float = Terrain.params.world_size
	var aim := Vector3(ws * 0.5, 0, ws * 0.5)
	if _focus == "resource":
		# 挑离地图中心最近的一个，避免随机刷在陡坡后面把镜头埋进山体
		var ws2: float = Terrain.params.world_size
		var best: Node3D = null
		var best_d: float = 1e9
		for rn in GameManager.resource_nodes:
			if not is_instance_valid(rn):
				continue
			var p: Vector3 = (rn as Node3D).global_position
			var d: float = Vector2(p.x - ws2 * 0.5, p.z - ws2 * 0.5).length()
			if d < best_d:
				best_d = d
				best = rn
		if best != null:
			aim = best.global_position
			_dist = minf(_dist, 14.0)
	elif _focus == "village":
		for v in GameManager.villages:
			if is_instance_valid(v):
				aim = (v as Node3D).global_position
				_dist = minf(_dist, 30.0)
				break
	if _aim_x >= 0.0 and _aim_z >= 0.0:
		aim = Vector3(_aim_x, 0.0, _aim_z)
	aim.y = Terrain.get_height(aim.x, aim.z)
	return aim

func _process(_d: float) -> void:
	_t += 1
	if _t == 40 and not _painted:
		_painted = true
		_paint_splat()
	if _t >= 60 and _t <= 74:
		var aim: Vector3 = _aim()
		var p: float = deg_to_rad(_pitch)
		var y: float = deg_to_rad(_yaw)
		var off: Vector3 = Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * _dist
		_cam.global_position = aim + off
		_cam.look_at(aim, Vector3.UP)
		_cam.make_current()
	if _t == 78:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("res://docs/shot_%s.png" % _out)
		print("[SHOT] %s  %dx%d  pitch=%.0f yaw=%.0f dist=%.0f" % [
			_out, img.get_width(), img.get_height(), _pitch, _yaw, _dist])
		get_tree().quit()
