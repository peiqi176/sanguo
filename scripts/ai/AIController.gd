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
var _general_timer: float = 3.0

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
	_general_timer -= delta
	
	if _decision_timer <= 0:
		# 🎯 设计v3：操作速度 = 反应延迟（3s/2s/1s/0.5s）
		# 从"动作就绪"到"执行下一步"的间隔，所有档位决策逻辑相同，只比手速
		_decision_timer = max(GameManager.ai_reaction_delay, 0.5)
		_make_decision()
	if _attack_timer <= 0:
		_attack_timer = 45.0 / difficulty
		_launch_attack()
	if _capture_timer <= 0:
		_capture_timer = 15.0 / difficulty
		_capture_nearest_neutral()
	if _general_timer <= 0:
		_general_timer = 4.0  # 每4秒检查一次武将技能
		_general_auto_cast()

func _make_decision() -> void:
	var faction_state = GameManager.factions[faction]
	var resources: Dictionary = faction_state.resources
	
	# === 1. 优先确保有农夫 ===
	var peasants: Array = []
	var idle_peasants: Array = []
	for u in faction_state.units:
		if is_instance_valid(u) and u.unit_id == "peasant":
			peasants.append(u)
			if u.state == 0 or u.state == 1:
				idle_peasants.append(u)
	
	# 如果农夫 < 经济建筑数 × 2，训练农夫
	var econ_buildings: Array = _get_buildings_by_category("economy")
	var needed_peasants: int = econ_buildings.size() * 2 + 2  # 每个经济建筑2个农夫 + 2个备用
	if peasants.size() < needed_peasants:
		_train_peasant()
	
	# === 2. 把空闲农夫派入经济建筑 ===
	for econ_b in econ_buildings:
		if not is_instance_valid(econ_b):
			continue
		if econ_b.get_worker_slots_available() > 0:
			var best_peasant = null
			var best_dist: float = 999.0
			for p in idle_peasants:
				if p.state != 0:
					continue
				var d: float = p.global_position.distance_to(econ_b.global_position)
				if d < best_dist:
					best_dist = d
					best_peasant = p
			if best_peasant:
				best_peasant.command_work(econ_b)
				idle_peasants.erase(best_peasant)
	
	# === 3. 发展思路决定下一个建筑（动态决策，优先于固定队列） ===
	var next_id: String = _decide_next_building()
	if next_id == "" and _build_index < _build_order.size():
		next_id = _build_order[_build_index]
	if next_id != "":
		var bdef: Dictionary = DataLoader.get_building_def(next_id)
		if GameManager.can_afford(faction, bdef.get("cost", {})):
			_place_building(next_id)
			if _build_index < _build_order.size() and _build_order[_build_index] == next_id:
				_build_index += 1
		return
	
	# === 4. 造兵 ===
	var barracks: Array = _get_buildings_by_category("military")
	if barracks.size() > 0:
		for b in barracks:
			if b.training_queue.size() < 3:
				if GameManager.can_afford(faction, DataLoader.get_unit_def("sword").get("cost", {})):
					b.train_unit("sword")
				if GameManager.can_afford(faction, DataLoader.get_unit_def("archer").get("cost", {})):
					b.train_unit("archer")
	
	# === 5. 升官府 ===
	if GameManager.can_upgrade_government(faction):
		GameManager.upgrade_government(faction)

