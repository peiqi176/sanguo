extends CharacterBody3D
class_name SupplyCart
## SupplyCart — 辎重车，随队补给站
## 提供范围内友军恢复体力/士气，可扎营变成营帐，被劫则断供

@export var cart_id: String = "cart_0"
var faction: String = ""
var hp: float = 200.0
var max_hp: float = 200.0
var move_speed: float = 1.8
var bun: float = 200.0
var max_bun: float = 200.0
var wine: float = 200.0
var max_wine: float = 200.0
var aura_radius: float = 6.0
var aura_radius_move: float = 6.0
var service_capacity: int = 15
var garrison_cap: int = 10
var setup_time: float = 3.0
var pack_time: float = 3.0
var garrison_recover_mult: float = 1.5

# 状态：0=IDLE, 1=MOVING, 2=SETUP(扎营中), 3=CAMPED(已扎营), 4=PACKING(打包中)
var state: int = 0
var target_pos: Vector3 = Vector3.ZERO
var _aura_timer: float = 0.0
var _dead: bool = false
var _state_timer: float = 0.0
var _deploying: bool = false
var garrisoned_units: Array = []

func _ready() -> void:
	GameManager.all_units.append(self)
	var sdef: Dictionary = DataLoader.logistics.get("supply_cart", {})
	max_hp = sdef.get("hp", 200)
	hp = max_hp
	move_speed = sdef.get("move_speed", 1.8)
	max_bun = sdef.get("bun_capacity", 200)
	bun = max_bun
	max_wine = sdef.get("wine_capacity", 200)
	wine = max_wine
	aura_radius_move = float(sdef.get("aura_radius_move", sdef.get("aura_radius", 6.0)))
	aura_radius = aura_radius_move
	service_capacity = sdef.get("service_capacity", 15)
	garrison_cap = sdef.get("garrison_cap", 10)
	setup_time = sdef.get("setup_time", 3.0)
	pack_time = sdef.get("pack_time", 3.0)
	garrison_recover_mult = sdef.get("garrison_recover_mult", 1.5)
	_create_visual()

func _create_visual() -> void:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	var adef: Dictionary = DataLoader.get_asset_def("supply_cart", "supply_cart")
	if not adef.is_empty():
		var tex: Texture2D = DataLoader.get_sprite_texture("supply_cart", "supply_cart")
		if tex:
			sprite.texture = tex
		sprite.pixel_size = DataLoader.get_sprite_pixel_size("supply_cart", tex)
		var s: float = float(adef.get("scale", 1.5))
		sprite.scale = Vector3(s, s, s)
		# 贴地公式统一：底边留白是量出来的（offset_y 现在只表示额外抬升米数）
		sprite.position.y = DataLoader.get_sprite_anchor_y("supply_cart", "supply_cart", s)
	add_child(sprite)

func get_faction() -> String:
	return faction

func _process(delta: float) -> void:
	if GameManager.paused or GameManager.game_over or _dead:
		return
	match state:
		1:  # MOVING
			_move_toward(delta)
		2:  # SETUP：扎营完成 → 就地转换成营帐建筑（体力恢复 +4/s）
			_state_timer -= delta
			if _state_timer <= 0.0:
				_deploy_as_tent()
		4:  # PACKING
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = 0
				EventBus.float_text.emit("📦 打包完成", global_position + Vector3(0, 3, 0), Color.YELLOW)
	# 补给光环（库存耗尽则停止）
	_aura_timer += delta
	if _aura_timer >= 1.0:
		_aura_timer = 0.0
		_apply_supply_aura()
	# 辎重车缓慢消耗自身库存
	if bun > 0:
		bun = max(0.0, bun - 0.2 * delta)

func _move_toward(delta: float) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0
	if dir.length() < 0.5:
		state = 0
		return
	dir = dir.normalized()
	velocity = dir * move_speed
	move_and_slide()
	_snap_to_ground(delta)

