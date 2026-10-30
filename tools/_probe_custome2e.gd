extends Node3D
## 探针：自建建筑 / 自建兵种真的能进场景吗（导入 → 实例化 → 可训练）
##
## 自测 `_selftest_entityimport` 只验证到"DataLoader 里查得到"。
## 这里再往前一步：让 ObjectSpawner 真的把 Building.tscn / Unit.tscn 实例化出来，
## 因为那边的默认值（hp/size/scale/贴图锚点）只要漏一个，就会在 _ready 里炸，
## 而不是在数据层被发现。
##
## 跑法：
##   ... --headless --path . res://tools/_probe_custome2e.tscn

const EntityImporter = preload("res://scripts/mapeditor/EntityImporter.gd")
const ObjectSpawner = preload("res://scripts/mapruntime/ObjectSpawner.gd")
const GridManager = preload("res://scripts/core/GridManager.gd")

const BID: String = "zz_probe_tower"
const UID: String = "zz_probe_guard"
const TMP: String = "user://_probe_custome2e"

var fails: int = 0
var _grid = null

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)

func _ready() -> void:
	GameManager.editor_mode = true
	Terrain.generate(Terrain.default_params())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))

	print("=== 1. 导入自建建筑 + 自建兵种 ===")
	var bdef: Dictionary = EntityImporter.default_building_def("探针望楼", Vector2i(2, 2))
	bdef["hp"] = 900
	var rb: Dictionary = EntityImporter.import_entity(_png("tower.png", 128, 128), EntityImporter.KIND_BUILDING, BID, bdef, 2.2)
	_ck(bool(rb["ok"]), "建筑导入：%s" % str(rb["message"]))

	var udef: Dictionary = EntityImporter.default_unit_def("探针铁卫", "infantry")
	udef["hp"] = 140
	udef["train_from"] = ["barracks_sword"]
	var ru: Dictionary = EntityImporter.import_entity(_png("guard.png", 128, 192), EntityImporter.KIND_UNIT, UID, udef, 0.85)
	_ck(bool(ru["ok"]), "兵种导入：%s" % str(ru["message"]))

	print("=== 2. 网格 + 找空地 ===")
	_grid = GridManager.new()
	_grid.name = "ProbeGrid"
	_grid.map_size = Vector2i(80, 80)
	_grid.cell_size = 2.0
	add_child(_grid)
	var spot: Vector2i = _find_spot(Vector2i(2, 2))
	_ck(spot != Vector2i(-1, -1), "找到一块 2×2 可放空地 %s" % str(spot))

	print("=== 3. 建筑真能实例化（不是空壳地基）===")
	var b = ObjectSpawner.spawn_building(self, _grid, BID, "shu", spot)
	_ck(b != null, "spawn_building 返回了节点（未知 id 会返回 null）")
	if b != null:
		_ck(absf(float(b.get("max_hp")) - 900.0) < 0.01, "血量取自自定义定义（%s）" % str(b.get("max_hp")))
		_ck(float(b.get("build_progress")) >= 0.999, "从地图载入 = 已建成（progress=%s）" % str(b.get("build_progress")))
		var sp = b.get("_sprite")
		_ck(sp != null and sp.texture != null, "建筑外观贴图已挂上")
		_ck(sp != null and is_zero_approx(float(sp.transparency)), "贴图不是全透明（transparency=0）")
		_ck(absf(float(b.global_position.y) - Terrain.get_height(b.global_position.x, b.global_position.z)) < 2.5,
			"大致贴在地面上（y=%.2f）" % float(b.global_position.y))

	print("=== 4. 兵种真能实例化 ===")
	var u = ObjectSpawner.spawn_unit(self, _grid, UID, "shu", spot + Vector2i(3, 0))
	_ck(u != null, "spawn_unit 返回了节点")
	if u != null:
		_ck(absf(float(u.get("max_hp")) - 140.0) < 0.01, "血量取自自定义定义（%s）" % str(u.get("max_hp")))
		var usp = u.get("_sprite")
		_ck(usp != null and usp.texture != null, "兵种贴图已挂上")
		_ck(usp != null and is_zero_approx(float(usp.transparency)), "兵种贴图不是全透明")
		_ck(usp != null and is_finite(float(usp.position.y)), "贴地锚点算出来了（y=%.3f）" % float(usp.position.y if usp != null else 0.0))

	print("=== 5. 游戏内可训练（兵营 trains 注入）===")
	var trains: Array = DataLoader.get_building_def("barracks_sword").get("trains", [])
	_ck(trains.has(UID), "刀兵营能训练它（trains=%s）" % str(trains))

	_cleanup()
	print("")
	if fails == 0:
		print("[PROBE] ✅ 自建实体端到端 全部通过")
	else:
		print("[PROBE] ❌ 有 %d 项失败" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# ---------------------------------------------------------------- 工具

func _find_spot(size: Vector2i) -> Vector2i:
	for y in range(3, 70):
		for x in range(3, 70):
			if _grid.is_placeable(Vector2i(x, y), size):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _png(name: String, w: int, h: int) -> String:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(int(w * 0.18), int(h * 0.08), int(w * 0.64), int(h * 0.86)),
		Color(0.5, 0.44, 0.36, 1.0))
	var abs_path: String = ProjectSettings.globalize_path(TMP + "/" + name)
	img.save_png(abs_path)
	return abs_path

func _cleanup() -> void:
	EntityImporter.remove_entity(EntityImporter.KIND_BUILDING, BID)
	EntityImporter.remove_entity(EntityImporter.KIND_UNIT, UID)
	for f in ["zz_probe_tower.png", "zz_probe_guard.png"]:
		var p: String = "res://assets/sprites/" + f
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	# 测试前没有 custom 文件的话，删掉（只留一个空表在工程里没意义）
	for p2 in [EntityImporter.CUSTOM_UNITS_PATH, EntityImporter.CUSTOM_BUILDINGS_PATH]:
		if not FileAccess.file_exists(p2):
			continue
		var fh: FileAccess = FileAccess.open(p2, FileAccess.READ)
		var txt: String = fh.get_as_text() if fh != null else ""
		if fh != null:
			fh.close()
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_DICTIONARY:
			var body = parsed.get("units", parsed.get("buildings", {}))
			if typeof(body) == TYPE_DICTIONARY and (body as Dictionary).is_empty():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p2))
	DataLoader.reload_entities()
	var abs_tmp: String = ProjectSettings.globalize_path(TMP)
	var d: DirAccess = DirAccess.open(abs_tmp)
	if d != null:
		for f3 in d.get_files():
			DirAccess.remove_absolute(abs_tmp + "/" + f3)
	DirAccess.remove_absolute(abs_tmp)
