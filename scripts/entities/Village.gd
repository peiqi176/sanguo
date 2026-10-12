extends StaticBody3D
class_name Village
## Village — 中立村庄，可占领后提供税收/粮草/人口加成
## 单位靠近村庄一定时间后占领，被敌方夺取则易主

@export var village_id: String = "village_0"
var village_owner: String = ""
var occupy_progress: float = 0.0
var occupier: String = ""
var income_tick: float = 0.0
var village_name: String = "村庄"
var tax_gold: float = 0.5
var tax_food: float = 0.3
var pop_bonus: int = 5
var _flag: MeshInstance3D = null

func _ready() -> void:
	GameManager.villages.append(self)
	_create_visual()

func _create_visual() -> void:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var adef: Dictionary = DataLoader.get_asset_def("village", "village")
	if not adef.is_empty():
		var tex: Texture2D = DataLoader.get_sprite_texture("village", "village")
		if tex:
			sprite.texture = tex
		var s: float = float(adef.get("scale", 1.8))
		sprite.scale = Vector3(s, s, s)
		sprite.position.y = float(adef.get("offset_y", 0.9))
	add_child(sprite)
	_flag = MeshInstance3D.new()
	var fbox: BoxMesh = BoxMesh.new()
	fbox.size = Vector3(0.6, 1.2, 0.1)
	_flag.mesh = fbox
	_flag.position = Vector3(1.2, 1.8, 0)
	add_child(_flag)
	_update_flag()

func _update_flag() -> void:
	if _flag == null:
		return
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	if village_owner == "":
		fmat.albedo_color = Color(0.8, 0.8, 0.8)
	else:
		fmat.albedo_color = GameManager.factions[village_owner].color
	_flag.material_override = fmat

func _process(delta: float) -> void:
	if GameManager.paused or GameManager.game_over:
		return
	_check_occupiers(delta)
	if village_owner != "" and village_owner in GameManager.factions:
		income_tick += delta
		if income_tick >= 1.0:
			income_tick = 0.0
			_apply_income()

func _check_occupiers(delta: float) -> void:
	var near_units: Array = []
	for u in GameManager.all_units:
		if is_instance_valid(u) and u.has_method("get_faction"):
			if global_position.distance_to(u.global_position) < 3.5:
				near_units.append(u)
	if near_units.is_empty():
		if occupy_progress > 0 and occupier != village_owner:
			occupy_progress = max(0.0, occupy_progress - 5.0 * delta)
		occupier = ""
		return
	var faction_counts: Dictionary = {}
	for u in near_units:
		var f: String = u.get_faction()
		faction_counts[f] = faction_counts.get(f, 0) + 1
	var best_faction: String = ""
	var best_count: int = 0
	for f in faction_counts.keys():
		if faction_counts[f] > best_count:
			best_count = faction_counts[f]
			best_faction = f
	if faction_counts.size() == 1:
		occupier = best_faction
		if occupier == village_owner:
			occupy_progress = 100.0
		else:
			occupy_progress = min(100.0, occupy_progress + 15.0 * delta)
			if occupy_progress >= 100.0:
				_capture(occupier)
	else:
		occupier = ""

func _capture(new_owner: String) -> void:
	var old: String = village_owner
	village_owner = new_owner
	occupy_progress = 100.0
	_update_flag()
	if old != "" and old in GameManager.factions:
		GameManager.factions[old].population_cap -= pop_bonus
	if new_owner in GameManager.factions:
		GameManager.factions[new_owner].population_cap += pop_bonus
	EventBus.float_text.emit("%s 占领村庄!" % new_owner.to_upper(), global_position + Vector3(0, 4, 0), Color.YELLOW)
	print("[Village] %s 占领村庄 %s (原属 %s)" % [new_owner, village_id, old])

func _apply_income() -> void:
	if village_owner not in GameManager.factions:
		return
	var state = GameManager.factions[village_owner]
	state.resources["gold"] += tax_gold
	state.resources["food"] += tax_food