## 贴地：辎重车原来完全不贴地，y 永远停在出生高度（山坡上就悬空/入地）
func _snap_to_ground(delta: float) -> void:
	var gh: float = Terrain.get_height(global_position.x, global_position.z)
	var dy: float = gh - global_position.y
	if absf(dy) > 1.2:
		global_position.y = gh
	else:
		global_position.y = lerpf(global_position.y, gh, clampf(delta * 20.0, 0.0, 1.0))

func command_move(target: Vector3) -> void:
	if state == 3 or state == 2:
		return  # 扎营状态不能移动
	target_pos = target
	state = 1

func command_setup() -> bool:
	"""扎营（3秒）→ 完成后就地转换为营帐建筑"""
	if state != 0 and state != 1:
		return false
	state = 2
	_state_timer = setup_time
	EventBus.float_text.emit("⛺ 扎营中...（将为营帐）", global_position + Vector3(0, 3, 0), Color.YELLOW)
	return true

## ⛺ 辎重车 → 营帐：粮草入库 + 生成一座已建成的 tent 建筑 + 自己移除
## 营帐补给圈 8 格、附近体力恢复 +4/s（比城池/村庄的 +2/s 快一倍）
func _deploy_as_tent() -> void:
	if _deploying:
		return
	_deploying = true
	var scene: PackedScene = load("res://scenes/Building.tscn")
	if scene == null:
		_deploying = false
		state = 0
		EventBus.float_text.emit("⛺ 扎营失败：营帐场景缺失", global_position + Vector3(0, 3, 0), Color.RED)
		return
	var tent = scene.instantiate()
	tent.building_id = "tent"
	tent.faction = faction
	tent.spawn_as_complete = true
	# 占格（有网格系统才登记，编辑器探针场景下 grid 可能为空）
	if GameManager.grid != null and GameManager.grid.has_method("world_to_grid"):
		var gp: Vector2i = GameManager.grid.world_to_grid(global_position)
		tent.grid_pos = gp
		GameManager.grid.set_occupied(gp, Vector2i(2, 2), 1)
	get_parent().add_child(tent)
	tent.global_position = global_position
	# 车上粮草随营帐入库，不凭空消失
	if bun > 0.0:
		GameManager.add_resource(faction, "bun", bun)
		bun = 0.0
	if wine > 0.0:
		GameManager.add_resource(faction, "wine", wine)
		wine = 0.0
	EventBus.float_text.emit("⛺ 已转为营帐", global_position + Vector3(0, 3, 0), Color.GREEN)
	GameManager.all_units.erase(self)
	queue_free()

func command_pack() -> bool:
	"""打包：取消正在进行的扎营（车还在原地，不会生成营帐）"""
	if state != 2:
		return false
	state = 0
	_state_timer = 0.0
	EventBus.float_text.emit("📦 已取消扎营", global_position + Vector3(0, 3, 0), Color.YELLOW)
	return true

func is_camped() -> bool:
	# 🚚 补给光环：车只要在场上（收起/行进/正在转营帐）就生效，仅打包中失效。
	# 注意：扎营 3 秒后车体会被营帐替换，因此不存在 state==3 的长期态。
	return state != 4

# 💾 存档 / 读档
func serialize() -> Dictionary:
	return {
		"type": "supply_cart",
		"cart_id": cart_id,
		"faction": faction,
		"pos": {"x": global_position.x, "y": global_position.y, "z": global_position.z},
		"hp": hp,
		"max_hp": max_hp,
		"bun": bun,
		"wine": wine,
		"state": state,
	}

func apply_state(d: Dictionary) -> void:
	cart_id = str(d.get("cart_id", cart_id))
	hp = float(d.get("hp", hp))
	max_hp = float(d.get("max_hp", max_hp))
	bun = float(d.get("bun", max_bun))
	wine = float(d.get("wine", max_wine))
	# ⛺ 扎营现在会直接转成营帐建筑、辎重车本身消失；
	# 旧存档里的「已扎营」辎重车按收起态恢复（state 3 不再产生）
	state = 0
	aura_radius = aura_radius_move

