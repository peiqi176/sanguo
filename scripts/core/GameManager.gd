extends Node
## GameManager — 全局游戏状态单例
## 管理：资源/人口/官府等级/科技/民心/外交/胜负
## 所有系统通过此单例查询和修改游戏状态


# 资源类型
enum ResourceType { FOOD, WOOD, STONE, GOLD }

# 游戏配置
const TICK_INTERVAL: float = 1.0  # 经济tick间隔（秒）

# 势力数据
var factions: Dictionary = {}  # faction_id -> FactionState
var player_faction: String = "shu"

# 全局实体引用
var all_units: Array = []
var all_buildings: Array = []
var resource_nodes: Array = []
var villages: Array = []
var wild_horses: Array = []

# 游戏状态
var game_speed: float = 1.0
var paused: bool = false
var game_over: bool = false
var current_season: String = "spring"
var season_timer: float = 0.0

# 网格
var grid: Node = null
var pathfinder: Node = null
var map_size: Vector2i = Vector2i(84, 84)
var cell_size: float = 1.0

# tick计时
var _tick_timer: float = 0.0

class FactionState:
	var faction_id: String
	var resources: Dictionary = { "food": 200, "wood": 200, "stone": 100, "gold": 150 }
	var population_used: int = 0
	var population_cap: int = 20
	var government_level: int = 1
	var morale: float = 70.0
	var tax_rate: String = "medium"
	var tech_completion: float = 0.0
	var researched_techs: Array = []
	var units: Array = []
	var buildings: Array = []
	var color: Color = Color.WHITE
	var trust: Dictionary = {}  # other_faction -> trust value
	var resource_rates: Dictionary = {}  # res -> per-second rate
	var defeated: bool = false
	var horses: int = 0  # 捕获的马匹储备
	
	func _init(id: String):
		faction_id = id


func _ready() -> void:
	_init_factions()
	print("[GameManager] 初始化完成")

func _init_factions() -> void:
	for faction_id in DataLoader.factions["factions"].keys():
		var def := DataLoader.get_faction_def(faction_id)
		var state := FactionState.new(faction_id)
		if def.has("starting_resources"):
			state.resources = def["starting_resources"].duplicate()
		if def.has("color"):
			state.color = Color.from_string(def["color"], Color.WHITE)
		# 初始化信任度
		for other in DataLoader.factions["factions"].keys():
			if other != faction_id:
				state.trust[other] = 50
		factions[faction_id] = state

func _process(delta: float) -> void:
	if paused or game_over:
		return
	var d := delta * game_speed
	_tick_timer += d
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer = 0.0
		_economic_tick()
	# 季节推进
	season_timer += d
	var season_duration: float = 120.0
	if DataLoader.seasons.has("duration_per_season"):
		season_duration = DataLoader.seasons["duration_per_season"]
	if season_timer >= season_duration:
		season_timer = 0.0
		_advance_season()

func _economic_tick() -> void:
	for faction_id in factions.keys():
		var state: FactionState = factions[faction_id]
		# 建筑产出
		for b in state.buildings:
			if b.has_method("get_production"):
				var prod: Dictionary = b.get_production()
				for res in prod.keys():
					state.resources[res] = (state.resources.get(res, 0) as float) + prod[res]
		# 民心随税率变化
		var tax_rates: Dictionary = DataLoader.factions.get("tax_rates", {})
		if tax_rates.has(state.tax_rate):
			var morale_delta: float = tax_rates[state.tax_rate].get("morale_delta", 0.0)
			state.morale = clampf(state.morale + morale_delta, 0, 100)
		# 饥荒检测
		if state.resources.get("food", 0) < 0:
			state.morale = clampf(state.morale - 2.0, 0, 100)
			state.resources["food"] = 0
		EventBus.morale_changed.emit(faction_id, state.morale)
		_update_resource_rates(faction_id)
		EventBus.resources_changed.emit(faction_id)

func _advance_season() -> void:
	var order: Array = DataLoader.seasons.get("seasons", ["spring","summer","autumn","winter"])
	var idx: int = order.find(current_season)
	idx = (idx + 1) % order.size()
	current_season = order[idx]
	EventBus.season_changed.emit(current_season)
	print("[GameManager] 季节变更: %s" % current_season)

# ==================== 资源系统 ====================

func get_resource(faction_id: String, res: String) -> float:
	if not factions.has(faction_id):
		return 0.0
	return factions[faction_id].resources.get(res, 0.0)

func add_resource(faction_id: String, res: String, amount: float) -> void:
	if not factions.has(faction_id):
		return
	factions[faction_id].resources[res] = (factions[faction_id].resources.get(res, 0.0) as float) + amount
	if factions[faction_id].resources[res] < 0:
		factions[faction_id].resources[res] = 0
	EventBus.resources_changed.emit(faction_id)

