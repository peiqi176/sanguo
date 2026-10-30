extends Node3D
## 生成一张地图并拍下来 —— 唯一能验证"对称化有没有真的落到屏幕上"的手段
##
## 用法：
##   godot --path . res://tools/_shot_generated.tscn -- --tpl=two_kingdoms --out=gen
## 输出：docs/shot_gen_<out>.png

const MapTemplates = preload("res://scripts/mapgen/MapTemplates.gd")
const MapGenService = preload("res://scripts/mapgen/MapGenService.gd")

var _t: int = 0
var _tpl_id: String = "two_kingdoms"
var _out: String = "gen"
var _dist: float = 150.0
var _pitch: float = 62.0
var _main = null
var _cam: Camera3D = null
var _done: bool = false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = str(a)
		if s.begins_with("--tpl="): _tpl_id = s.substr(6)
		elif s.begins_with("--out="): _out = s.substr(6)
		elif s.begins_with("--dist="): _dist = float(s.substr(7))
		elif s.begins_with("--pitch="): _pitch = float(s.substr(8))

	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	var cc = _main.get_node_or_null("CameraController")
	if cc != null:
		cc.edge_scroll = false
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.3
	_cam.far = 2000.0
	add_child(_cam)

func _process(_d: float) -> void:
	_t += 1
	# 30 帧后 Main 初始化完成，开始生成
	if _t == 30 and not _done:
		_generate()
		return
	if _t < 45:
		return
	if _t == 45:
		_aim()
	elif _t <= 60:
		_aim()          # 每帧压住，防别的脚本改相机
	elif _t == 64:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("res://docs/shot_gen_%s.png" % _out)
		print("[SHOT] shot_gen_%s.png  %dx%d  tpl=%s dist=%.0f" % [
			_out, img.get_width(), img.get_height(), _tpl_id, _dist])
		get_tree().quit()

func _generate() -> void:
	_done = true
	var tpl: Dictionary = MapTemplates.template_def(_tpl_id)
	if tpl.is_empty():
		print("[GENSHOT] 未知模板 %s，用默认" % _tpl_id)
		tpl = MapTemplates.default_template()
	# 截图用中等尺寸，快且够看
	tpl["grid_n"] = 84
	if int(tpl.get("players", 2)) > 3:
		tpl["players"] = 3
	var r: Dictionary = MapGenService.generate(tpl, {"map_name": "_shot_gen"})
	print("[GENSHOT] 生成 %s：ok=%s  error=%s" % [_tpl_id, str(r["ok"]), str(r["error"])])
	if not str(r["text"]).is_empty():
		print(r["text"])
	var doc = r["doc"]
	if doc != null:
		print("[GENSHOT] 对象 %d 个：建筑 %d / 资源 %d / 单位 %d / 装饰 %d" % [
			doc.objects.size(), doc.count_by_kind("building"), doc.count_by_kind("resource"),
			doc.count_by_kind("unit"), doc.count_by_kind("deco")])
	if r["grid"] != null and is_instance_valid(r["grid"]):
		r["grid"].free()

func _aim() -> void:
	var ws: float = 84.0 * 2.0
	if Terrain.params != null:
		ws = float(Terrain.params.get("world_size"))
	var center := Vector3(ws * 0.5, 0.0, ws * 0.5)
	center.y = Terrain.get_height(center.x, center.z)
	var p: float = deg_to_rad(_pitch)
	var y: float = deg_to_rad(45.0)
	var off: Vector3 = Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * _dist
	_cam.global_position = center + off
	_cam.look_at(center, Vector3.UP)
	_cam.make_current()
