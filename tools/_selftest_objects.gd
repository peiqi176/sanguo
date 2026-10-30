extends Node3D
## 对象层自测：ObjectSpawner + GridManager 占位 + doc/磁盘往返
##
## 跑法：
##   Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --quit-after 90 \
##     res://tools/_selftest_objects.tscn
##
## 验四件事：
##   1. 编辑器模式下实例化真建筑/单位不会崩、不会登记进 GameManager 全局列表
##   2. 建筑占位被正确标记，删掉后能还回去（否则拆了房子原地还是不能重建）
##   3. objects[] 存盘 → 读回来后字段完整（owner/rot/amount/is_mine 都不丢）
##   4. 编辑器模式关掉后，实体恢复自己跑（复位逻辑别漏）

const GridManager = preload("res://scripts/core/GridManager.gd")
const MapDoc = preload("res://scripts/mapformat/MapDoc.gd")
const MapIO = preload("res://scripts/mapformat/MapIO.gd")
const ObjectSpawner = preload("res://scripts/mapruntime/ObjectSpawner.gd")

const TEST_MAP: String = "_selftest_objects"

var fails: int = 0
var checks: int = 0
var grid = null

func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)

func _ready() -> void:
	GameManager.editor_mode = true
	# ⚠ 必须用平地：本测试只验对象层（占位/登记/存读档），不验地形。
	# 曾经直接用 default_params()——world_size 200→300 后，100×100 测试网格（200m）
	# 对到 300m 地形上，(4,4) 附近泡进水里，GridManager 按可建性预占 3800+ 格，
	# 第 5 节 _find_land(1,1) 找到的孤格放不下 2×2 的 house → spawn 返回 null。
	var p := Terrain.default_params()
	p.flat_ground = true
	Terrain.generate(p)

	grid = GridManager.new()
	grid.name = "TestGrid"
	grid.map_size = Vector2i(100, 100)
	grid.cell_size = 2.0
	add_child(grid)          # _ready 里会按已设好的 map_size 初始化

	print("=== 1. 编辑器模式下实例化实体 ===")
	var anchor: Vector2i = _find_land(Vector2i(3, 3))
	check(anchor != Vector2i(-1, -1), "地图上找到一块 3×3 陆地")

	print("=== 2. 建筑占位 ===")
	_test_building(anchor)

	print("=== 3. 其他对象类型 ===")
	_test_others(anchor)

	print("=== 4. doc → 磁盘 → doc ===")
	_test_persist()

	print("=== 5. editor_mode 复位 ===")
	_test_mode_reset()

	_cleanup()
	print("")
	print("[SELFTEST] %d 项检查，%d 项失败" % [checks, fails])
	if fails == 0:
		print("[SELFTEST] ✅ 对象层全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# ----------------------------------------------------------------

func _find_land(size: Vector2i) -> Vector2i:
	for x in range(4, 90):
		for z in range(4, 90):
			if grid.is_placeable(Vector2i(x, z), size):
				return Vector2i(x, z)
	return Vector2i(-1, -1)

var doc = null
var _built_nodes: Array = []

func _test_building(anchor: Vector2i) -> void:
	doc = MapDoc.new()
	doc.map_name = TEST_MAP
	doc.grid_n = 100
	doc.cell_size = 2.0

	var before_reg: int = GameManager.all_buildings.size()

	var obj: Dictionary = {"kind": "building", "id": "government", "owner": "wei",
			"grid": [anchor.x, anchor.y], "rot": 0}
	var node: Node = ObjectSpawner.spawn(self, grid, obj)
	check(node != null, "官府实例化成功")
	check(node is Node3D, "拿到的是 3D 节点")

	# 官府是 3×3（见 buildings.json）
	check(not grid.is_placeable(anchor, Vector2i(1, 1)), "占位已标记（原地不可再放）")
	check(GameManager.all_buildings.size() == before_reg,
			"editor_mode 下没有登记进 GameManager（否则全局列表会污染游戏）")

	# 同一位置再放一个必须失败
	var node2: Node = ObjectSpawner.spawn(self, grid, obj)
	check(node2 == null, "重叠放置被拒绝")

	# 归还占位后应能再放
	ObjectSpawner.release_footprint(grid, obj)
	check(grid.is_placeable(anchor, Vector2i(3, 3)), "release_footprint 把 3×3 还回来了")
	var node3: Node = ObjectSpawner.spawn(self, grid, obj)
	check(node3 != null, "归还后可以重新放置")

	doc.add_object(obj)
	if node != null:
		_built_nodes.append(node)
	if node3 != null:
		_built_nodes.append(node3)
	# node3 占着格子，后面测试另找地方
	ObjectSpawner.release_footprint(grid, obj)

func _test_others(anchor: Vector2i) -> void:
	var spot: Vector2i = _find_land(Vector2i(1, 1))
	check(spot != Vector2i(-1, -1), "找到 1×1 空地")

	# 单位
	var u_obj: Dictionary = {"kind": "unit", "id": "sword", "owner": "shu",
			"grid": [spot.x, spot.y], "rot": 0}
	var before_units: int = GameManager.all_units.size()
	var u: Node = ObjectSpawner.spawn(self, grid, u_obj)
	check(u != null, "单位剑兵实例化成功")
	check(GameManager.all_units.size() == before_units, "editor_mode 下单位也没登记")
	if u != null:
		_built_nodes.append(u)
		doc.add_object(u_obj)

	# 资源
	var spot2: Vector2i = _find_land(Vector2i(1, 1))
	var r_obj: Dictionary = {"kind": "resource", "id": "wood",
			"grid": [spot2.x, spot2.y], "amount": 900}
	var r: Node = ObjectSpawner.spawn(self, grid, r_obj)
	check(r != null, "木材资源点实例化成功")
	if r != null:
		_built_nodes.append(r)
		doc.add_object(r_obj)

	# 矿洞（is_mine 分支）
	var spot3: Vector2i = _find_land(Vector2i(1, 1))
	var m_obj: Dictionary = {"kind": "resource", "id": "iron",
			"grid": [spot3.x, spot3.y], "amount": 99999, "is_mine": true}
	var m: Node = ObjectSpawner.spawn(self, grid, m_obj)
	check(m != null, "矿洞实例化成功")
	if m != null:
		_built_nodes.append(m)
		doc.add_object(m_obj)

	# 装饰（用世界坐标，允许半格）
	var d_obj: Dictionary = {"kind": "deco", "id": "tree_2", "pos": [120.5, 130.25], "scale": 1.2}
	var d: Node = ObjectSpawner.spawn(self, grid, d_obj)
	check(d != null, "树实例化成功")
	if d != null:
		_built_nodes.append(d)
		doc.add_object(d_obj)
		var dy: float = (d as Node3D).global_position.y
		var expect: float = Terrain.get_height(120.5, 130.25)
		check(absf(dy - expect) < 0.01, "树贴地（y=%.2f 期望 %.2f）" % [dy, expect])

	check(doc.objects.size() == 5, "doc 里记了 5 条对象（实得 %d）" % doc.objects.size())

	# 未知 id 不该崩
	var bad: Node = ObjectSpawner.spawn(self, grid, {"kind": "building", "id": "不存在的建筑",
			"owner": "shu", "grid": [spot.x, spot.y]})
	check(bad == null, "未知建筑 id 返回 null 而不是崩")

func _test_persist() -> void:
	doc.capture_terrain_from(Terrain.params)
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RF)
	img.fill(Color(0.2, 0.0, 0.0, 1.0))

	check(MapIO.save(doc, img, null), "存盘成功")

	var loaded: Dictionary = MapIO.load_map(TEST_MAP)
	check(not loaded.is_empty(), "读档成功")
	if loaded.is_empty():
		return

	var d2 = loaded["doc"]
	check(d2.objects.size() == 5, "读回 5 条对象")

	var kinds: Dictionary = {}
	for o in d2.objects:
		kinds[str(o.get("kind", ""))] = true
	check(kinds.has("building") and kinds.has("unit") and kinds.has("resource") and kinds.has("deco"),
			"四种 kind 都在")

	# 字段完整性
	var res: Dictionary = {}
	var mine: Dictionary = {}
	for o in d2.objects:
		if str(o.get("kind", "")) != "resource":
			continue
		if bool(o.get("is_mine", false)):
			mine = o
		else:
			res = o
	check(not res.is_empty() and int(res.get("amount", 0)) == 900, "普通资源点 amount 保住")
	check(not mine.is_empty() and bool(mine.get("is_mine", false)), "矿洞 is_mine 保住")

	var b: Dictionary = {}
	for o in d2.objects:
		if str(o.get("kind", "")) == "building":
			b = o
	check(str(b.get("owner", "")) == "wei", "建筑 owner 保住")
	check(int(b.get("rot", -1)) == 0, "建筑 rot 保住")

	var deco: Dictionary = {}
	for o in d2.objects:
		if str(o.get("kind", "")) == "deco":
			deco = o
	var p = deco.get("pos", [])
	check(typeof(p) == TYPE_ARRAY and (p as Array).size() == 2, "装饰的世界坐标保住")
	check(absf(float(p[0]) - 120.5) < 0.001, "装饰坐标精度没丢")

func _test_mode_reset() -> void:
	# 模拟 Main._ready() 的复位
	GameManager.editor_mode = false
	var before: int = GameManager.all_buildings.size()
	var spot: Vector2i = _find_land(Vector2i(1, 1))
	var n: Node = ObjectSpawner.spawn(self, grid, {"kind": "building", "id": "house",
			"owner": "shu", "grid": [spot.x, spot.y]})
	check(n != null, "editor_mode 关掉后仍能正常实例化")
	check(GameManager.all_buildings.size() == before + 1,
			"editor_mode 关掉后恢复登记（证明复位是有效的）")
	if n != null:
		_built_nodes.append(n)
	GameManager.editor_mode = true

func _cleanup() -> void:
	for n in _built_nodes:
		if n != null and is_instance_valid(n):
			n.queue_free()
	if MapIO.exists(TEST_MAP):
		MapIO.delete_map(TEST_MAP)
	print("[SELFTEST] 测试目录已清理")