func can_afford(faction_id: String, cost: Dictionary) -> bool:
	if not factions.has(faction_id):
		return false
	var state: FactionState = factions[faction_id]
	for res in cost.keys():
		if state.resources.get(res, 0) < cost[res]:
			return false
	return true

func spend_resources(faction_id: String, cost: Dictionary) -> bool:
	if not can_afford(faction_id, cost):
		return false
	var state: FactionState = factions[faction_id]
	for res in cost.keys():
		state.resources[res] -= cost[res]
	EventBus.resources_changed.emit(faction_id)
	return true

# ==================== 人口系统 ====================

func get_population(faction_id: String) -> Dictionary:
	if not factions.has(faction_id):
		return { "used": 0, "cap": 0 }
	var state: FactionState = factions[faction_id]
	return { "used": state.population_used, "cap": state.population_cap }

func can_train(faction_id: String, pop_cost: int) -> bool:
	if not factions.has(faction_id):
		return false
	var state: FactionState = factions[faction_id]
	return state.population_used + pop_cost <= state.population_cap

func change_population(faction_id: String, delta: int) -> void:
	if not factions.has(faction_id):
		return
	factions[faction_id].population_used = max(0, factions[faction_id].population_used + delta)
	EventBus.resources_changed.emit(faction_id)

func add_population_cap(faction_id: String, amount: int) -> void:
	if not factions.has(faction_id):
		return
	factions[faction_id].population_cap += amount
	EventBus.resources_changed.emit(faction_id)

# ==================== 官府等级 ====================

func get_government_level(faction_id: String) -> int:
	if not factions.has(faction_id):
		return 1
	return factions[faction_id].government_level

func can_upgrade_government(faction_id: String) -> bool:
	if not factions.has(faction_id):
		return false
	var state: FactionState = factions[faction_id]
	var cur: int = state.government_level
	if cur >= 4:
		return false
	var upgrade_key: String = "%d_to_%d" % [cur, cur + 1]
	var upgrades: Dictionary = DataLoader.tech.get("government_upgrade", {})
	if not upgrades.has(upgrade_key):
		return false
	var up: Dictionary = upgrades[upgrade_key]
	# 官府2级需要科技达60%
	if cur == 1 and state.tech_completion < up.get("tech_completion_required", 0.6):
		return false
	return can_afford(faction_id, up.get("cost", {}))

func upgrade_government(faction_id: String) -> bool:
	if not can_upgrade_government(faction_id):
		return false
	var state: FactionState = factions[faction_id]
	var cur: int = state.government_level
	var upgrade_key: String = "%d_to_%d" % [cur, cur + 1]
	var up: Dictionary = DataLoader.tech["government_upgrade"][upgrade_key]
	spend_resources(faction_id, up["cost"])
	state.government_level = cur + 1
	EventBus.government_upgraded.emit(faction_id, state.government_level)
	return true

# ==================== 科技系统 ====================

func research_tech(faction_id: String, branch: String, tech_id: String) -> bool:
	if not factions.has(faction_id):
		return false
	var state: FactionState = factions[faction_id]
	var branches: Dictionary = DataLoader.tech.get("branches", {})
	if not branches.has(branch) or not branches[branch].has("techs"):
		return false
	var techs: Dictionary = branches[branch]["techs"]
	if not techs.has(tech_id):
		return false
	var tech_def: Dictionary = techs[tech_id]
	if state.researched_techs.has(tech_id):
		return false
	# 检查官府等级
	if state.government_level < tech_def.get("gov_req", 1):
		return false
	# 检查前置科技
	if tech_def.has("requires"):
		for req in tech_def["requires"]:
			if not state.researched_techs.has(req):
				return false
	if not can_afford(faction_id, tech_def.get("cost", {})):
		return false
	spend_resources(faction_id, tech_def["cost"])
	state.researched_techs.append(tech_id)
	# 更新科技完成度
	var total_techs: int = 0
	for b in branches.values():
		total_techs += b.get("techs", {}).size()
	state.tech_completion = float(state.researched_techs.size()) / float(total_techs)
	EventBus.tech_researched.emit(faction_id, tech_id)
	return true

func get_tech_completion(faction_id: String) -> float:
	if not factions.has(faction_id):
		return 0.0
	return factions[faction_id].tech_completion

# ==================== 民心/税率 ====================

func get_morale(faction_id: String) -> float:
	if not factions.has(faction_id):
		return 50.0
	return factions[faction_id].morale

func set_tax_rate(faction_id: String, rate: String) -> void:
	if not factions.has(faction_id):
		return
	if rate in ["low", "medium", "high"]:
		factions[faction_id].tax_rate = rate

