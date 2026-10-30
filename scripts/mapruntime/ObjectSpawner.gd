extends RefCounted
## ObjectSpawner —— 把 doc.objects[] 里的一条数据变成场景里的真实节点
##
## 核心设计：**接受任意 Node3D 作为容器**
##   游戏里传 Main 的引用，编辑器里传 MapEditor 的引用，
##   两边跑的是同一份创建代码 —— 这样"编辑器里看到的 = 游戏里跑出来的"，
##   不会出现"编辑器放的是占位盒、游戏里是另一样东西"。
##
## 同理，grid 也由调用方传：Main 用 $GridManager，编辑器用自己的 EditorGrid。
## 绝不从 GameManager.grid 取 —— 编辑器不该污染游戏的全局状态。
##
## 每个 spawn_* 都返回 Node（失败返回 null），调用方据 null 判断是否要回滚占位。

## 场景路径集中在这里，资源搬家只改这一处
const BUILDING_SCENE: String = "res://scenes/Building.tscn"
const UNIT_SCENE: String = "res://scenes/Unit.tscn"
const RESOURCE_SCENE: String = "res://scenes/ResourceNode.tscn"
const VILLAGE_SCENE: String = "res://scenes/Village.tscn"
const HORSE_SCENE: String = "res://scenes/WildHorse.tscn"
const TREE_SCRIPT: String = "res://scripts/world/Tree.gd"
const DECO_SCRIPT: String = "res://scripts/world/Decoration.gd"

## 装饰 id → 创建方式。id 就是存盘时写进 objects[] 的值。
##   tree_0..tree_3 → Tree.gd，tree_type=0..3
##   rock / buddha / lantern → Decoration.gd，deco_type 分别 1 / 0 / 2
const DECO_TYPES: Dictionary = {
	"buddha": 0,
	"rock": 1,
	"lantern": 2,
}

# ---------------------------------------------------------------- 统一入口

## obj 是 doc.objects[] 里的一条。返回创建的节点（失败 null）。
static func spawn(host: Node3D, grid, obj: Dictionary) -> Node:
	if host == null or typeof(obj) != TYPE_DICTIONARY:
		return null
	var kind: String = str(obj.get("kind", ""))
	var id: String = str(obj.get("id", ""))
	var gp: Vector2i = _obj_grid(obj)

	match kind:
		"building":
			return spawn_building(host, grid, id, str(obj.get("owner", "shu")), gp, int(obj.get("rot", 0)))
		"unit":
			return spawn_unit(host, grid, id, str(obj.get("owner", "shu")), gp)
		"resource":
			return spawn_resource(host, grid, id, gp, int(obj.get("amount", 800)), bool(obj.get("is_mine", false)))
		"village":
			return spawn_village(host, grid, id, gp)
		"horse":
			return spawn_horse(host, grid, id, gp)
		"deco":
			return spawn_deco(host, grid, id, _obj_pos(obj), float(obj.get("scale", 1.0)))
	return null

## 取对象的网格坐标。doc 里存成 [x, y] 数组（JSON 没有 Vector2i）。
static func _obj_grid(obj: Dictionary) -> Vector2i:
	var g = obj.get("grid", null)
	if typeof(g) == TYPE_ARRAY and (g as Array).size() >= 2:
		return Vector2i(int(g[0]), int(g[1]))
	return Vector2i.ZERO

## 取装饰的世界坐标（deco 允许非格对齐）
static func _obj_pos(obj: Dictionary) -> Vector2:
	var p = obj.get("pos", null)
	if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	var gp: Vector2i = _obj_grid(obj)
	return Vector2(float(gp.x), float(gp.y))

# ---------------------------------------------------------------- 建筑

