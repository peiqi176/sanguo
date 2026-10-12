extends Node3D
## Main — 主场景
## 初始化游戏世界：地形、网格、相机、初始建筑/单位、AI

@onready var camera_controller: Node3D = $CameraController
@onready var grid: GridManager = $GridManager
@onready var pathfinder: Pathfinder = $Pathfinder
@onready var selection: SelectionManager = $SelectionManager
@onready var ui: CanvasLayer = $GameUI

var _build_mode: String = ""
var _build_ghost: MeshInstance3D = null
var _terrain: MeshInstance3D = null

func _ready() -> void:
	GameManager.grid = grid
	GameManager.pathfinder = pathfinder
	GameManager.map_size = grid.map_size
	_setup_terrain()
	_spawn_initial_forces()
	_spawn_resource_nodes()
	_spawn_villages()
	_spawn_wild_horses()
	print("[Main] 游戏世界初始化完成")

func _spawn_ai() -> void:
	for faction_id in GameManager.factions.keys():
		if faction_id != GameManager.player_faction:
			var ai_script: GDScript = load("res://scripts/ai/AIController.gd")
			if ai_script:
				var ai: Node = ai_script.new()
				ai.faction = faction_id
				ai.name = "AI_" + faction_id
				add_child(ai)

func _setup_terrain() -> void:
	_terrain = MeshInstance3D.new()
	var plane_mesh: PlaneMesh = PlaneMesh.new()
	plane_mesh.size = Vector2(168, 168)
	plane_mesh.subdivide_width = 42
	plane_mesh.subdivide_depth = 42
	_terrain.mesh = plane_mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.55, 0.30)
	mat.roughness = 0.8
	_terrain.material_override = mat
	_terrain.rotation.x = deg_to_rad(-90)
	add_child(_terrain)
	# 光照
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-45), deg_to_rad(30), 0)
	light.light_energy = 1.5
	add_child(light)
	# 环境光
	var env: WorldEnvironment = WorldEnvironment.new()
	var env_resource: Environment = Environment.new()
	env_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_resource.ambient_light_color = Color(0.8, 0.8, 0.7)
	env_resource.ambient_light_energy = 0.8
	env_resource.background_mode = Environment.BG_COLOR
	env_resource.background_color = Color(0.3, 0.35, 0.25)
	env.environment = env_resource
	add_child(env)

func _spawn_initial_forces() -> void:
	_spawn_ai()
	# 玩家（蜀）初始基地 — 左下
	_spawn_base("shu", Vector2i(10, 10))
	# AI（魏）初始基地 — 右上
	_spawn_base("wei", Vector2i(70, 70))
	# AI（吴）— 右上偏中
	_spawn_base("wu", Vector2i(60, 20))

func _spawn_base(faction_id: String, pos: Vector2i) -> void:
	# 官府
	_spawn_building("government", faction_id, pos)
	# 牌楼（仓库+招农）
	_spawn_building("paifang", faction_id, pos + Vector2i(3, 0))
	# 民居
	_spawn_building("house", faction_id, pos + Vector2i(-3, 0))
	# 农田
	_spawn_building("farm", faction_id, pos + Vector2i(0, 3))
	# 刀兵营
	_spawn_building("barracks_sword", faction_id, pos + Vector2i(4, -2))
	# 翰林院
	_spawn_building("hanlinyuan", faction_id, pos + Vector2i(-2, -3))
	# 初始农夫
	for i in range(4):
		_spawn_unit("peasant", faction_id, grid.grid_to_world(pos + Vector2i(0, 1 + i)))
	# 初始士兵
	_spawn_unit("sword", faction_id, grid.grid_to_world(pos + Vector2i(2, 2)))
	_spawn_unit("sword", faction_id, grid.grid_to_world(pos + Vector2i(3, 2)))
	_spawn_unit("archer", faction_id, grid.grid_to_world(pos + Vector2i(2, 3)))
	_spawn_general(faction_id, grid.grid_to_world(pos + Vector2i(1, 4)))

func _spawn_building(building_id: String, faction_id: String, grid_pos: Vector2i) -> void:
	var bdef: Dictionary = DataLoader.get_building_def(building_id)
	var size: Vector2i = Vector2i(bdef.get("size", [2,2])[0], bdef.get("size", [2,2])[1])
	if not grid.is_placeable(grid_pos, size):
		return
	grid.set_occupied(grid_pos, size, 1)
	var scene: PackedScene = load("res://scenes/Building.tscn")
	if scene:
		var b: Building = scene.instantiate()
		b.building_id = building_id
		b.faction = faction_id
		b.grid_pos = grid_pos
		add_child(b)
		b.global_position = grid.grid_to_world(grid_pos)