# ==================== 注册实体 ====================

func register_unit(unit) -> void:
	if not all_units.has(unit):
		all_units.append(unit)
	if unit.get_faction() in factions:
		factions[unit.get_faction()].units.append(unit)

func unregister_unit(unit) -> void:
	all_units.erase(unit)
	if unit.get_faction() in factions:
		factions[unit.get_faction()].units.erase(unit)

func register_building(building) -> void:
	if not all_buildings.has(building):
		all_buildings.append(building)
	if building.get_faction() in factions:
		factions[building.get_faction()].buildings.append(building)

func unregister_building(building) -> void:
	all_buildings.erase(building)
	if building.get_faction() in factions:
		factions[building.get_faction()].buildings.erase(building)

# ==================== 胜负判定 ====================

func check_victory() -> void:
	if game_over:
		return
	for faction_id in factions.keys():
		var state: FactionState = factions[faction_id]
		# 检查是否有官府存在
		var has_government: bool = false
		for b in state.buildings:
			if b.building_id == "government":
				has_government = true
				break
		if not has_government and not state.defeated:
			state.defeated = true
			EventBus.defeat.emit(faction_id)
			print("[GameManager] %s 被击败" % faction_id)
	# 检查是否只剩一个势力
	var alive: Array = []
	for fid in factions.keys():
		if not factions[fid].defeated:
			alive.append(fid)
	if alive.size() == 1:
		game_over = true
		EventBus.victory.emit(alive[0])
		print("[GameManager] 游戏结束，%s 胜利" % alive[0])

func set_paused(p: bool) -> void:
	paused = p

func set_game_speed(s: float) -> void:
	game_speed = s









# ==================== 外交系统 ====================

func get_trust(from_faction: String, to_faction: String) -> int:
	if not factions.has(from_faction):
		return 50
	return int(factions[from_faction].trust.get(to_faction, 50))

func get_relation(from_faction: String, to_faction: String) -> String:
	var trust_val: int = get_trust(from_faction, to_faction)
	if trust_val >= 80:
		return "alliance"
	elif trust_val <= 20:
		return "war"
	else:
		return "neutral"

func diplomatic_action(from_faction: String, to_faction: String, action_id: String) -> bool:
	if not factions.has(from_faction) or not factions.has(to_faction):
		return false
	var actions: Dictionary = DataLoader.diplomacy.get("actions", {})
	if not actions.has(action_id):
		return false
	var adef: Dictionary = actions[action_id]
	var from_state: FactionState = factions[from_faction]
	var to_state: FactionState = factions[to_faction]
	var cost: Dictionary = adef.get("cost", {})
	if not cost.is_empty() and not can_afford(from_faction, cost):
		return false
	if adef.has("trust_required") and from_state.trust.get(to_faction, 50) < adef["trust_required"]:
		return false
	if not cost.is_empty():
		spend_resources(from_faction, cost)
	match adef.get("effect", ""):
		"hostile":
			from_state.trust[to_faction] = clampi(from_state.trust.get(to_faction, 50) + adef.get("trust_delta", 0), 0, 100)
			to_state.trust[from_faction] = clampi(to_state.trust.get(from_faction, 50) + adef.get("trust_delta", 0), 0, 100)
		"alliance":
			from_state.trust[to_faction] = 100
			to_state.trust[from_faction] = 100
		"trade", "tribute", "marriage":
			from_state.trust[to_faction] = clampi(from_state.trust.get(to_faction, 50) + adef.get("trust_delta", 0), 0, 100)
			to_state.trust[from_faction] = clampi(to_state.trust.get(from_faction, 50) + int(adef.get("trust_delta", 0) * 0.5), 0, 100)
		"sabotage":
			var success: bool = randf() < adef.get("success_rate", 0.5)
			if success:
				to_state.trust[from_faction] = clampi(to_state.trust.get(from_faction, 50) + adef.get("trust_delta_target", 0), 0, 100)
			return success
	EventBus.diplomatic_action.emit(action_id, from_faction, to_faction)
	return true

# ==================== 资源速率 ====================

func get_resource_rate(faction_id: String, res: String) -> float:
	if not factions.has(faction_id):
		return 0.0
	return factions[faction_id].resource_rates.get(res, 0.0)

func _update_resource_rates(faction_id: String) -> void:
	if not factions.has(faction_id):
		return
	var state: FactionState = factions[faction_id]
	var rates: Dictionary = {}
	for b in state.buildings:
		if b.has_method("get_production"):
			var prod: Dictionary = b.get_production()
			for res in prod.keys():
				rates[res] = rates.get(res, 0.0) + prod[res]
	state.resource_rates = rates

