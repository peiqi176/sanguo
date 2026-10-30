extends CharacterBody3D
class_name TransportTeam
## TransportTeam — 村庄资源运输队
## 由村庄民夫押运，从村庄运往城池/营帐/其他村，可被劫掉50%

@export var team_id: String = "transport_0"
var faction: String = ""
var hp: float = 100.0
var max_hp: float = 100.0
var move_speed: float = 1.5

# 运输资源
var cargo: Dictionary = {}  # { "bun": 50, "wine": 30, ... }
var cargo_total: float = 0.0

# 起点和终点
var source_village = null
var target_position: Vector3 = Vector3.ZERO
var target_type: String = ""  # "city" / "camp" / "village"
var target_ref: Node = null  # 目标引用

# 押运民夫
var peasant_count: int = 1
var max_peasants: int = 5
var capacity_per_peasant: float = 50.0
var ambush_loss_ratio: float = 0.5

# 状态
enum State { IDLE, MOVING, DELIVERING, RETURNING }
var state: int = State.IDLE
var _dead: bool = false

func _ready() -> void:
	var conf: Dictionary = DataLoader.logistics.get("transport", {})
	move_speed = float(conf.get("move_speed", move_speed))
	max_peasants = int(conf.get("max_peasants", max_peasants))
	capacity_per_peasant = float(conf.get("capacity_per_peasant", capacity_per_peasant))
	ambush_loss_ratio = float(conf.get("ambush_loss_ratio", ambush_loss_ratio))
	GameManager.all_units.append(self)
	_create_visual()

func _exit_tree() -> void:
	# 在途被外部清场（读档/重开/场景卸载）时把货物退回原势力，避免资源凭空消失。
	# 正常交付（cargo 已清空）与被劫（_dead=true，货已归劫方）不触发。
	if _dead or cargo_total <= 0.0 or faction == "":
		return
	if faction in GameManager.factions:
		for k in cargo.keys():
			GameManager.add_resource(faction, k, float(cargo[k]))
		print("[Transport] %s 在途销毁，货物退回：%s" % [team_id, str(cargo)])
	cargo.clear()
	cargo_total = 0.0

func _create_visual() -> void:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	# 使用辎重车贴图
	var adef: Dictionary = DataLoader.get_asset_def("supply_cart", "supply_cart")
	if not adef.is_empty():
		var tex: Texture2D = DataLoader.get_sprite_texture("supply_cart", "supply_cart")
		if tex:
			sprite.texture = tex
		var s: float = float(adef.get("scale", 1.2))
		sprite.scale = Vector3(s, s, s)
		sprite.position.y = DataLoader.get_sprite_anchor_y("supply_cart", "supply_cart", s)
	add_child(sprite)

func get_faction() -> String:
	return faction

func max_cargo_for(peasants: int) -> float:
	return float(clampi(peasants, 1, max_peasants)) * capacity_per_peasant

func setup_transport(from_village, to_pos: Vector3, resources: Dictionary, peasants: int, fid: String = "") -> bool:
	"""设置运输队参数。返回 false 表示超载（调用方负责退款）。"""
	var conf: Dictionary = DataLoader.logistics.get("transport", {})
	max_peasants = int(conf.get("max_peasants", max_peasants))
	capacity_per_peasant = float(conf.get("capacity_per_peasant", capacity_per_peasant))
	source_village = from_village
	if fid != "":
		faction = fid
	elif from_village != null and "village_owner" in from_village:
		faction = str(from_village.village_owner)
	target_position = to_pos
	cargo = resources.duplicate()
	peasant_count = clampi(peasants, 1, max_peasants)
	cargo_total = 0.0
	for k in cargo.keys():
		cargo_total += float(cargo[k])
	if cargo_total > max_cargo_for(peasant_count):
		EventBus.float_text.emit("超载：%d 民夫最多运 %d" % [peasant_count, int(max_cargo_for(peasant_count))], global_position + Vector3(0, 3, 0), Color.RED)
		return false
	state = State.MOVING
	return true

func _process(delta: float) -> void:
	if GameManager.paused or GameManager.game_over or _dead:
		return
	match state:
		State.MOVING:
			_move_toward(target_position, delta)
			if global_position.distance_to(target_position) < 2.0:
				_deliver_cargo()
		State.RETURNING:
			if source_village != null and is_instance_valid(source_village):
				_move_toward(source_village.global_position, delta)
				if global_position.distance_to(source_village.global_position) < 2.0:
					_finish_transport()

func _move_toward(target: Vector3, delta: float) -> void:
	var dir: Vector3 = target - global_position
	dir.y = 0
	if dir.length() < 0.5:
		return
	dir = dir.normalized()
	velocity = dir * move_speed
	move_and_slide()
	_snap_to_ground(delta)

## 贴地（同上：运输队原来也不贴地）
func _snap_to_ground(delta: float) -> void:
	var gh: float = Terrain.get_height(global_position.x, global_position.z)
	var dy: float = gh - global_position.y
	if absf(dy) > 1.2:
		global_position.y = gh
	else:
		global_position.y = lerpf(global_position.y, gh, clampf(delta * 20.0, 0.0, 1.0))

func _deliver_cargo() -> void:
	"""交付货物"""
	if faction in GameManager.factions:
		for k in cargo.keys():
			# 走 add_resource 以便标脏 → 顶栏资源栏当帧刷新
			GameManager.add_resource(faction, k, float(cargo[k]))
		EventBus.float_text.emit("📦 运输到达", global_position + Vector3(0, 3, 0), Color.GREEN)
		print("[Transport] %s 运输到达: %s" % [team_id, str(cargo)])
	cargo.clear()
	cargo_total = 0.0
	state = State.RETURNING

func _finish_transport() -> void:
	"""完成运输，民夫返回村庄"""
	if source_village != null and is_instance_valid(source_village):
		source_village.peasant_count = min(source_village.max_peasants, source_village.peasant_count + peasant_count)
	GameManager.all_units.erase(self)
	queue_free()

func take_damage(amount: float, attacker: Node) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0:
		_destroy(attacker)

func _destroy(killer: Node) -> void:
	_dead = true
	# 被劫：损失50%货物，劫方获得50%
	if killer and killer.has_method("get_faction"):
		var kf: String = killer.get_faction()
		if kf in GameManager.factions:
			var looted: Dictionary = {}
			for k in cargo.keys():
				var amt: float = float(cargo[k]) * ambush_loss_ratio
				looted[k] = amt
				# 走 add_resource 以便标脏 → 顶栏资源栏当帧刷新
				GameManager.add_resource(kf, k, amt)
			EventBus.float_text.emit("⚔️ 运输队被劫！", global_position + Vector3(0, 3, 0), Color.RED)
			print("[Transport] %s 被劫，损失%d%%: %s" % [team_id, int(ambush_loss_ratio * 100.0), str(looted)])
	# 民夫死亡
	if source_village != null and is_instance_valid(source_village):
		for i in range(peasant_count):
			source_village.on_peasant_died()
	GameManager.all_units.erase(self)
	queue_free()