func _spawn_unit(unit_id: String, faction_id: String, pos: Vector3) -> void:
	var scene: PackedScene = load("res://scenes/Unit.tscn")
	if scene:
		var u: Unit = scene.instantiate()
		u.unit_id = unit_id
		u.faction = faction_id
		add_child(u)
		u.global_position = pos
		GameManager.change_population(faction_id, DataLoader.get_unit_def(unit_id).get("pop_cost", 1))

func _spawn_general(faction_id: String, pos: Vector3) -> void:
	var general_ids: Dictionary = { "wei": "cao_cao", "shu": "liubei", "wu": "sunquan" }
	if not general_ids.has(faction_id):
		return
	var scene: PackedScene = load("res://scenes/General.tscn")
	if scene:
		var g: General = scene.instantiate()
		g.general_id = general_ids[faction_id]
		g.faction = faction_id
		g.unit_id = "general_" + general_ids[faction_id]
		add_child(g)
		g.global_position = pos

func _spawn_resource_nodes() -> void:
	# 散布资源点
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(20):
		var pos: Vector2i = Vector2i(rng.randi_range(2, 80), rng.randi_range(2, 80))
		if not grid.is_placeable(pos, Vector2i(1,1)):
			continue
		var res_type: String = "wood" if i % 3 != 1 else "stone"
		if i % 5 == 0:
			res_type = "food"
		_spawn_resource_node(res_type, pos)

func _spawn_resource_node(res_type: String, grid_pos: Vector2i) -> void:
	var scene: PackedScene = load("res://scenes/ResourceNode.tscn")
	if scene:
		var node: ResourceNode = scene.instantiate()
		node.resource_type = res_type
		node.amount = 800.0 + float(randi_range(0, 400))
		add_child(node)
		node.global_position = grid.grid_to_world(grid_pos)


func _spawn_villages() -> void:
	# 散布中立村庄（6个）
	var rng := RandomNumberGenerator.new()
	rng.seed = 99999
	var positions: Array = [
		Vector2i(40, 10), Vector2i(10, 40), Vector2i(70, 40),
		Vector2i(40, 70), Vector2i(25, 25), Vector2i(55, 55)
	]
	for i in range(positions.size()):
		var pos: Vector2i = positions[i]
		if not grid.is_placeable(pos, Vector2i(2, 2)):
			pos = Vector2i(rng.randi_range(5, 78), rng.randi_range(5, 78))
		_spawn_village("village_%d" % i, pos)

func _spawn_village(vid: String, grid_pos: Vector2i) -> void:
	var scene: PackedScene = load("res://scenes/Village.tscn")
	if scene:
		var v: Village = scene.instantiate()
		v.village_id = vid
		add_child(v)
		v.global_position = grid.grid_to_world(grid_pos)