func _train_peasant() -> void:
	"""在牌楼/paifang 训练农夫"""
	var recruit_buildings: Array = []
	for b in GameManager.factions[faction].buildings:
		var bdef: Dictionary = DataLoader.get_building_def(b.building_id)
		if "recruit_peasant" in bdef.get("function", []):
			recruit_buildings.append(b)
	if recruit_buildings.is_empty():
		# fallback：任意有训练能力的建筑
		recruit_buildings = GameManager.factions[faction].buildings
	if recruit_buildings.is_empty():
		return
	var target = recruit_buildings[0]
	# 训练农夫 = 在 target 旁边 spawn 一个 peasant（不走 train_unit 队列，快速补充）
	# 或者走 train_unit 队列（需要 peasants.json 里有 train_time/cost）
	var udef: Dictionary = DataLoader.get_unit_def("peasant")
	if udef.is_empty():
		return
	if GameManager.can_afford(faction, udef.get("cost", {})):
		if target.training_queue.size() < 3:
			target.train_unit("peasant")


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
	var best_village = null
	var best_dist: float = 999.0
	for v in GameManager.villages:
		if not is_instance_valid(v):
			continue
		if v.village_owner == "" or v.village_owner != faction:
			var dv: float = unit.global_position.distance_to(v.global_position)
			if dv < best_dist:
				best_dist = dv
				best_village = v
	if best_village:
		unit.command_move(best_village.global_position)
		return
	# 其次捕获野马
	var best_horse = null
	best_dist = 999.0
	for h in GameManager.wild_horses:
		if not is_instance_valid(h):
			continue
		var dh: float = unit.global_position.distance_to(h.global_position)
		if dh < best_dist:
			best_dist = dh
			best_horse = h
	if best_horse:
		unit.command_move(best_horse.global_position)

func _place_building(building_id: String) -> void:
	var faction_state = GameManager.factions[faction]
	# 在官府附近找空位
	var gov_building = null
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
		var occ_val: int = 1
		if building_id.begins_with("wall_") or building_id == "gate":
			occ_val = 2
		GameManager.grid.set_occupied(target, size, occ_val)
		var scene: PackedScene = load("res://scenes/Building.tscn")
		if scene:
			var b = scene.instantiate()
			if building_id.begins_with("wall_") or building_id == "gate":
				var wall_script: GDScript = load("res://scripts/entities/Wall.gd") as GDScript
				if wall_script:
					b.set_script(wall_script)
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

func _count_building_type(type_id: String) -> int:
	var count: int = 0
	for b in GameManager.factions[faction].buildings:
		if is_instance_valid(b) and b.building_id == type_id:
			count += 1
	return count

func _decide_next_building() -> String:
	## 🎯 设计v3 发展思路（所有档位共享，AI 赢在思路好）：
	## 1. 农夫需求未满足 → 优先建民居（扩农夫人口上限）
	## 2. 经济稳定 → 建多个兵营同时练兵
	## 3. 兵营成型 → 器械房（攻城准备）
	var econ: Array = _get_buildings_by_category("economy")
	var mil: Array = _get_buildings_by_category("military")
	var peasants: int = 0
	for u in GameManager.factions[faction].units:
		if is_instance_valid(u) and u.unit_id == "peasant":
			peasants += 1
	# 思路1: 农夫 < 经济建筑×2+2 → 优先民居（民居最多 5 个，防铺满）
	if peasants < econ.size() * 2 + 2 and _count_building_type("house") < 5:
		return "house"
	# 思路2: 经济建筑 >= 3 且兵营 < 3 → 多兵营同时爆兵
	if econ.size() >= 3 and mil.size() < 3:
		return "barracks_sword"
	# 思路3: 兵营 >= 3 → 器械房（投石车准备）
	if mil.size() >= 3 and _count_building_type("siege_workshop") < 1:
		return "siege_workshop"
	return ""

