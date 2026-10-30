extends Node3D
class_name RelicFragment
## RelicFragment — 古碑残片（gather 修复模式）
## 己方单位走到 2m 内自动拾取，通知所属古碑计数。

var relic_id: String = ""
var stele: Node = null
var faction: String = ""
var pickup_radius: float = 2.0
var _taken: bool = false
var _t: float = 0.0
var _visual: MeshInstance3D = null
var _label: Label3D = null

func _ready() -> void:
	_create_visual()
	GameManager.relics.append(self)

func _exit_tree() -> void:
	GameManager.relics.erase(self)

func get_faction() -> String:
	return faction

func is_taken() -> bool:
	return _taken

func get_hud_hint() -> String:
	return "🧩 古碑残片"

func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	if _visual:
		_visual.rotate_y(delta * 1.6)
		_visual.position.y = 0.9 + sin(_t * 2.0) * 0.15
	# 己方单位靠近即拾取（山贼/敌军不算）
	for u in GameManager.all_units:
		if not is_instance_valid(u) or not u.has_method("get_faction"):
			continue
		if u.get_faction() == "" or u.get_faction() == "bandit":
			continue
		if u.get("on_board") == true or u.get("is_escort") == true:
			continue
		if global_position.distance_to(u.global_position) <= pickup_radius:
			_collect(u.get_faction())
			return

func _collect(fid: String) -> void:
	if _taken:
		return
	_taken = true
	faction = fid
	EventBus.float_text.emit("🧩 拾得古碑残片", global_position + Vector3(0, 2, 0), Color.GOLD)
	if stele != null and is_instance_valid(stele) and stele.has_method("on_fragment_collected"):
		stele.on_fragment_collected(self)
	queue_free()

func _create_visual() -> void:
	_visual = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.45, 0.6, 0.2)
	_visual.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.78, 0.32)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.42, 0.10)
	mat.emission_energy_multiplier = 1.4
	_visual.material_override = mat
	_visual.position.y = 0.9
	add_child(_visual)
	_label = Label3D.new()
	_label.text = "🧩 残片"
	_label.font_size = 34
	_label.pixel_size = 0.005
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 1.9
	_label.modulate = Color(0.98, 0.88, 0.55)
	add_child(_label)
