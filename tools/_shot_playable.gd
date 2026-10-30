extends Node
## 生成一张地图 → 存盘 → 以 custom 模式起 Main → 拍照
##
## 用法：
##   godot --path . res://tools/_shot_playable.tscn -- --tpl=two_kingdoms --name=_demo --out=play
## 输出：docs/shot_play_<out>.png（全景）+ docs/shot_play_<out>_base.png（起点近景）

const MapTemplates = preload("res://scripts/mapgen/MapTemplates.gd")
const MapGenService = preload("res://scripts/mapgen/MapGenService.gd")
const MapIO = preload("res://scripts/mapformat/MapIO.gd")

var _tpl_id: String = "two_kingdoms"
var _name: String = "_shot_play"
var _out: String = "play"
var _grid_n: int = 84
var _main = null
var _cam: Camera3D = null
var _shot_i: int = 0
var _shots: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = str(a)
		if s.begins_with("--tpl="): _tpl_id = s.substr(6)
		elif s.begins_with("--name="): _name = s.substr(7)
		elif s.begins_with("--out="): _out = s.substr(6)
		elif s.begins_with("--grid="): _grid_n = int(s.substr(7))

	var tpl: Dictionary = MapTemplates.template_def(_tpl_id)
	if tpl.is_empty():
		tpl = MapTemplates.default_template()
	tpl["grid_n"] = _grid_n
	if int(tpl.get("players", 2)) > 3:
		tpl["players"] = 3
	var gen: Dictionary = MapGenService.generate_and_save(tpl, {"map_name": _name})
	print("[PLAYSHOT] 生成 %s：ok=%s error=%s" % [_tpl_id, str(gen["ok"]), str(gen["error"])])
	if not str(gen["text"]).is_empty():
		print(gen["text"])
	if not bool(gen["ok"]):
		get_tree().quit(1)
		return

	GameManager.game_settings_override = {"map_mode": "custom", "map_saved_name": _name}
	GameManager.apply_settings()
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	var cc = _main.get_node_or_null("CameraController")
	if cc != null:
		cc.edge_scroll = false
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.3
	_cam.far = 2400.0
	add_child(_cam)
	var ws: float = float(_grid_n) * 2.0
	_shots = [
		{"name": _out, "target": Vector3(ws * 0.5, 0, ws * 0.5), "dist": ws * 0.80, "pitch": 62.0},
		{"name": _out + "_base", "target": "start", "dist": 42.0, "pitch": 45.0},
	]

func _process(_d: float) -> void:
	_t += 1
	if _t < 40:
		return
	# 每张图：8 帧定位 + 拍
	var slot: int = (_t - 40) / 8
	if slot >= _shots.size():
		_cleanup()
		return
	var sh: Dictionary = _shots[slot]
	if (_t - 40) % 8 == 1:
		_aim(sh)
	elif (_t - 40) % 8 == 5:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("res://docs/shot_play_%s.png" % str(sh["name"]))
		print("[SHOT] shot_play_%s.png" % str(sh["name"]))

var _t: int = 0

func _aim(sh: Dictionary) -> void:
	var tgt = sh["target"]
	if tgt is String:
		tgt = _first_start()
	var center: Vector3 = tgt
	center.y = Terrain.get_height(center.x, center.z)
	var p: float = deg_to_rad(float(sh["pitch"]))
	var y: float = deg_to_rad(45.0)
	var off: Vector3 = Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * float(sh["dist"])
	_cam.global_position = center + off
	_cam.look_at(center, Vector3.UP)
	_cam.make_current()

func _first_start() -> Vector3:
	# 用玩家第一个建筑当"起点"（官府）
	for c in _main.get_children():
		if c.get("building_id") == "government":
			return (c as Node3D).global_position
	return Vector3(float(_grid_n), 0, float(_grid_n))

func _cleanup() -> void:
	set_process(false)
	MapIO.delete_map(_name)
	print("[PLAYSHOT] 完成，测试地图已清理")
	get_tree().quit()
