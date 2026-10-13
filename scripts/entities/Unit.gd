extends CharacterBody3D
class_name Unit
## Unit — 单位基类（士兵/农夫/武将）
## 包含：移动(A*寻路)、攻击(微克制+暴击)、采集、状态机、等级/老兵系统

signal died(unit)

# 基础属性
@export var unit_id: String = "sword"
@export var faction: String = "shu"
@export var is_general: bool = false

var def: Dictionary = {}
var hp: float = 100.0
var max_hp: float = 100.0
var atk: float = 10.0
var defense: float = 4.0
var atk_speed: float = 1.0
var move_speed: float = 2.6
var range: float = 0.6
var morale: float = 60.0
var level: int = 1
var exp: float = 0.0
var kills: int = 0
var veteran_atk_bonus: float = 0.0
var stamina: float = 100.0
var mounted: bool = false

# 状态
enum State { IDLE, MOVING, ATTACKING, GATHERING, RETURNING, BUILDING, REPAIRING, GUARDING }
var state: int = State.IDLE
var attack_cooldown: float = 0.0
var is_selected: bool = false

# 目标
var move_target: Vector3 = Vector3.ZERO
var attack_target: Node = null
var gather_target: Node = null
var repair_target: Node = null
var garrison_building: Node = null
var command_queue: Array = []  # 指令队列 (Shift+点击排队)
var path: Array = []
var path_index: int = 0

# 组件
var _selection_ring: MeshInstance3D = null
var _hp_bar: Sprite3D = null
var _pathfinder: Pathfinder = null
var _sprite: Sprite3D = null

func _ready() -> void:
	def = DataLoader.get_unit_def(unit_id)
	if not def.is_empty():
		_init_from_def()
	_create_sprite()
	_create_selection_ring()
	GameManager.register_unit(self)

func _init_from_def() -> void:
	max_hp = def.get("hp", 100)
	hp = max_hp
	atk = def.get("atk", 10)
	defense = def.get("def", 4)
	atk_speed = def.get("atk_speed", 1.0)
	move_speed = def.get("move_speed", 2.6)
	range = def.get("range", 0.6)
	morale = def.get("morale", 60)

func _create_sprite() -> void:
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Determine category and id
	var cat: String = "units"
	var eid: String = unit_id
	if is_general:
		cat = "generals"
		var gid: Variant = get("general_id")
		eid = str(gid) if gid != null and str(gid) != "" else "default"
	var adef: Dictionary = DataLoader.get_asset_def(cat, eid)
	if not adef.is_empty():
		var tex: Texture2D = DataLoader.get_sprite_texture(cat, eid)
		if tex:
			_sprite.texture = tex
		var s: float = float(adef.get("scale", 1.0))
		_sprite.scale = Vector3(s, s, s)
		_sprite.position.y = float(adef.get("offset_y", 0.8))
	add_child(_sprite)

func _create_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.4
	ring_mesh.outer_radius = 0.5
	ring_mesh.ring_segments = 32
	ring_mesh.ring_segments = 8
	_selection_ring.mesh = ring_mesh
	_selection_ring.visible = false
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color.GREEN
	mat.emission_enabled = true
	mat.emission = Color.GREEN
	_selection_ring.material_override = mat
	add_child(_selection_ring)
	_selection_ring.position.y = 0.1
	_selection_ring.rotation.x = deg_to_rad(90)

func set_selected(selected: bool) -> void:
	is_selected = selected
	if _selection_ring:
		_selection_ring.visible = selected

func get_faction() -> String:
	return faction

func _process(delta: float) -> void:
	if hp <= 0:
		return
	attack_cooldown = max(0, attack_cooldown - delta)
	
	match state:
		State.IDLE:
			_process_idle()
		State.MOVING:
			_process_moving(delta)
		State.ATTACKING:
			_process_attacking(delta)
		State.GATHERING:
			_process_gathering(delta)
		State.RETURNING:
			_process_returning(delta)
		State.REPAIRING:
			_process_repairing(delta)

func _process_idle() -> void:
	# 自动攻击附近敌人
	if attack_target == null or not is_instance_valid(attack_target):
		_find_nearest_enemy()
	if attack_target:
		state = State.ATTACKING

