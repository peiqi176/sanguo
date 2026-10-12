extends CharacterBody3D
class_name SupplyCart
## SupplyCart — 辎重车，随队补给站
## 提供范围内友军恢复体力/士气/粮补，被劫则断供

@export var cart_id: String = "cart_0"
var faction: String = ""
var hp: float = 200.0
var max_hp: float = 200.0
var move_speed: float = 1.8
var food: float = 500.0
var max_food: float = 500.0
var aura_radius: float = 6.0

var state: int = 0  # 0=IDLE, 1=MOVING
var target_pos: Vector3 = Vector3.ZERO
var _aura_timer: float = 0.0
var _dead: bool = false

func _ready() -> void:
	GameManager.all_units.append(self)
	var sdef: Dictionary = DataLoader.logistics.get("supply_cart", {})
	max_hp = sdef.get("hp", 200)
	hp = max_hp
	move_speed = sdef.get("move_speed", 1.8)
	max_food = sdef.get("capacity", 500)
	food = max_food
	aura_radius = sdef.get("aura_radius", 6.0)
	_create_visual()

func _create_visual() -> void:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var adef: Dictionary = DataLoader.get_asset_def("supply_cart", "supply_cart")
	if not adef.is_empty():
		var tex: Texture2D = DataLoader.get_sprite_texture("supply_cart", "supply_cart")
		if tex:
			sprite.texture = tex
		var s: float = float(adef.get("scale", 1.5))
		sprite.scale = Vector3(s, s, s)
		sprite.position.y = float(adef.get("offset_y", 0.7))
	add_child(sprite)

func get_faction() -> String:
	return faction

func _process(delta: float) -> void:
	if GameManager.paused or GameManager.game_over or _dead:
		return
	if state == 1:
		_move_toward(delta)
	# 补给光环
	_aura_timer += delta
	if _aura_timer >= 1.0:
		_aura_timer = 0.0
		_apply_supply_aura()
	# 辎重车缓慢消耗自身粮草
	if food > 0:
		food = max(0.0, food - 0.2 * delta)

func _move_toward(delta: float) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0
	if dir.length() < 0.5:
		state = 0
		return
	dir = dir.normalized()
	velocity = dir * move_speed
	move_and_slide()

func command_move(target: Vector3) -> void:
	target_pos = target
	state = 1

func _apply_supply_aura() -> void:
	if food <= 0:
		return
	var sdef: Dictionary = DataLoader.logistics.get("supply_cart", {})
	var effects: Dictionary = sdef.get("effects", {})
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u == self:
			continue
		if not u.has_method("get_faction") or u.get_faction() != faction:
			continue
		if global_position.distance_to(u.global_position) > aura_radius:
			continue
		# 恢复体力（如果有 stamina 属性）
		if "stamina" in u:
			u.stamina = min(100.0, u.stamina + effects.get("stamina_recover", 2.0))
		# 恢复士气
		if "morale" in u:
			u.morale = min(100.0, u.morale + effects.get("morale_recover", 0.5))
	# 消耗粮草
	food = max(0.0, food - effects.get("food_supply", 1.0))

func take_damage(amount: float, attacker: Node) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0:
		_destroy(attacker)

func _destroy(killer: Node) -> void:
	_dead = true
	# 断粮效果：周围友军士气大降
	for u in GameManager.all_units:
		if is_instance_valid(u) and u.has_method("get_faction") and u.get_faction() == faction:
			if global_position.distance_to(u.global_position) < aura_radius * 2:
				if "morale" in u:
					u.morale = max(0.0, u.morale - 15.0)
	if killer and killer.has_method("get_faction"):
		EventBus.float_text.emit("辎重被劫! 断粮!", global_position + Vector3(0, 3, 0), Color.RED)
		# 劫粮方获得部分粮草
		var kf: String = killer.get_faction()
		if kf in GameManager.factions:
			GameManager.factions[kf].resources["food"] += food * 0.3
	GameManager.all_units.erase(self)
	queue_free()