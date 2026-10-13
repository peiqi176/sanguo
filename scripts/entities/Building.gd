extends StaticBody3D
class_name Building
## Building — 建筑基类
## 包含：产出、训练队列、人口提供、建造/升级、集结点

signal built(building)
signal destroyed(building)

@export var building_id: String = "house"
@export var faction: String = "shu"

var def: Dictionary = {}
var hp: float = 250.0
var max_hp: float = 250.0
var grid_pos: Vector2i = Vector2i.ZERO
var size: Vector2i = Vector2i(2, 2)
var is_selected: bool = false
var build_progress: float = 1.0  # 0-1, 1=完成
var training_queue: Array = []  # [{unit_id, time_left}]
var rally_point: Vector3 = Vector3.ZERO
var workers: Array = []
var production_accum: float = 0.0
var garrisoned_units: Array = []  # 驻扎在建筑内的单位
var can_garrison: bool = false
var garrison_cap: int = 0

# 组件
var _selection_ring: MeshInstance3D = null
var _hp_bar: Node = null
var _sprite: Sprite3D = null

func _ready() -> void:
	def = DataLoader.get_building_def(building_id)
	if not def.is_empty():
		_init_from_def()
	_create_sprite()
	_create_selection_ring()
	GameManager.register_building(self)
	if building_id == "house":
		GameManager.add_population_cap(faction, def.get("pop_provide", 0))
	built.emit(self)

func _init_from_def() -> void:
	max_hp = def.get("hp", 250)
	hp = max_hp
	size = Vector2i(def.get("size", [2,2])[0], def.get("size", [2,2])[1])
	can_garrison = def.get("can_garrison", false)
	garrison_cap = def.get("garrison_cap", 0)

func _create_sprite() -> void:
	# 3D底座平台（增加立体感）
	var platform: MeshInstance3D = MeshInstance3D.new()
	var plat_mesh: BoxMesh = BoxMesh.new()
	var sw: float = float(size.x) * 2.0 + 0.3
	var sd: float = float(size.y) * 2.0 + 0.3
	plat_mesh.size = Vector3(sw, 0.3, sd)
	platform.mesh = plat_mesh
	var plat_mat: StandardMaterial3D = StandardMaterial3D.new()
	var cat: String = def.get("category", "civilian")
	if cat == "military":
		plat_mat.albedo_color = Color(0.45, 0.40, 0.35)
	elif cat == "governance":
		plat_mat.albedo_color = Color(0.55, 0.48, 0.35)
	elif cat == "resource":
		plat_mat.albedo_color = Color(0.40, 0.35, 0.25)
	else:
		plat_mat.albedo_color = Color(0.42, 0.36, 0.28)
	plat_mat.roughness = 0.9
	platform.material_override = plat_mat
	platform.position.y = 0.15
	add_child(platform)
	# 台阶边缘
	var edge: MeshInstance3D = MeshInstance3D.new()
	var edge_mesh: BoxMesh = BoxMesh.new()
	edge_mesh.size = Vector3(sw + 0.15, 0.1, sd + 0.15)
	edge.mesh = edge_mesh
	var edge_mat: StandardMaterial3D = StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.30, 0.26, 0.20)
	edge_mat.roughness = 0.95
	edge.material_override = edge_mat
	edge.position.y = 0.05
	add_child(edge)

	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.shaded = false
	_sprite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var adef: Dictionary = DataLoader.get_asset_def("buildings", building_id)
	if not adef.is_empty():
		var tex: Texture2D = DataLoader.get_sprite_texture("buildings", building_id)
		if tex:
			_sprite.texture = tex
		var s: float = float(adef.get("scale", 1.5))
		_sprite.scale = Vector3(s, s, s)
		_sprite.position.y = float(adef.get("offset_y", 1.0)) + 0.3
	add_child(_sprite)

func _create_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(float(size.x) * 2.0 + 0.4, 0.1, float(size.y) * 2.0 + 0.4)
	_selection_ring.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color.GREEN
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 0.2)
	_selection_ring.material_override = mat
	_selection_ring.visible = false
	add_child(_selection_ring)
	_selection_ring.position.y = -0.45

func set_selected(selected: bool) -> void:
	is_selected = selected
	if _selection_ring:
		_selection_ring.visible = selected

func get_faction() -> String:
	return faction

func get_production() -> Dictionary:
	if build_progress < 1.0:
		return {}
	var produces: Dictionary = def.get("produces", {})
	var result: Dictionary = {}
	for res in produces.keys():
		result[res] = produces[res]
	return result