## 放建筑。会先检查占位、再占位、再实例化。
## 占位值：城墙/城门 = 2（可破屏障），普通建筑 = 1。
static func spawn_building(host: Node3D, grid, id: String, owner: String,
		grid_pos: Vector2i, rot: int = 0) -> Node:
	var bdef: Dictionary = DataLoader.get_building_def(id)
	if bdef.is_empty():
		push_warning("[ObjectSpawner] 未知建筑 id: " + id)
		return null

	var size: Vector2i = _building_size(bdef)
	# 90/270 度时 footprint 的 x/y 互换（编辑期只放开 0 度，这里先写好逻辑备用）
	if rot % 180 != 0:
		size = Vector2i(size.y, size.x)

	if grid != null:
		if not grid.is_placeable(grid_pos, size):
			return null
		var occ: int = 2 if (id.begins_with("wall_") or id == "gate") else 1
		grid.set_occupied(grid_pos, size, occ)

	var scene: PackedScene = load(BUILDING_SCENE)
	if scene == null:
		_rollback(grid, grid_pos, size)
		return null

	var b = scene.instantiate()
	b.building_id = id
	b.faction = owner
	b.grid_pos = grid_pos
	# ★ 地图里存的建筑都是「已建成」的。必须在这行之前置标志 ——
	#   _ready 在 add_child 里就跑完 _init_from_def()，之后改就来不及了。
	#   漏了这个：house / barracks 这种 build_time>0 的建筑载入后只剩一块
	#   阵营色地基平台，看不到房屋外观。
	b.spawn_as_complete = true
	if rot != 0:
		b.rotation_degrees.y = float(rot)
	host.add_child(b)
	b.global_position = _grid_to_world(grid, grid_pos)

	# 新占位会让旧路径失效（游戏里才需要，编辑器没有 pathfinder）
	if GameManager.pathfinder != null:
		GameManager.pathfinder.clear_cache()
	return b

static func _building_size(bdef: Dictionary) -> Vector2i:
	var s = bdef.get("size", [2, 2])
	if typeof(s) == TYPE_ARRAY and (s as Array).size() >= 2:
		return Vector2i(int(s[0]), int(s[1]))
	return Vector2i(2, 2)

# ---------------------------------------------------------------- 单位

static func spawn_unit(host: Node3D, grid, id: String, owner: String, grid_pos: Vector2i) -> Node:
	var udef: Dictionary = DataLoader.get_unit_def(id)
	if udef.is_empty():
		push_warning("[ObjectSpawner] 未知单位 id: " + id)
		return null
	var scene: PackedScene = load(UNIT_SCENE)
	if scene == null:
		return null
	var u = scene.instantiate()
	u.unit_id = id
	u.faction = owner
	host.add_child(u)
	u.global_position = _grid_to_world(grid, grid_pos)
	# 人口统计：游戏里要算，编辑器里不算（否则摆一批兵就把人口预算吃光了）
	if not GameManager.editor_mode:
		GameManager.change_population(owner, int(udef.get("pop_cost", 1)))
	return u

# ---------------------------------------------------------------- 资源

static func spawn_resource(host: Node3D, grid, id: String, grid_pos: Vector2i,
		amount: int = 800, is_mine: bool = false) -> Node:
	var scene: PackedScene = load(RESOURCE_SCENE)
	if scene == null:
		return null
	var n = scene.instantiate()
	n.resource_type = id
	if is_mine:
		# 矿洞：无限量、中立归属、可驻扎 8 人（对齐 Main._spawn_mine_node）
		n.amount = 99999.0
		n.max_amount = 99999.0
		n.is_mine = true
		n.mine_cap = 8
		n.mine_owner = ""
	else:
		n.amount = float(maxi(amount, 1))
		n.max_amount = float(maxi(amount, 1))
	n.init_with_grid_pos(grid_pos)
	host.add_child(n)
	n.global_position = _grid_to_world(grid, grid_pos)
	return n

# ---------------------------------------------------------------- 村庄 / 野马

static func spawn_village(host: Node3D, grid, id: String, grid_pos: Vector2i) -> Node:
	var scene: PackedScene = load(VILLAGE_SCENE)
	if scene == null:
		return null
	var v = scene.instantiate()
	v.village_id = id
	host.add_child(v)
	v.global_position = _grid_to_world(grid, grid_pos)
	return v

static func spawn_horse(host: Node3D, grid, id: String, grid_pos: Vector2i) -> Node:
	var scene: PackedScene = load(HORSE_SCENE)
	if scene == null:
		return null
	var h = scene.instantiate()
	h.horse_id = "horse_" + str(grid_pos.x) + "_" + str(grid_pos.y)
	h.horse_type = id
	host.add_child(h)
	h.global_position = _grid_to_world(grid, grid_pos)
	return h

# ---------------------------------------------------------------- 装饰

