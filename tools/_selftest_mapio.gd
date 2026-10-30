extends Node
## 数据层自测：MapDoc / MapIO
##
## 跑法：
##   Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --quit-after 60 \
##     res://tools/_selftest_mapio.tscn
##
## 验四件事：
##   1. MapDoc dict 往返字段全等
##   2. capture_terrain_from / apply_terrain_to 能无损搬 28 个地形参数
##   3. MapIO 存 → 读，高度图 float 精度无损（差值必须为 0，不是"接近 0"）
##   4. list_maps 能把工坊地图和 legacy 参数图分开，不混读

const MapDoc = preload("res://scripts/mapformat/MapDoc.gd")
const MapIO = preload("res://scripts/mapformat/MapIO.gd")
const MapParams = preload("res://scripts/core/MapParams.gd")

const TEST_MAP: String = "_selftest_mapio"
const LEGACY_DIR: String = "user://maps/_selftest_legacy/"

var fails: int = 0
var checks: int = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)

func _ready() -> void:
	print("=== 1. MapDoc dict 往返 ===")
	_test_doc_roundtrip()

	print("=== 2. 地形参数桥 ===")
	_test_param_bridge()

	print("=== 3. MapIO 存读往返（高度精度）===")
	_test_io_roundtrip()

	print("=== 4. 列表与 legacy 区分 ===")
	_test_list_and_legacy()

	_cleanup()

	print("")
	print("[SELFTEST] %d 项检查，%d 项失败" % [checks, fails])
	if fails == 0:
		print("[SELFTEST] ✅ 数据层全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# ----------------------------------------------------------------

func _test_doc_roundtrip() -> void:
	var d = MapDoc.new()
	d.map_name = "赤壁之战"
	d.author = "shy"
	d.desc = "长江天险"
	d.grid_n = 168
	d.cell_size = 2.0
	d.add_object({"kind": "building", "id": "government", "owner": "wei", "grid": [132, 24], "rot": 0})
	d.add_object({"kind": "unit", "id": "sword", "owner": "wei", "grid": [130, 22], "rot": 180})
	d.add_object({"kind": "deco", "id": "tree_2", "pos": [210.5, 133.0], "scale": 1.2})
	d.set_player(0, {"faction": "wei", "start": [132, 24], "color": "blue"})
	d.set_player(1, {"faction": "wu", "start": [36, 132], "color": "red"})
	d.regions.append({"id": "r1", "shape": "circle", "pts": [[80, 80], 16]})

	var back = MapDoc.new()
	var ok: bool = back.from_dict(d.to_dict())

	check(ok, "from_dict 返回 true")
	check(back.map_name == "赤壁之战", "name 保住")
	check(back.grid_n == 168 and back.cell_size == 2.0, "grid 保住")
	check(back.world_size() == 336.0, "world_size() == n*cell == 336")
	check(back.objects.size() == 3, "objects 数量 3")
	check(back.count_by_kind("building") == 1, "count_by_kind(building) == 1")
	check(back.start_points().size() == 2, "start_points 拿到 2 个")
	check(back.start_points()[0] == Vector2i(132, 24), "起点坐标是 Vector2i 不是 Array")
	check(back.regions.size() == 1, "regions 保住")
	check(back.to_dict() == d.to_dict(), "整个 dict 再序列化完全相等")

	# kind 判别：伪造一个非工坊 dict 必须被拒
	var fake: Dictionary = d.to_dict()
	fake["kind"] = "something_else"
	check(not MapDoc.new().from_dict(fake), "kind 不匹配时 from_dict 拒绝")

	# 删对象返回被删的那条（撤销要用）
	var removed: Dictionary = back.remove_object(1)
	check(str(removed.get("id", "")) == "sword", "remove_object 返回被删对象")
	check(back.objects.size() == 2, "删除后剩 2 条")

func _test_param_bridge() -> void:
	var p = MapParams.new()
	p.seed = 123456
	p.world_size = 240.0
	p.max_height = 12.5
	p.water_level = -3.25
	p.river_count = 7
	p.forest_density = 1.75

	var d = MapDoc.new()
	d.cell_size = 2.0
	d.capture_terrain_from(p)

	# MapParams 现在有 28 个脚本变量
	check(d.terrain.size() >= 28, "capture 抓到 >=28 个字段（实得 %d）" % d.terrain.size())
	check(int(d.terrain.get("seed", 0)) == 123456, "seed 抓到")
	check(absf(float(d.terrain.get("max_height", 0.0)) - 12.5) < 1e-6, "max_height 抓到")
	check(absf(float(d.terrain.get("forest_density", 0.0)) - 1.75) < 1e-6, "forest_density 抓到")
	check(d.grid_n == 120, "grid_n 由 world_size/cell_size 反推 = 120")
	check(d.heightmap_size == p.heightmap_size, "heightmap_size 同步")

	var p2 = MapParams.new()
	d.apply_terrain_to(p2)
	check(p2.seed == 123456, "apply 回写 seed")
	check(absf(p2.max_height - 12.5) < 1e-6, "apply 回写 max_height")
	check(p2.river_count == 7, "int 属性没有被 float 污染（river_count=7）")
	check(absf(p2.water_level - (-3.25)) < 1e-6, "负数 water_level 正确")

func _test_io_roundtrip() -> void:
	# 造一张 64x64 的高度图，值刻意用不规则的 float
	var sz: int = 64
	var img: Image = Image.create(sz, sz, false, Image.FORMAT_RF)
	for y in range(sz):
		for x in range(sz):
			var v: float = sin(float(x) * 0.31) * 0.42 + cos(float(y) * 0.17) * 0.33 + float(x * y % 7) * 0.01
			img.set_pixel(x, y, Color(v, 0.0, 0.0, 1.0))

	var biome: Image = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	biome.fill(Color(0.25, 0.5, 0.1, 1.0))

	var d = MapDoc.new()
	d.map_name = TEST_MAP
	d.grid_n = 84
	d.cell_size = 2.0
	d.add_object({"kind": "building", "id": "government", "owner": "shu", "grid": [10, 10], "rot": 0})
	d.add_object({"kind": "resource", "id": "wood", "grid": [20, 20], "amount": 900})

	var saved: bool = MapIO.save(d, img, biome)
	check(saved, "MapIO.save 返回 true")
	check(MapIO.exists(TEST_MAP), "exists() 认得出刚存的图")

	var loaded: Dictionary = MapIO.load_map(TEST_MAP)
	check(not loaded.is_empty(), "load_map 返回非空")
	if loaded.is_empty():
		return

	var d2 = loaded["doc"]
	var h2: Image = loaded["height"]
	check(d2.map_name == TEST_MAP, "读回来的名字对")
	check(d2.objects.size() == 2, "读回来 2 个对象")
	check(d2.objects[1].has("amount") and int(d2.objects[1]["amount"]) == 900, "对象自定义字段 amount 保住")
	check(h2 != null and h2.get_width() == sz, "高度图尺寸对")

	# 精度：二进制必须完全一致，不是"接近"
	var exact: bool = true
	var worst: float = 0.0
	if h2 != null:
		for y in range(sz):
			for x in range(sz):
				var a: float = img.get_pixel(x, y).r
				var b: float = h2.get_pixel(x, y).r
				var diff: float = absf(a - b)
				if diff > worst:
					worst = diff
				if diff != 0.0:
					exact = false
	check(exact, "高度图 float 往返零误差（最大差 %s）" % str(worst))

	var bi2 = loaded["biome"]
	check(bi2 != null and bi2.get_width() == sz, "群系图读回来")

	# 只改元数据时不该动图
	d2.desc = "只改描述"
	MapIO.save(d2, null, null)
	var loaded2: Dictionary = MapIO.load_map(TEST_MAP)
	check(not loaded2.is_empty() and loaded2["height"] != null, "save(doc, null, null) 保留磁盘旧图")
	check(str(loaded2["doc"].desc) == "只改描述", "元数据改动生效")

func _test_list_and_legacy() -> void:
	# 造一个假的 legacy 参数图（只有 params.json）
	DirAccess.make_dir_recursive_absolute(LEGACY_DIR)
	var lf: FileAccess = FileAccess.open(LEGACY_DIR + "params.json", FileAccess.WRITE)
	if lf != null:
		lf.store_string(JSON.stringify({"seed": 1, "world_size": 200.0}))
		lf.close()

	var list: Array = MapIO.list_maps()
	var found_forge: bool = false
	var found_legacy: bool = false
	for it in list:
		if str(it.get("name", "")) == TEST_MAP and not bool(it.get("legacy", false)):
			found_forge = true
			check(int(it.get("grid_n", 0)) == 84, "工坊条目带 grid_n")
			check(bool(it.get("has_height", false)), "工坊条目 has_height=true")
		if str(it.get("name", "")) == "_selftest_legacy" and bool(it.get("legacy", false)):
			found_legacy = true

	check(found_forge, "list_maps 列出工坊地图且 legacy=false")
	check(found_legacy, "list_maps 列出老参数图且 legacy=true")

	# 两条互不干扰
	check(int(MapIO.peek(TEST_MAP).get("object_count", -1)) == 2, "peek 拿到 object_count")
	check(MapIO.peek("_selftest_legacy").get("legacy", false) == true, "peek legacy 正确识别")

	# MapSaveManager 只该看到 legacy，不该看到工坊地图
	var legacy_list: Array = MapSave.list_maps()
	check(not legacy_list.has(TEST_MAP), "MapSaveManager.list_maps 不会列出工坊地图")
	check(legacy_list.has("_selftest_legacy"), "MapSaveManager.list_maps 列出自己的参数图")

	# 保护：MapSaveManager 不能删工坊地图
	check(not MapSave.delete_map(TEST_MAP), "MapSaveManager.delete_map 拒绝删工坊地图")
	check(MapIO.exists(TEST_MAP), "工坊地图还在")
	# 保护：MapIO 不能删 legacy
	check(not MapIO.delete_map("_selftest_legacy"), "MapIO.delete_map 拒绝删老参数图")

func _cleanup() -> void:
	if MapIO.exists(TEST_MAP):
		MapIO.delete_map(TEST_MAP)
	if DirAccess.dir_exists_absolute(LEGACY_DIR):
		DirAccess.remove_absolute(LEGACY_DIR + "params.json")
		DirAccess.remove_absolute(LEGACY_DIR)
	print("[SELFTEST] 测试目录已清理")
