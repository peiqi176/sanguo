extends Node
## AIController — AI 对手
## 分层决策：战略(发展/军事) → 运营(建造/采集) → 战术(进攻/防守)

@export var faction: String = "wei"
@export var difficulty: float = 1.0  # 0.7~1.3

var _build_order: Array = ["house", "farm", "barracks_sword", "lumber", "house", "barracks_archer", "siege_workshop"]
var _build_index: int = 0
var _decision_timer: float = 0.0
var _attack_timer: float = 0.0
var _capture_timer: float = 0.0

func _ready() -> void:
	_decision_timer = 5.0
	_attack_timer = 30.0
	_capture_timer = 10.0

func _process(delta: float) -> void:
	if GameManager.game_over:
		return
	if GameManager.paused:
		return
	_decision_timer -= delta
	_attack_timer -= delta
	_capture_timer -= delta
	
	if _decision_timer <= 0:
		_decision_timer = 8.0 / difficulty
		_make_decision()
	if _attack_timer <= 0:
		_attack_timer = 45.0 / difficulty
		_launch_attack()
	if _capture_timer <= 0:
		_capture_timer = 15.0 / difficulty
		_capture_nearest_neutral()

func _make_decision() -> void:
	var faction_state = GameManager.factions[faction]
	var resources: Dictionary = faction_state.resources
	
	# 按建造顺序建造
	if _build_index < _build_order.size():
		var building_id: String = _build_order[_build_index]
		var bdef: Dictionary = DataLoader.get_building_def(building_id)
		if GameManager.can_afford(faction, bdef.get("cost", {})):
			_place_building(building_id)
			_build_index += 1
		return
	
	# 造兵
	var barracks: Array = _get_buildings_by_category("military")
	if barracks.size() > 0 and resources.get("gold", 0) > 30:
		var barracks_building: Building = barracks[0]
		if barracks_building.training_queue.size() < 2:
			barracks_building.train_unit("sword")
	
	# 升官府
	if GameManager.can_upgrade_government(faction):
		GameManager.upgrade_government(faction)


func _capture_nearest_neutral() -> void:
	# 找最近的中立村庄或野马
	var my_units: Array = []
	for u in GameManager.factions[faction].units:
		if is_instance_valid(u) and u.unit_id != "peasant":
			my_units.append(u)
	if my_units.is_empty():
		return
	var unit: Node = my_units[0]
	# 优先占领中立村庄
	var best_village: Village = null
	var best_dist: float = 999.0
	for v in GameManager.villages:
		if not is_instance_valid(v):
			continue
		if v.village_owner == "" or v.village_owner != faction:
			var d: float = unit.global_position.distance_to(v.global_position)
			if d < best_dist:
				best_dist = d
				best_village = v
	if best_village:
		unit.command_move(best_village.global_position)
		return
	# 其次捕获野马
	var best_horse: WildHorse = null
	best_dist = 999.0
	for h in GameManager.wild_horses:
		if not is_instance_valid(h):
			continue
		var d: float = unit.global_position.distance_to(h.global_position)
		if d < best_dist:
			best_dist = d
			best_horse = h
	if best_horse:
		unit.command_move(best_horse.global_position)
func _place_building(building_id: String) -> void:
	var faction_state = GameManager.factions[faction]
	# 在官府附近找空位
	var gov_building: Building = null
	for b in faction_state.buildings:
		if b.building_id == "government":
			gov_building = b
			break
	if gov_building == null:
		return
	var base_pos: Vector2i = GameManager.grid.world_to_grid(gov_building.global_position)
	var offset: Vector2i = Vector2i(randi_range(-4, 4), randi_range(-4, 4))
	var target: Vector2i = base_pos + offset
	var bdef: Dictionary = DataLoader.get_building_def(building_id)
	var size: Vector2i = Vector2i(bdef.get("size", [2,2])[0], bdef.get("size", [2,2])[1])
	if GameManager.grid.is_placeable(target, size):
		GameManager.spend_resources(faction, bdef.get("cost", {}))
		GameManager.grid.set_occupied(target, size, 1)
		var scene: PackedScene = load("res://scenes/Building.tscn")
		if scene:
			var b: Building = scene.instantiate()
			b.building_id = building_id
			b.faction = faction
			b.grid_pos = target
			get_tree().root.add_child(b)
			b.global_position = GameManager.grid.grid_to_world(target)

func _get_buildings_by_category(category: String) -> Array:
	var result: Array = []
	for b in GameManager.factions[faction].buildings:
		var bdef: Dictionary = DataLoader.get_building_def(b.building_id)
		if bdef.get("category", "") == category:
			result.append(b)
	return result

func _launch_attack() -> void:
	var army: Array = []
	for u in GameManager.factions[faction].units:
		if u.unit_id != "peasant":
			army.append(u)
	if army.size() < 5:
		return
	# 找敌方官府
	var target_building: Building = null
	for fid in GameManager.factions.keys():
		if fid == faction:
			continue
		for b in GameManager.factions[fid].buildings:
			if b.building_id == "government":
				target_building = b
				break
	if target_building:
		for u in army:
			u.command_move(target_building.global_position)
			u.attack_target = target_building