func _find_nearest_enemy() -> void:
	var nearest: Node = null
	var nearest_dist: float = range + 3.0
	for unit in GameManager.all_units:
		if unit.get_faction() != faction and is_instance_valid(unit):
			var dist: float = global_position.distance_to(unit.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = unit
	attack_target = nearest

func _process_moving(delta: float) -> void:
	if path.size() == 0 or path_index >= path.size():
		# 到达目的地后，若有驻军目标则入驻
		if garrison_building != null and is_instance_valid(garrison_building):
			if garrison_building.has_method('garrison'):
				garrison_building.garrison(self)
			garrison_building = null
		elif repair_target != null and is_instance_valid(repair_target):
			state = State.REPAIRING
		else:
			state = State.IDLE
		return
	var target_grid: Vector2i = path[path_index]
	var target_pos: Vector3 = GameManager.grid.grid_to_world(target_grid)
	target_pos.y = global_position.y
	var direction: Vector3 = (target_pos - global_position)
	direction.y = 0
	var dist: float = direction.length()
	if dist < 0.3:
		path_index += 1
		return
	var move_dir: Vector3 = direction.normalized()
	velocity = move_dir * move_speed
	move_and_slide()

func _process_attacking(delta: float) -> void:
	if not is_instance_valid(attack_target):
		attack_target = null
		state = State.IDLE
		return
	var dist: float = global_position.distance_to(attack_target.global_position)
	if dist > range:
		# 靠近目标
		var target_grid: Vector2i = GameManager.grid.world_to_grid(attack_target.global_position)
		path = GameManager.pathfinder.find_path(GameManager.grid.world_to_grid(global_position), target_grid)
		path_index = 0
		state = State.MOVING
		return
	if attack_cooldown <= 0:
		_perform_attack()
		attack_cooldown = 1.0 / atk_speed

func _perform_attack() -> void:
	var target_unit: Unit = attack_target as Unit
	if target_unit == null:
		return
	var damage: float = _compute_damage(target_unit)
	target_unit.take_damage(damage, self)

func _compute_damage(target: Unit) -> float:
	var base_atk: float = atk + veteran_atk_bonus
	# 微克制
	var counter_mult: float = 1.0
	if def.has("counters"):
		if target.unit_id in def["counters"]:
			var counters: Dictionary = DataLoader.combat.get("counter", {})
			counter_mult = 1.0 + counters.get("base", 0.35)
	# 士气影响
	var morale_mult: float = 1.0
	if morale > 75:
		morale_mult = 1.15
	elif morale < 25:
		morale_mult = 0.85
	# 暴击
	var crit_chance: float = DataLoader.combat.get("crit", {}).get("base_chance", 0.05)
	if is_general:
		crit_chance = DataLoader.combat.get("crit", {}).get("general_chance", 0.18)
	var damage: float = base_atk * counter_mult * morale_mult
	if randf() < crit_chance:
		damage *= DataLoader.combat.get("crit", {}).get("damage_mult", 1.5)
		EventBus.float_text.emit("暴击!", global_position + Vector3(0, 3, 0), Color.RED)
	# 防御减伤
	damage = max(1.0, damage - target.defense * 0.5)
	return damage

func take_damage(amount: float, attacker: Node = null) -> void:
	hp -= amount
	EventBus.float_text.emit(str(int(amount)), global_position + Vector3(0, 2.5, 0), Color.WHITE)
	if hp <= 0:
		_die(attacker)

func _die(killer: Node = null) -> void:
	hp = 0
	if killer and killer.has_method("on_kill"):
		killer.on_kill(self)
	GameManager.unregister_unit(self)
	EventBus.unit_died.emit(self)
	died.emit(self)
	queue_free()

func on_kill(victim: Unit) -> void:
	kills += 1
	# 杀人累计攻击力
	var cap: int = DataLoader.veteran_bonus.get("soft_cap_kills", 300)
	var per_kill: float = DataLoader.veteran_bonus.get("atk_per_kill", 0.12)
	if kills <= cap:
		veteran_atk_bonus += per_kill
	# 经验
	exp += DataLoader.combat.get("experience", {}).get("kill_exp", 20)
	_check_level_up()

func _check_level_up() -> void:
	var curve: Dictionary = DataLoader.level_curve
	var key: String = "%d_to_%d" % [level, level + 1]
	if curve.has(key):
		var needed: float = curve[key].get("exp", 999)
		if exp >= needed:
			exp -= needed
			level += 1
			var growth: Dictionary = curve[key].get("growth", {})
			atk *= (1.0 + growth.get("atk", 0.0))
			defense *= (1.0 + growth.get("def", 0.0))
			EventBus.float_text.emit("升级 Lv%d!" % level, global_position + Vector3(0, 3, 0), Color.YELLOW)
			if level >= 5:
				EventBus.float_text.emit("可提拔武将!", global_position + Vector3(0, 3.5, 0), Color.GOLD)

# ==================== 指令 ====================

func command_move(target: Vector3) -> void:
	move_target = target
	attack_target = null
	var start_grid: Vector2i = GameManager.grid.world_to_grid(global_position)
	var end_grid: Vector2i = GameManager.grid.world_to_grid(target)
	path = GameManager.pathfinder.find_path(start_grid, end_grid)
	path_index = 0
	state = State.MOVING

func command_attack(target: Node) -> void:
	attack_target = target
	state = State.ATTACKING

func command_gather(node: Node) -> void:
	gather_target = node
	state = State.GATHERING

func _process_gathering(delta: float) -> void:
	if not is_instance_valid(gather_target):
		state = State.IDLE
		return
	var dist: float = global_position.distance_to(gather_target.global_position)
	if dist > 1.5:
		command_move(gather_target.global_position)
		return
	# 采集逻辑由农夫子类实现
	if unit_id == "peasant" and gather_target.has_method("gather"):
		gather_target.gather(self, delta)

func _process_returning(delta: float) -> void:
	# 寻找最近的资源仓库（官府/农田）存放资源
	var drop_off: Node = null
	var nearest_dist: float = 999.0
	for b in GameManager.all_buildings:
		if b.get_faction() == faction and b.building_id in ["government", "farm", "barracks_sword", "barracks_archer", "hanlinyuan"]:
			var d: float = global_position.distance_to(b.global_position)
			if d < nearest_dist:
				nearest_dist = d
				drop_off = b
	if drop_off == null:
		state = State.IDLE
		return
	if nearest_dist > 2.0:
		command_move(drop_off.global_position)
		return
	# 存放资源
	if has_meta("carrying"):
		var carrying: Dictionary = get_meta("carrying")
		var res_type: String = carrying.get("type", "food")
		var amount: float = carrying.get("amount", 0.0)
		GameManager.add_resource(faction, res_type, amount)
		remove_meta("carrying")
		EventBus.float_text.emit("+%d %s" % [int(amount), res_type], global_position + Vector3(0, 2, 0), Color.GREEN)
	# 返回采集点继续采集
	if is_instance_valid(gather_target):
		state = State.GATHERING
	else:
		state = State.IDLE

func command_repair(target: Node) -> void:
	"""农夫修理受损建筑"""
	if unit_id != "peasant":
		return
	if not is_instance_valid(target) or not target.has_method("is_damaged"):
		return
	if not target.is_damaged():
		EventBus.float_text.emit("无需修理", target.global_position + Vector3(0, 3, 0), Color.GRAY)
		return
	repair_target = target
	state = State.REPAIRING

func _process_repairing(delta: float) -> void:
	if not is_instance_valid(repair_target):
		state = State.IDLE
		return
	if not repair_target.has_method("is_damaged") or not repair_target.is_damaged():
		state = State.IDLE
		EventBus.float_text.emit("修理完成", repair_target.global_position + Vector3(0, 3, 0), Color.GREEN)
		return
	var dist: float = global_position.distance_to(repair_target.global_position)
	if dist > 2.0:
		command_move(repair_target.global_position)
		return
	# 修理速度：每秒恢复15点HP
	var repair_amount: float = 15.0 * delta
	if repair_target.has_method("repair"):
		repair_target.repair(repair_amount)

func command_garrison(building: Node) -> void:
	"""单位入驻建筑"""
	if not is_instance_valid(building) or not building.has_method("garrison"):
		return
	if not building.can_garrison:
		EventBus.float_text.emit("无法入驻", building.global_position + Vector3(0, 3, 0), Color.GRAY)
		return
	if building.get_garrison_count() >= building.garrison_cap:
		EventBus.float_text.emit("驻扎已满", building.global_position + Vector3(0, 3, 0), Color.GRAY)
		return
	garrison_building = building
	var dist: float = global_position.distance_to(building.global_position)
	if dist > 2.0:
		# 先走到建筑旁
		move_target = building.global_position
		var start_grid: Vector2i = GameManager.grid.world_to_grid(global_position)
		var end_grid: Vector2i = GameManager.grid.world_to_grid(building.global_position)
		path = GameManager.pathfinder.find_path(start_grid, end_grid)
		path_index = 0
		state = State.MOVING
		# 到达后自动入驻
	else:
		building.garrison(self)