func _spawn_wild_horses() -> void:
	# 散布野马（8匹，含名马）
	var horse_types: Array = ["white", "white", "white", "red", "red", "chitu", "dilu", "white"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77777
	for i in range(horse_types.size()):
		var pos: Vector2i = Vector2i(rng.randi_range(5, 78), rng.randi_range(5, 78))
		_spawn_horse("horse_%d" % i, horse_types[i], pos)

func _spawn_horse(hid: String, htype: String, grid_pos: Vector2i) -> void:
	var scene: PackedScene = load("res://scenes/WildHorse.tscn")
	if scene:
		var h: WildHorse = scene.instantiate()
		h.horse_id = hid
		h.horse_type = htype
		add_child(h)
		h.global_position = grid.grid_to_world(grid_pos)
func _process(_delta: float) -> void:
	if _build_mode != "":
		_update_build_ghost()

func _unhandled_input(event: InputEvent) -> void:
	# 右键下达指令
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _build_mode != "":
			_cancel_build_mode()
			return
		var world_pos: Vector3 = _screen_to_world(event.position)
		if world_pos != Vector3.INF:
			var target: Node = _get_entity_at(world_pos)
			# 农夫右键资源节点 -> 采集
			if target and target is ResourceNode:
				for u in selection.get_selected_units():
					if u.unit_id == "peasant":
						u.command_gather(target)
				EventBus.float_text.emit("采集", world_pos + Vector3(0, 2, 0), Color.YELLOW)
			# 右键受损友方建筑 + 农夫 -> 修理
			elif target and target is Building and target.get_faction() == GameManager.player_faction and target.is_damaged():
				for u in selection.get_selected_units():
					if u.unit_id == 'peasant':
						u.command_repair(target)
				EventBus.float_text.emit('修理', world_pos + Vector3(0, 2, 0), Color.YELLOW)
			# 右键可驻军友方建筑 -> 入驻
			elif target and target is Building and target.get_faction() == GameManager.player_faction and target.can_garrison:
				for u in selection.get_selected_units():
					u.command_garrison(target)
			# 右键村庄/野马 -> 移动占领/捕获
			elif target and (target is Village or target is WildHorse):
				selection.issue_command(target.global_position)
			# 右键敌方单位 -> 攻击
			elif target and target.has_method("get_faction") and target.get_faction() != GameManager.player_faction:
				selection.issue_command(world_pos, target)
			else:
				selection.issue_command(world_pos)
		get_viewport().set_input_as_handled()
	
	# 建造模式下左键放置
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _build_mode != "":
		var world_pos: Vector3 = _screen_to_world(event.position)
		if world_pos != Vector3.INF:
			_place_building(_build_mode, world_pos)
		get_viewport().set_input_as_handled()
	
	# ESC 取消
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _build_mode != "":
			_cancel_build_mode()

func start_build_mode(building_id: String) -> void:
	_build_mode = building_id
	var bdef: Dictionary = DataLoader.get_building_def(building_id)
	_build_ghost = MeshInstance3D.new()
	var size: Vector2i = Vector2i(bdef.get("size", [2,2])[0], bdef.get("size", [2,2])[1])
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(float(size.x) * 2.0, 1.0, float(size.y) * 2.0)
	_build_ghost.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_build_ghost.material_override = mat
	add_child(_build_ghost)

func _update_build_ghost() -> void:
	if _build_ghost == null:
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var world_pos: Vector3 = _screen_to_world(mouse_pos)
	if world_pos != Vector3.INF:
		var grid_pos: Vector2i = grid.world_to_grid(world_pos)
		var bdef: Dictionary = DataLoader.get_building_def(_build_mode)
		var size: Vector2i = Vector2i(bdef.get("size", [2,2])[0], bdef.get("size", [2,2])[1])
		var placeable: bool = grid.is_placeable(grid_pos, size) and GameManager.can_afford(GameManager.player_faction, bdef.get("cost", {}))
		_build_ghost.global_position = grid.grid_to_world(grid_pos)
		var mat: StandardMaterial3D = _build_ghost.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.2, 0.8, 0.2, 0.4) if placeable else Color(0.8, 0.2, 0.2, 0.4)

func _place_building(building_id: String, world_pos: Vector3) -> void:
	var grid_pos: Vector2i = grid.world_to_grid(world_pos)
	var bdef: Dictionary = DataLoader.get_building_def(building_id)
	var size: Vector2i = Vector2i(bdef.get("size", [2,2])[0], bdef.get("size", [2,2])[1])
	if not grid.is_placeable(grid_pos, size):
		EventBus.float_text.emit("无法放置", world_pos + Vector3(0, 2, 0), Color.RED)
		return
	if not GameManager.spend_resources(GameManager.player_faction, bdef.get("cost", {})):
		EventBus.float_text.emit("资源不足", world_pos + Vector3(0, 2, 0), Color.RED)
		return
	_spawn_building(building_id, GameManager.player_faction, grid_pos)
	EventBus.float_text.emit("建造中: %s" % bdef.get("name", building_id), world_pos + Vector3(0, 2, 0), Color.GREEN)
	_cancel_build_mode()

func _cancel_build_mode() -> void:
	_build_mode = ""
	if _build_ghost:
		_build_ghost.queue_free()
		_build_ghost = null

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	var camera: Camera3D = camera_controller.get_node("Camera3D")
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.001:
		return Vector3.INF
	var t: float = -from.y / dir.y
	if t < 0:
		return Vector3.INF
	return from + dir * t

func _get_entity_at(pos: Vector3) -> Node:
	var best: Node = null
	var best_dist: float = 1.5
	for u in GameManager.all_units:
		if u.global_position.distance_to(pos) < best_dist:
			best_dist = u.global_position.distance_to(pos)
			best = u
	for b in GameManager.all_buildings:
		if b.global_position.distance_to(pos) < best_dist + 1.0:
			best = b
			break
	# 资源节点
	for rn in GameManager.resource_nodes:
		if is_instance_valid(rn) and rn.global_position.distance_to(pos) < best_dist + 0.5:
			best = rn
			break
	# 村庄
	for v in GameManager.villages:
		if is_instance_valid(v) and v.global_position.distance_to(pos) < best_dist + 1.5:
			best = v
			break
	# 野马
	for h in GameManager.wild_horses:
		if is_instance_valid(h) and h.global_position.distance_to(pos) < best_dist + 0.5:
			best = h
			break
	return best