## deco 用世界坐标（允许半格偏移、允许叠放），因为它不参与寻路和占位
static func spawn_deco(host: Node3D, grid, id: String, pos: Vector2, sc: float = 1.0) -> Node:
	var info: Dictionary = parse_deco_id(id)
	if info.is_empty():
		return null

	var node: Node3D = null
	# 用世界坐标直接落位；没传 grid 就按格坐标当世界坐标兜底
	var wx: float = pos.x
	var wz: float = pos.y
	if grid != null and pos.x == floor(pos.x) and pos.y == floor(pos.y):
		var w: Vector3 = grid.grid_to_world(Vector2i(int(pos.x), int(pos.y)))
		wx = w.x
		wz = w.z
	var ground_y: float = Terrain.get_height(wx, wz)

	if str(info["kind"]) == "tree" and info.has("species"):
		# ---- GLB 树（用户 Blender 交付管线）----
		node = TreeGLTF.spawn(host, str(info["species"]), Vector3(wx, ground_y, wz))
		if node == null:
			push_warning("[ObjectSpawner] 未知树种: " + str(info["species"]))
			return null
		return node
	if str(info["kind"]) == "tree":
		var scr: GDScript = load(TREE_SCRIPT)
		if scr == null:
			return null
		node = scr.new()
		node.tree_type = int(info["type"])
	else:
		var scr2: GDScript = load(DECO_SCRIPT)
		if scr2 == null:
			return null
		node = scr2.new()
		node.deco_type = int(info["type"])

	host.add_child(node)
	node.global_position = Vector3(wx, ground_y, wz)
	if not is_equal_approx(sc, 1.0):
		node.scale *= sc
	return node

## deco id → 解析结果，三种形态：
##   { kind: "tree", type: int }            —— 旧程序树（tree_0 ~ tree_3）
##   { kind: "tree", species: "oak" }       —— GLB 树（tree_oak / tree_bamboo_v1 / tree_elm_dead）
##   { kind: "deco", type: int }            —— 程序装饰物
static func parse_deco_id(id: String) -> Dictionary:
	if id.begins_with("tree"):
		var rest := id.trim_prefix("tree_")
		# tree_数字 = 旧程序树 id —— 贴片已下线（2026-10-29），按序映射到 GLB 树种，
		# 存档/旧地图里的 tree_0~3 仍能渲染，只是变成真 3D 树。
		if rest.is_valid_int():
			var legacy: PackedStringArray = ["oak", "spruce", "willow", "maple"]
			return {"kind": "tree", "species": legacy[clampi(int(rest), 0, 3)]}
		if not rest.is_empty():
			return {"kind": "tree", "species": rest}
		return {"kind": "tree", "species": "oak"}
	if DECO_TYPES.has(id):
		return {"kind": "deco", "type": int(DECO_TYPES[id])}
	return {}

## 调色板要用：把 deco id 展开成一份完整清单
static func deco_ids() -> Array:
	var out: Array = []
	# GLB 树种（用户 Blender 交付的 35 种）。旧 tree_0~3 已下线不再列出，
	# 但 parse_deco_id 仍兼容它们（映射成 GLB 树）。
	for s in TreeGLTF.species_list():
		out.append("tree_" + s)
	for k in DECO_TYPES.keys():
		out.append(k)
	return out

# ---------------------------------------------------------------- 工具

## 删掉一个已放置的对象时要把它占的格子还回去
static func release_footprint(grid, obj: Dictionary) -> void:
	if grid == null or typeof(obj) != TYPE_DICTIONARY:
		return
	if str(obj.get("kind", "")) != "building":
		return
	var id: String = str(obj.get("id", ""))
	var bdef: Dictionary = DataLoader.get_building_def(id)
	if bdef.is_empty():
		return
	var size: Vector2i = _building_size(bdef)
	if int(obj.get("rot", 0)) % 180 != 0:
		size = Vector2i(size.y, size.x)
	grid.clear_occupied(_obj_grid(obj), size)

static func _grid_to_world(grid, grid_pos: Vector2i) -> Vector3:
	if grid != null:
		return grid.grid_to_world(grid_pos)
	var cell: float = 2.0
	var wx: float = (float(grid_pos.x) + 0.5) * cell
	var wz: float = (float(grid_pos.y) + 0.5) * cell
	return Vector3(wx, Terrain.get_height(wx, wz), wz)

static func _rollback(grid, grid_pos: Vector2i, size: Vector2i) -> void:
	if grid != null:
		grid.clear_occupied(grid_pos, size)
