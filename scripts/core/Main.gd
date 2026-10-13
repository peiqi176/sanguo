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
	_spawn_water()
	_spawn_decorations()
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
	# 傲世三国风格的土褐色调草地
	mat.albedo_color = Color(0.42, 0.48, 0.28)
	mat.roughness = 0.95
	_terrain.material_override = mat
	_terrain.rotation.x = deg_to_rad(-90)
	add_child(_terrain)
	# 光照
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	light.light_energy = 1.8
	light.light_color = Color(1.0, 0.96, 0.88)
	light.shadow_enabled = true
	light.light_angular_distance = 0.5
	light.shadow_blur = 1.5
	light.shadow_normal_bias = 0.3
	light.shadow_bias = 0.05
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(light)
	# 环境光
	var env: WorldEnvironment = WorldEnvironment.new()
	var env_resource: Environment = Environment.new()
	env_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_resource.ambient_light_color = Color(0.75, 0.78, 0.65)
	env_resource.ambient_light_energy = 1.0
	env_resource.background_mode = Environment.BG_COLOR
	env_resource.background_color = Color(0.50, 0.65, 0.82)
	# 雾效
	env_resource.fog_enabled = true
	env_resource.fog_light_color = Color(0.72, 0.76, 0.72)
	env_resource.fog_density = 0.006
	env_resource.fog_height = 0.0
	env_resource.fog_height_density = 0.01
	# 辉光
	env_resource.glow_enabled = true
	env_resource.glow_intensity = 0.6
	env_resource.glow_bloom = 0.3
	env_resource.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# 色调映射
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

func _spawn_water() -> void:
	"""生成河流和湖泊"""
	var water_script: GDScript = load("res://scripts/world/Water.gd")
	if not water_script:
		return
	# 横向河流
	var river = water_script.new()
	river.mesh = river.mesh  # placeholder
	add_child(river)
	river.global_position = Vector3(40, 0.1, 42)
	river.scale = Vector3(4.2, 1, 0.8)
	# 湖泊
	var lake = water_script.new()
	add_child(lake)
	lake.global_position = Vector3(15, 0.1, 65)
	lake.scale = Vector3(1.8, 1, 1.5)

func _spawn_decorations() -> void:
	"""生成树木、佛像、岩石、灯笼等装饰"""
	var tree_script: GDScript = load("res://scripts/world/Tree.gd")
	var deco_script: GDScript = load("res://scripts/world/Decoration.gd")
	if not tree_script or not deco_script:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	# 散布树木（约80棵）
	for i in range(80):
		var gx: int = rng.randi_range(1, 82)
		var gz: int = rng.randi_range(1, 82)
		# 避开水域
		if abs(gz - 42) < 6 and gx > 10 and gx < 74:
			continue
		if abs(gx - 15) < 8 and abs(gz - 65) < 8:
			continue
		if not grid.is_placeable(Vector2i(gx, gz), Vector2i(1, 1)):
			continue
		var tree = tree_script.new()
		var t: int = rng.randi_range(0, 3)
		tree.tree_type = t
		add_child(tree)
		tree.global_position = grid.grid_to_world(Vector2i(gx, gz))
		tree.scale *= randf_range(0.8, 1.3)
	# 佛像（3座）
	var buddha_positions: Array = [Vector2i(30, 30), Vector2i(60, 60), Vector2i(20, 70)]
	for bp in buddha_positions:
		if grid.is_placeable(bp, Vector2i(2, 2)):
			var b = deco_script.new()
			b.deco_type = 0  # BUDDHA
			add_child(b)
			b.global_position = grid.grid_to_world(bp)
	# 岩石散布
	for i in range(30):
		var rx: int = rng.randi_range(1, 82)
		var rz: int = rng.randi_range(1, 82)
		if not grid.is_placeable(Vector2i(rx, rz), Vector2i(1, 1)):
			continue
		var rock = deco_script.new()
		rock.deco_type = 1  # ROCK
		add_child(rock)
		rock.global_position = grid.grid_to_world(Vector2i(rx, rz))
	# 灯笼（村庄附近）
	var lantern_positions: Array = [Vector2i(39, 11), Vector2i(41, 11), Vector2i(9, 39), Vector2i(11, 39)]
	for lp in lantern_positions:
		var lantern = deco_script.new()
		lantern.deco_type = 2  # LANTERN
		add_child(lantern)
		lantern.global_position = grid.grid_to_world(lp)

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
	# 右键下达指令 (Shift+右键 = 加入指令队列)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _build_mode != "":
			_cancel_build_mode()
			return
		var queue: bool = event.shift_pressed
		var world_pos: Vector3 = _screen_to_world(event.position)
		if world_pos != Vector3.INF:
			var target: Node = _get_entity_at(world_pos)
			# 农夫右键资源节点 -> 采集
			if target and target is ResourceNode:
				for u in selection.get_selected_units():
					if u.unit_id == "peasant":
						u.command_gather(target, queue)
				EventBus.float_text.emit("采集" + (" (排队)" if queue else ""), world_pos + Vector3(0, 2, 0), Color.YELLOW)
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
				selection.issue_command(target.global_position, null, queue)
			# 右键敌方单位 -> 攻击
			elif target and target.has_method("get_faction") and target.get_faction() != GameManager.player_faction:
				selection.issue_command(world_pos, target, queue)
			else:
				selection.issue_command(world_pos, null, queue)
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

	# 编队快捷键: Ctrl+1~9 保存编队, 1~9 选择编队, 双击数字居中视角
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		var group_idx: int = -1
		if key >= KEY_1 and key <= KEY_9:
			group_idx = key - KEY_1
		elif key == KEY_0:
			group_idx = 9
		if group_idx >= 0:
			var ctrl: bool = event.ctrl_pressed
			if ctrl:
				selection.save_group(group_idx)
			else:
				# 双击检测
				var now: float = Time.get_ticks_msec() / 1000.0
				var double_tap: bool = (group_idx == selection._last_group_key and (now - selection._last_group_time) < 0.4)
				selection._last_group_key = group_idx
				selection._last_group_time = now
				selection.select_group(group_idx, double_tap)
			get_viewport().set_input_as_handled()

	# S键停止 (清空指令队列)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S:
		for u in selection.get_selected_units():
			u.command_queue.clear()
			u.state = u.State.IDLE
			u.attack_target = null
			u.gather_target = null
			u.repair_target = null
		EventBus.float_text.emit("停止", Vector3.ZERO, Color.WHITE)

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