func _launch_attack() -> void:
	# === 统计双方兵力 ===
	var my_combat: Array = []
	for u in GameManager.factions[faction].units:
		if is_instance_valid(u) and u.unit_id != "peasant":
			my_combat.append(u)
	
	# 敌方总兵力（玩家势力）
	var enemy_combat: int = 0
	var target_faction: String = GameManager.player_faction
	if target_faction != "":
		for u in GameManager.factions[target_faction].units:
			if is_instance_valid(u) and u.unit_id != "peasant":
				enemy_combat += 1
	
	# 兵力不足 或 还没敌人 → 不进攻
	if my_combat.is_empty() or enemy_combat == 0:
		return
	# 兵力不够（己方 < 敌方 × 1.2） → 等待
	if my_combat.size() < int(float(enemy_combat) * 1.2 * difficulty):
		return
	
	# === 找敌方官府 ===
	var target_pos: Vector3 = Vector3.ZERO
	var target_gov = null
	if target_faction != "":
		for b in GameManager.factions[target_faction].buildings:
			if is_instance_valid(b) and b.building_id == "government":
				target_gov = b
				target_pos = b.global_position
				break
	
	if target_pos == Vector3.ZERO:
		return
	
	# === 派军队进攻：主力打官府，分队拔敌方村镇 ===
	# 🏛 官府/村镇都是 10% 锁血：单位打到位后会自行停火、进入范围推进占领条（Unit._process_capture_hold）
	var enemy_village = _find_enemy_village()
	print("[AI %s] 发起进攻！兵力 %d vs 敌方 %d%s" % [faction, my_combat.size(), enemy_combat,
		"" if enemy_village == null else "，并分兵打村镇"])
	var idx: int = 0
	for u in my_combat:
		if _is_target_locked(target_gov):
			# 官府已锁血：留一部分进城占领，其余转火村镇
			if enemy_village != null and idx % 2 == 1:
				u.command_attack(enemy_village)
			elif is_instance_valid(target_gov):
				u.command_attack(target_gov)
			else:
				u.command_move(target_pos)
		else:
			# 官府未锁血：主力攻城，每 3 人留 1 人去村镇
			if enemy_village != null and idx % 3 == 2:
				u.command_attack(enemy_village)
			elif is_instance_valid(target_gov):
				u.command_attack(target_gov)
			else:
				u.command_move(target_pos)
		idx += 1

func _is_target_locked(node) -> bool:
	return is_instance_valid(node) and node.has_method("is_hp_locked") and node.is_hp_locked()

func _find_enemy_village():
	"""找最近的敌方（玩家）村镇，没有就找任意非我方村镇"""
	var best = null
	var best_dist: float = 999999.0
	var origin: Vector3 = Vector3.ZERO
	var has_origin: bool = false
	for b in GameManager.factions[faction].buildings:
		if is_instance_valid(b) and b.building_id == "government":
			origin = b.global_position
			has_origin = true
			break
	for v in GameManager.villages:
		if not is_instance_valid(v):
			continue
		if v.village_owner == faction or v.village_owner == "":
			continue
		var d: float = 0.0
		if has_origin:
			d = origin.distance_to(v.global_position)
		if d < best_dist:
			best_dist = d
			best = v
	return best

func _general_auto_cast() -> void:
	"""让 AI 武将自动放技能"""
	for u in GameManager.factions[faction].units:
		if not is_instance_valid(u) or not ("mp" in u):  # duck-type General
			continue
		var g = u  # General（弱类型）
		if g.mp < 20:
			continue
		# 附近有敌人 → 放主动技能
		var nearest_enemy = null
		var nearest_dist: float = 999.0
		for eu in GameManager.all_units:
			if not is_instance_valid(eu) or eu.get_faction() == faction:
				continue
			var d: float = g.global_position.distance_to(eu.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest_enemy = eu
		if nearest_enemy and nearest_dist < 8.0:
			# 有敌人靠近 → 放主动技能
			if g.skill_cooldowns.get("active", 0) <= 0 and g.mp >= g.active_skill.get("mp_cost", 0):
				g.cast_active_skill(g.global_position, nearest_enemy)
			elif g.skill_cooldowns.get("ultimate", 0) <= 0 and g.mp >= g.ultimate_skill.get("mp_cost", 0):
				g.cast_ultimate(g.global_position, nearest_enemy)
			elif g.basic_skills.size() > 0 and g.skill_cooldowns.get(g.basic_skills[0], 0) <= 0:
				g.cast_basic_skill(g.basic_skills[0], g.global_position, nearest_enemy)
		elif nearest_enemy and nearest_dist < 15.0:
			# 远方有敌人 → 放第一个基础技能（buff 类）
			if g.basic_skills.size() > 0 and g.skill_cooldowns.get(g.basic_skills[0], 0) <= 0:
				g.cast_basic_skill(g.basic_skills[0], g.global_position)
