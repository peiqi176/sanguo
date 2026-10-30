extends Node3D
class_name Showcase
## Showcase — 实体图鉴展示场景
## 把 config/asset_map.json 里所有建筑/单位/武将/资源/村庄/野马/辎重
## 一次性摆在大平面上，方便直观地查看「翻新后的 AoE 风格」全部实体。
## 实体用真实的 Building/Unit/General 等场景实例化（保留势力色底座与染色），
## 但冻结其每帧逻辑（AI/寻路/动画），只做静态展示。

const ASSET_MAP_PATH := "res://config/asset_map.json"

# 各分类展示配置：场景路径、导出属性名、标题、列间距、每行列数
const CATS := [
	{"cat": "buildings",      "scene": "res://scenes/Building.tscn",     "prop": "building_id",  "title": "建筑 Buildings",        "sx": 7.0, "sz": 7.0, "cols": 8,  "faction": true},
	{"cat": "units",          "scene": "res://scenes/Unit.tscn",         "prop": "unit_id",      "title": "士兵/单位 Units",      "sx": 4.0, "sz": 4.0, "cols": 10, "faction": true},
	{"cat": "generals",       "scene": "res://scenes/General.tscn",       "prop": "general_id",   "title": "武将 Generals",         "sx": 6.0, "sz": 6.0, "cols": 6,  "faction": true},
	{"cat": "resource_nodes", "scene": "res://scenes/ResourceNode.tscn",  "prop": "resource_type","title": "资源点 Resources",       "sx": 4.5, "sz": 4.5, "cols": 8,  "faction": false},
	{"cat": "village",        "scene": "res://scenes/Village.tscn",       "prop": "",             "title": "村庄 Village",          "sx": 6.0, "sz": 6.0, "cols": 4,  "faction": false},
	{"cat": "wild_horse",     "scene": "res://scenes/WildHorse.tscn",     "prop": "horse_type",   "title": "野马 Wild Horses",       "sx": 4.5, "sz": 4.5, "cols": 8,  "faction": false},
	{"cat": "supply_cart",    "scene": "res://scenes/SupplyCart.tscn",    "prop": "",             "title": "辎重车 Supply Cart",     "sx": 6.0, "sz": 6.0, "cols": 4,  "faction": true},
]

# 用于建筑/单位/武将的阵营色交替（呈现 AoE 风格的多阵营底色）
var _factions := ["shu", "wei", "wu"]
var _faction_idx := 0

var _min_bound := Vector3.ZERO
var _max_bound := Vector3.ZERO


func _ready() -> void:
	_setup_environment()
	_setup_lights()
	_setup_ground()
	_spawn_all()
	_frame_camera()
	print("[Showcase] 全部实体展示生成完成")


# ---------------- 场景环境 ----------------
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.71, 0.85)  # 天空蓝
	# 环境光（用 Environment 内置属性，不依赖 AmbientLight3D 节点）
	env.ambient_light_color = Color(0.85, 0.90, 0.80)
	env.ambient_light_energy = 1.1
	env.ambient_light_sky_contribution = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.position = Vector3(60, 120, 40)
	sun.rotation_degrees = Vector3(-60, 20, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	add_child(sun)


func _setup_ground() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.48, 0.26)  # 草地绿
	gm.roughness = 1.0
	gm.metallic = 0.0
	ground.material_override = gm
	ground.rotation.x = -PI / 2.0
	add_child(ground)


# ---------------- 生成全部实体 ----------------
func _spawn_all() -> void:
	var amap := _load_asset_map()
	if amap.is_empty():
		print("[Showcase] ❌ 无法读取 asset_map.json")
		return

	var z_cursor := 0.0
	for cfg in CATS:
		var cat: String = cfg["cat"]
		if not amap.has(cat):
			continue
		var ids: Array = amap[cat].keys()
		ids.sort()
		z_cursor = _spawn_category(cfg, ids, z_cursor)


func _spawn_category(cfg: Dictionary, ids: Array, z_start: float) -> float:
	var scene_path: String = cfg["scene"]
	var prop: String = cfg["prop"]
	var title: String = cfg["title"]
	var sx: float = cfg["sx"]
	var sz: float = cfg["sz"]
	var cols: int = int(cfg["cols"])

	var scene: PackedScene = load(scene_path)
	if scene == null:
		print("[Showcase] ❌ 场景加载失败: %s" % scene_path)
		return z_start

	# 分类标题
	_make_label(title, Vector3(-sx, 6.5, z_start), 36)

	var n := ids.size()
	var rows := ceili(float(n) / float(cols))
	var start_x := 0.0

	for i in range(n):
		var id: String = ids[i]
		var col := i % cols
		var row := i / cols
		var x := start_x + float(col) * sx
		var z := z_start + float(row) * sz

		var inst: Node = scene.instantiate()
		# 设置导出属性（实体在 _ready 中读取它来选贴图）
		if prop != "":
			inst.set(prop, id)
		# 给建筑/单位/武将/辎重车交替阵营色
		if cfg.get("faction", false):
			inst.set("faction", _factions[_faction_idx % _factions.size()])
			_faction_idx += 1

		inst.position = Vector3(x, 0.0, z)
		add_child(inst)
		# 冻结每帧逻辑：只留 _ready 生成的静态立绘，避免 AI/寻路/动画干扰
		inst.set_process(false)
		inst.set_physics_process(false)

		# 实体名牌
		_make_label(id, Vector3(x, 4.2, z), 18)
		_expand_bounds(x, z, 5.0)

	# 返回下一个分类的 z 起点（留出行间距）
	return z_start + float(rows) * sz + sz * 1.5


func _make_label(text: String, pos: Vector3, size: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.modulate = Color.WHITE
	l.outline_size = 2
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	add_child(l)


func _expand_bounds(x: float, z: float, r: float) -> void:
	_min_bound.x = min(_min_bound.x, x - r)
	_min_bound.z = min(_min_bound.z, z - r)
	_max_bound.x = max(_max_bound.x, x + r)
	_max_bound.z = max(_max_bound.z, z + r)
	_max_bound.y = max(_max_bound.y, 8.0)


func _frame_camera() -> void:
	var cc := $CameraController
	if cc == null:
		return
	var center := (_min_bound + _max_bound) * 0.5
	var ext := _max_bound - _min_bound
	var span: float = max(ext.x, ext.z)
	cc.set("_target", Vector3(center.x, 0.0, center.z))
	cc.set("_rotation_y", 0.0)
	cc.set("_distance", span * 0.55 + 70.0)
	if cc.has_method("_update_camera"):
		cc._update_camera()
	print("[Showcase] 相机已对准全景 (center=%s span=%.1f)" % [center, span])


# ---------------- 工具 ----------------
func _load_asset_map() -> Dictionary:
	if not FileAccess.file_exists(ASSET_MAP_PATH):
		return {}
	var f := FileAccess.open(ASSET_MAP_PATH, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var p := JSON.new()
	var err := p.parse(txt)
	if err != OK:
		return {}
	return p.get_data()
