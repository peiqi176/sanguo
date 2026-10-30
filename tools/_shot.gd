extends Node
## 截图调试工具（长期保留，别再删）
##
## 为什么要自建相机：CameraController 每帧覆盖 transform，手动赋值会被它 lerp 回去。
## 用法：
##   godot --path . res://tools/_shot.tscn                          默认：45° 标准视角拍玩家基地
##   godot --path . res://tools/_shot.tscn -- --pitch=35 --yaw=45 --dist=60 --out=far
## 输出：docs/shot_<out>.png
var _t: int = 0
var _main = null
var _cam: Camera3D = null
var _pitch: float = 45.0
var _yaw: float = 45.0
var _dist: float = 34.0
var _out: String = "default"
var _focus: String = "base"      # base / overview / unit / game（用游戏自己的相机）
var _aim: Vector3 = Vector3.ZERO
var _aim_x: float = -1.0
var _aim_z: float = -1.0
var _dist_set: bool = false   # 命令行显式给了 --dist 就不要被 focus 的默认值抬走
var _own_cam: bool = true

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = str(a)
		if s.begins_with("--pitch="): _pitch = float(s.substr(8))
		elif s.begins_with("--yaw="): _yaw = float(s.substr(6))
		elif s.begins_with("--dist="): _dist = float(s.substr(7)); _dist_set = true
		elif s.begins_with("--out="): _out = s.substr(6)
		elif s.begins_with("--focus="): _focus = s.substr(8)
		elif s.begins_with("--aimx="): _aim_x = float(s.substr(7))
		elif s.begins_with("--aimz="): _aim_z = float(s.substr(7))
		elif s.begins_with("--owncam="): _own_cam = (s.substr(9) != "0")

	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	# ⚠ 关掉边缘滚屏：headless 下鼠标永远在 (0,0)，会一直往左上滚，
	# 等 70 帧再截图时相机已经飘出基地十几米了（这个坑排查了很久）。
	var cc = _main.get_node_or_null("CameraController")
	if cc != null:
		cc.edge_scroll = false

	if _own_cam:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		_cam.near = 0.2
		_cam.far = 900.0
		add_child(_cam)

func _place_aim() -> void:
	match _focus:
		"overview":
			_aim = Vector3(Terrain.params.world_size * 0.5, 0, Terrain.params.world_size * 0.5)
			if not _dist_set:
				_dist = 150.0
		"unit":
			for n in _main.get_children():
				if n.get("unit_id") != null and str(n.get("faction")) == "shu":
					_aim = (n as Node3D).global_position
					break
		"horse":
			# 对准第一匹野马：验证"贴地跑"最直接的办法就是把它拍下来
			for h in GameManager.wild_horses:
				if is_instance_valid(h):
					_aim = (h as Node3D).global_position
					break
			_dist = minf(_dist, 14.0)
		_:
			for n in _main.get_children():
				if n.get("building_id") == "government" and str(n.get("faction")) == "shu":
					_aim = (n as Node3D).global_position
					break
	if _focus == "base":
		_aim += Vector3(4, 0, 4)
	if _aim_x >= 0.0 and _aim_z >= 0.0:
		_aim = Vector3(_aim_x, 0.0, _aim_z)
		_aim.y = Terrain.get_height(_aim_x, _aim_z)

func _aim_camera() -> void:
	_place_aim()
	var p: float = deg_to_rad(_pitch)
	var y: float = deg_to_rad(_yaw)
	var off: Vector3 = Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * _dist
	_cam.global_position = _aim + off
	_cam.look_at(_aim, Vector3.UP)
	_cam.make_current()

func _process(_d: float) -> void:
	_t += 1
	if _t == 55:
		if _own_cam:
			_aim_camera()
	if _t >= 56 and _t <= 72:
		if _own_cam:
			_aim_camera()      # 每帧压住，防止别的脚本改相机
	if _t == 76:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("res://docs/shot_%s.png" % _out)
		print("[SHOT] %s  %dx%d  pitch=%.0f yaw=%.0f dist=%.0f owncam=%s" % [
			_out, img.get_width(), img.get_height(), _pitch, _yaw, _dist, str(_own_cam)])
		get_tree().quit()