func _apply_supply_aura() -> void:
	"""辎重车光环：**体力冻结**由 Unit 侧 mode=hold 处理（这里不再直接加体力），
	车上只负责供粮（扣包子）与回士气。"""
	if bun <= 0 and wine <= 0:
		return  # 库存耗尽，光环停止
	var served: int = 0
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u == self:
			continue
		if not u.has_method("get_faction") or u.get_faction() != faction:
			continue
		if global_position.distance_to(u.global_position) > aura_radius:
			continue
		if served >= service_capacity:
			break
		# 供粮：单位在圈的判定由 Unit._update_supply_state 做，这里只扣车上包子
		if "stamina" in u and bun > 0:
			bun = max(0.0, bun - 0.5)
		# 恢复士气
		if "morale" in u and wine > 0:
			u.morale = min(100.0, u.morale + 0.5)
			wine = max(0.0, wine - 0.1)
		served += 1

func garrison_unit(unit: Node) -> bool:
	"""单位驻扎进辎重车/营帐"""
	if garrisoned_units.size() >= garrison_cap:
		return false
	if not garrisoned_units.has(unit):
		garrisoned_units.append(unit)
		if unit.has_method("set_garrisoned"):
			unit.set_garrisoned(true)
		return true
	return false

func ungarrison_unit(unit: Node) -> void:
	if garrisoned_units.has(unit):
		garrisoned_units.erase(unit)
		if unit.has_method("set_garrisoned"):
			unit.set_garrisoned(false)

func take_damage(amount: float, attacker: Node) -> void:
	if _dead:
		return
	hp -= amount
	# 劫敌营帐：回复体力 = 剩余粮草/1000 × 对方本次伤害
	if attacker and attacker.has_method("get_faction") and attacker.get_faction() != faction:
		if "stamina" in attacker:
			var grain_remaining: float = bun + wine
			var stam_recover: float = grain_remaining / 1000.0 * max(amount, 5.0)
			stam_recover = clamp(stam_recover, 0.0, 20.0)  # 单次上限20
			attacker.stamina = min(100.0, attacker.stamina + stam_recover)
	if hp <= 0:
		_destroy(attacker)

func _destroy(killer: Node) -> void:
	_dead = true
	# 释放驻扎单位
	for u in garrisoned_units:
		if is_instance_valid(u) and u.has_method("set_garrisoned"):
			u.set_garrisoned(false)
	garrisoned_units.clear()
	# 摧毁时半径8格+15体力给劫方
	if killer and killer.has_method("get_faction"):
		var kf: String = killer.get_faction()
		for u in GameManager.all_units:
			if is_instance_valid(u) and u.has_method("get_faction") and u.get_faction() == kf:
				if global_position.distance_to(u.global_position) < 8.0:
					if "stamina" in u:
						u.stamina = min(100.0, u.stamina + 15.0)
		# 断粮效果：周围友军士气大降
		for u2 in GameManager.all_units:
			if is_instance_valid(u2) and u2.has_method("get_faction") and u2.get_faction() == faction:
				if global_position.distance_to(u2.global_position) < aura_radius * 2:
					if "morale" in u2:
						u2.morale = max(0.0, u2.morale - 15.0)
		EventBus.float_text.emit("辎重被劫! 断粮!", global_position + Vector3(0, 3, 0), Color.RED)
		# 劫粮方获得部分粮草
		if kf in GameManager.factions:
			GameManager.factions[kf].resources["bun"] = (GameManager.factions[kf].resources.get("bun", 0) as float) + bun * 0.3
			GameManager.factions[kf].resources["wine"] = (GameManager.factions[kf].resources.get("wine", 0) as float) + wine * 0.3
	GameManager.all_units.erase(self)
	queue_free()