func train_unit(unit_id: String) -> bool:
	var unit_def: Dictionary = DataLoader.get_unit_def(unit_id)
	if unit_def.is_empty():
		if unit_id == "supply_cart":
			unit_def = DataLoader.logistics.get("supply_cart", {})
			unit_def["pop_cost"] = 0
			unit_def["train_time"] = unit_def.get("build_time", 25)
		else:
			return false
		return false
	var cost: Dictionary = unit_def.get("cost", {})
	if not GameManager.can_afford(faction, cost):
		EventBus.float_text.emit("资源不足", global_position + Vector3(0, 3, 0), Color.RED)
		return false
	if not GameManager.can_train(faction, unit_def.get("pop_cost", 1)):
		EventBus.float_text.emit("人口不足", global_position + Vector3(0, 3, 0), Color.RED)
		return false
	GameManager.spend_resources(faction, cost)
	training_queue.append({ "unit_id": unit_id, "time_left": unit_def.get("train_time", 20) })
	return true

func set_rally_point(pos: Vector3) -> void:
	rally_point = pos
	EventBus.rally_point_set.emit(self, pos)

func _process(delta: float) -> void:
	if build_progress < 1.0:
		build_progress = min(1.0, build_progress + delta * 0.1)
		return
	# 训练队列
	if training_queue.size() > 0:
		var item: Dictionary = training_queue[0]
		item["time_left"] = float(item["time_left"]) - delta
		if item["time_left"] <= 0:
			_spawn_unit(item["unit_id"])
			training_queue.pop_front()

func _spawn_unit(unit_id: String) -> void:
	if unit_id == "supply_cart":
		var cart_scene: PackedScene = load("res://scenes/SupplyCart.tscn")
		if cart_scene:
			var cart: SupplyCart = cart_scene.instantiate()
			cart.cart_id = "cart_" + str(randi())
			cart.faction = faction
			var spawn_pos: Vector3 = global_position + Vector3(size.x, 0, 0)
			cart.global_position = spawn_pos
			get_tree().root.add_child(cart)
			GameManager.factions[faction].units.append(cart)
		return
	var unit_scene: PackedScene = load("res://scenes/Unit.tscn")
	if unit_scene:
		var unit: Unit = unit_scene.instantiate()
		unit.unit_id = unit_id
		unit.faction = faction
		# 在建筑旁边生成
		var spawn_pos: Vector3 = global_position + Vector3(size.x, 0, 0)
		unit.global_position = spawn_pos
		get_tree().root.add_child(unit)
		GameManager.change_population(faction, DataLoader.get_unit_def(unit_id).get("pop_cost", 1))
		EventBus.unit_trained.emit(faction, unit_id)
		if rally_point != Vector3.ZERO:
			unit.command_move(rally_point)

func repair(amount: float) -> void:
	"""修理建筑，恢复HP，消耗木材和石料"""
	if hp >= max_hp:
		return
	# 修理消耗：每点HP消耗0.5木材+0.3石料
	var wood_cost: float = amount * 0.5
	var stone_cost: float = amount * 0.3
	if not GameManager.can_afford(faction, {"wood": wood_cost, "stone": stone_cost}):
		return
	GameManager.spend_resources(faction, {"wood": wood_cost, "stone": stone_cost})
	hp = min(max_hp, hp + amount)

func is_damaged() -> bool:
	return hp < max_hp

func garrison(unit: Unit) -> bool:
	"""单位入驻建筑"""
	if not can_garrison:
		return false
	if garrisoned_units.size() >= garrison_cap:
		return false
	if unit in garrisoned_units:
		return false
	garrisoned_units.append(unit)
	unit.visible = false
	if unit.has_method("set_physics_process"):
		unit.set_physics_process(false)
	EventBus.float_text.emit("入驻", global_position + Vector3(0, 3, 0), Color.CYAN)
	return true

func unload_unit(unit: Unit) -> void:
	"""让一个单位离开建筑"""
	if unit in garrisoned_units:
		garrisoned_units.erase(unit)
		unit.visible = true
		if unit.has_method("set_physics_process"):
			unit.set_physics_process(true)
		unit.global_position = global_position + Vector3(size.x, 0, 0)
		unit.state = Unit.State.IDLE

func unload_all() -> void:
	"""所有驻扎单位离开"""
	for u in garrisoned_units.duplicate():
		unload_unit(u)

func get_garrison_count() -> int:
	return garrisoned_units.size()

func take_damage(amount: float, attacker: Node = null) -> void:
	hp -= amount
	if hp <= 0:
		_destroyed()

func _destroyed() -> void:
	unload_all()
	GameManager.unregister_building(self)
	GameManager.grid.clear_occupied(grid_pos, size)
	if building_id == "house":
		GameManager.add_population_cap(faction, -def.get("pop_provide", 0))
	EventBus.building_destroyed.emit(self)
	destroyed.emit(self)
	GameManager.check_victory()
	queue_free()

