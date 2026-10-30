extends Node3D
## 实体导入自测（M3-6）：把「导入建筑 / 导入兵种」这条链路从头验到尾
##
## 跑法：
##   Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . res://tools/_selftest_entityimport.tscn
##
## 会临时写 config/custom_*.json、改 asset_map.json、往 assets/sprites/ 拷测试图，
## 结束时全部还原（内存备份写回 + 删测试图），断在中途也不留垃圾：
## 测试实体一律以 zz_selftest_ 开头。

const EntityImporter = preload("res://scripts/mapeditor/EntityImporter.gd")
const AssetImporter = preload("res://scripts/mapeditor/AssetImporter.gd")
const PalettePanel = preload("res://scripts/mapeditor/PalettePanel.gd")

const TEST_BID: String = "zz_selftest_tower"
const TEST_UID: String = "zz_selftest_guard"
const TEST_BPNG: String = "res://assets/sprites/zz_selftest_tower.png"
const TEST_UPNG: String = "res://assets/sprites/zz_selftest_guard.png"
const TMP_DIR: String = "user://_selftest_entity"

var fails: int = 0
var checks: int = 0
var _map_backup: String = ""
var _cu_backup: Variant = null      # null = 测试前文件不存在
var _cb_backup: Variant = null

func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)

func _ready() -> void:
	_map_backup = _read_text(AssetImporter.ASSET_MAP_PATH)
	_cu_backup = _read_text_or_null(EntityImporter.CUSTOM_UNITS_PATH)
	_cb_backup = _read_text_or_null(EntityImporter.CUSTOM_BUILDINGS_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))

	print("=== 1. 调色板取的是解包后的表（不是 _meta / buildings 这两个字面量）===")
	_test_palette_container()

	print("=== 2. 默认模板开箱可用 ===")
	_test_defaults()

	print("=== 3. id 规则：内置保护 / 大小写 / 数字开头 ===")
	_test_id_rules()

	print("=== 4. 数值校验：越界必须拦下来 ===")
	_test_numeric_validate()

	print("=== 5. 导入建筑：贴图 + 定义 + DataLoader 三处都要对上 ===")
	_test_import_building()

	print("=== 6. 重复导入 = 覆盖（不能出现两条同名）===")
	_test_overwrite()

	print("=== 7. 导入兵种 + id 自动递增 ===")
	_test_import_unit()

	print("=== 8. 删除：定义与贴图映射都摘掉，PNG 留着 ===")
	_test_remove()

	_cleanup()
	print("")
	print("[SELFTEST] %d 项检查，%d 项失败" % [checks, fails])
	if fails == 0:
		print("[SELFTEST] ✅ 实体导入全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# ---------------------------------------------------------------- 1

func _test_palette_container() -> void:
	var bmap: Dictionary = DataLoader.buildings.get("buildings", {})
	var umap: Dictionary = DataLoader.units.get("units", {})
	check(bmap.size() >= 30, "buildings 解包后至少 30 条（实得 %d）" % bmap.size())
	check(umap.size() >= 30, "units 解包后至少 30 条（实得 %d）" % umap.size())
	check(bmap.has("house"), "解包后的表里有 house")
	check(umap.has("peasant"), "解包后的表里有 peasant")

	# 直接问调色板要列表，确认它拿的不是容器壳
	var p = PalettePanel.new(null)
	p._cat = "building"
	var bids: Array = p._all_ids()
	check(bids.size() == bmap.size(), "调色板建筑页项数 = %d（实得 %d）" % [bmap.size(), bids.size()])
	check(not bids.has("_meta") and not bids.has("buildings"), "建筑页里没有 _meta / buildings 这种假条目")
	p._cat = "unit"
	var uids: Array = p._all_ids()
	check(uids.size() == umap.size(), "调色板单位页项数 = %d（实得 %d）" % [umap.size(), uids.size()])
	check(uids.has("peasant"), "单位页里能看到 peasant")
	# PalettePanel 是 RefCounted，别调 free()（会报 "Attempted to free a RefCounted object"，
	# 而且报错时自测仍然是绿的 —— 只有真跑一次才看得见，所以这里留个注释）
	p = null

# ---------------------------------------------------------------- 2

func _test_defaults() -> void:
	var bd: Dictionary = EntityImporter.default_building_def("望楼")
	check(str(bd["name"]) == "望楼", "默认建筑名写进去了")
	check((bd["size"] as Array).size() == 2, "默认尺寸是 [宽, 深] 两元组")
	var bv: Dictionary = EntityImporter.validate(EntityImporter.KIND_BUILDING, "zz_selftest_tmp", bd)
	check(bool(bv["ok"]), "默认建筑定义开箱就合法（errors=%s）" % str(bv["errors"]))

	var ud: Dictionary = EntityImporter.default_unit_def("连弩兵", "archer")
	check(str(ud["category"]) == "archer", "默认兵种记住了传入的类别")
	var uv: Dictionary = EntityImporter.validate(EntityImporter.KIND_UNIT, "zz_selftest_tmp2", ud)
	check(bool(uv["ok"]), "默认兵种定义开箱就合法（errors=%s）" % str(uv["errors"]))

	# 类别写错时要被纠正，而不是把非法值写进表
	var bad_cat: Dictionary = EntityImporter.default_unit_def("怪兵", "wizard")
	check(str(bad_cat["category"]) == "infantry", "非法类别退化成 infantry")

# ---------------------------------------------------------------- 3

func _test_id_rules() -> void:
	check(EntityImporter.check_id(EntityImporter.KIND_BUILDING, "") != "", "空 id 被拒")
	check(EntityImporter.check_id(EntityImporter.KIND_BUILDING, "WatchTower") != "", "含大写被拒")
	check(EntityImporter.check_id(EntityImporter.KIND_BUILDING, "1tower") != "", "数字开头被拒")
	check(EntityImporter.check_id(EntityImporter.KIND_BUILDING, "watch-tower") != "", "含连字符被拒")
	check(EntityImporter.check_id(EntityImporter.KIND_BUILDING, "watch_tower") == "", "合法 id 通过")
	var conflict: String = EntityImporter.check_id(EntityImporter.KIND_BUILDING, "house")
	check(conflict != "" and conflict.contains("内置"), "内置建筑 id 撞名被拦下：%s" % conflict)
	check(EntityImporter.is_builtin(EntityImporter.KIND_BUILDING, "house"), "house 被判为内置")
	check(EntityImporter.is_builtin(EntityImporter.KIND_UNIT, "peasant"), "peasant 被判为内置")
	check(not EntityImporter.is_custom(EntityImporter.KIND_BUILDING, "house"), "内置不算自建")

# ---------------------------------------------------------------- 4

func _test_numeric_validate() -> void:
	var d: Dictionary = EntityImporter.default_building_def("坏楼")
	d["hp"] = 0
	check(not bool(EntityImporter.validate(EntityImporter.KIND_BUILDING, "zz_a", d)["ok"]), "建筑 0 血被拒")

	d = EntityImporter.default_building_def("坏楼")
	d["size"] = [12, 2]
	var sv: Dictionary = EntityImporter.validate(EntityImporter.KIND_BUILDING, "zz_a", d)
	check(not bool(sv["ok"]), "建筑尺寸 12×2 被拒")
	check(str(sv["errors"][0]).contains("超范围"), "拒绝原因说清了是尺寸超范围")

	d = EntityImporter.default_building_def("大院子")
	d["size"] = [7, 7]
	var wv: Dictionary = EntityImporter.validate(EntityImporter.KIND_BUILDING, "zz_a", d)
	check(bool(wv["ok"]) and (wv["warnings"] as Array).size() > 0, "7×7 只是警告，仍可导入")

	d = EntityImporter.default_unit_def("蜗牛")
	d["move_speed"] = 0.0
	check(not bool(EntityImporter.validate(EntityImporter.KIND_UNIT, "zz_b", d)["ok"]), "移速 0 被拒")

	d = EntityImporter.default_unit_def("无兵")
	d["name"] = ""
	check(not bool(EntityImporter.validate(EntityImporter.KIND_UNIT, "zz_b", d)["ok"]), "空名字被拒")

	d = EntityImporter.default_unit_def("乱花")
	d["cost"] = {"wood": 10, "diamond": 5}
	var cv: Dictionary = EntityImporter.validate(EntityImporter.KIND_UNIT, "zz_b", d)
	check(bool(cv["ok"]), "多出来的资源种类不阻止导入")
	check(str(cv["warnings"][0]).contains("diamond"), "但会警告 diamond 不存在")

# ---------------------------------------------------------------- 5

func _test_import_building() -> void:
	var src: String = _tmp_png("tower.png", 128, 128, Rect2i(24, 20, 80, 104))
	var def: Dictionary = EntityImporter.default_building_def("望楼", Vector2i(2, 2))
	def["hp"] = 900
	def["cost"] = {"wood": 180, "gold": 40}
	var res: Dictionary = EntityImporter.import_entity(src, EntityImporter.KIND_BUILDING, TEST_BID, def, 2.4)
	check(bool(res["ok"]), "导入成功：%s" % str(res["message"]))

	# ① 贴图：文件到位 + 映射到位
	check(FileAccess.file_exists(TEST_BPNG), "PNG 已拷进 assets/sprites/")
	var adef: Dictionary = DataLoader.get_asset_def("buildings", TEST_BID)
	check(str(adef.get("sprite", "")) == "zz_selftest_tower.png", "asset_map 里挂上了这张图")
	check(absf(float(adef.get("scale", 0.0)) - 2.4) < 0.001, "缩放写的是 2.4（实得 %.2f）" % float(adef.get("scale", 0.0)))
	check(DataLoader.get_sprite_texture("buildings", TEST_BID) != null, "纹理会话内立刻能取到（不用重启）")

	# ② 玩法定义：内存里查得到，字段对得上
	var bdef: Dictionary = DataLoader.get_building_def(TEST_BID)
	check(not bdef.is_empty(), "DataLoader 立刻查得到这个建筑")
	check(str(bdef.get("name", "")) == "望楼", "名字是「望楼」")
	check(absf(float(bdef.get("hp", 0)) - 900.0) < 0.01, "血量 900（实得 %s）" % str(bdef.get("hp")))
	check((bdef.get("size", []) as Array).size() == 2 and int(bdef["size"][0]) == 2, "尺寸落成 [2, 2]")
	check(int((bdef.get("cost", {}) as Dictionary).get("wood", 0)) == 180, "造价 · 木 180")
	check(bool(bdef.get("custom", false)), "定义里打了 custom 标记")

	# ③ 落盘：文件里真有这条，且没碰内置表
	check(DataLoader.custom_building_ids.has(TEST_BID), "custom_buildings.json 里的 id 清单含它")
	var store: Dictionary = _read_json(EntityImporter.CUSTOM_BUILDINGS_PATH)
	check((store.get("buildings", {}) as Dictionary).has(TEST_BID), "磁盘上的 custom_buildings.json 真有这条")
	var house: Dictionary = DataLoader.get_building_def("house")
	check(absf(float(house.get("hp", 0)) - 400.0) < 0.01,
		"内置 house 仍是 400 血（实得 %s，没被顺手改掉）" % str(house.get("hp")))

	# ④ 能真的摆进场景：和编辑器放置走同一个入口
	check(EntityImporter.is_custom(EntityImporter.KIND_BUILDING, TEST_BID), "它被认成自建建筑")

# ---------------------------------------------------------------- 6

func _test_overwrite() -> void:
	var src: String = _tmp_png("tower2.png", 128, 128, Rect2i(20, 16, 88, 108))
	var def: Dictionary = EntityImporter.default_building_def("望楼贰")
	def["hp"] = 1500
	var res: Dictionary = EntityImporter.import_entity(src, EntityImporter.KIND_BUILDING, TEST_BID, def, 2.4)
	check(bool(res["ok"]), "同 id 再导一次成功")
	var bdef: Dictionary = DataLoader.get_building_def(TEST_BID)
	check(absf(float(bdef.get("hp", 0)) - 1500.0) < 0.01, "血量被覆盖成 1500（实得 %s）" % str(bdef.get("hp")))
	check(str(bdef.get("name", "")) == "望楼贰", "名字也被覆盖")
	var store: Dictionary = _read_json(EntityImporter.CUSTOM_BUILDINGS_PATH)
	var block: Dictionary = store.get("buildings", {})
	check(block.size() == 1 and block.has(TEST_BID), "表里只有这一条，没有堆出重复项（实得 %d）" % block.size())

# ---------------------------------------------------------------- 7

func _test_import_unit() -> void:
	check(EntityImporter.next_free_id(EntityImporter.KIND_UNIT, TEST_UID) == TEST_UID,
		"还没被占用的 id 原样返回")
	var src: String = _tmp_png("guard.png", 128, 192, Rect2i(28, 16, 72, 172))
	var def: Dictionary = EntityImporter.default_unit_def("铁卫", "infantry")
	def["hp"] = 140
	def["atk"] = 16
	def["move_speed"] = 2.9
	var res: Dictionary = EntityImporter.import_entity(src, EntityImporter.KIND_UNIT, TEST_UID, def, 0.9)
	check(bool(res["ok"]), "兵种导入成功：%s" % str(res["message"]))

	var udef: Dictionary = DataLoader.get_unit_def(TEST_UID)
	check(not udef.is_empty(), "DataLoader 查得到这个兵种")
	check(absf(float(udef.get("atk", 0)) - 16.0) < 0.01, "攻击 16")
	check(absf(float(udef.get("move_speed", 0)) - 2.9) < 0.01, "移速 2.9")
	check(FileAccess.file_exists(TEST_UPNG), "兵种 PNG 也到位了")
	check(DataLoader.get_sprite_texture("units", TEST_UID) != null, "兵种贴图会话内可用")

	# 同一个兵种再导一次 → 自动换 id 就不能撞自己
	var next: String = EntityImporter.next_free_id(EntityImporter.KIND_UNIT, TEST_UID)
	check(next == TEST_UID + "_2", "已占用的 id 自动变成 %s_2（实得 %s）" % [TEST_UID, next])

	# 训练挂载：新兵种必须能从兵营里造出来，否则等于只导入了半个兵
	var trains: Array = DataLoader.get_building_def("barracks_sword").get("trains", [])
	check(trains.has(TEST_UID), "刀兵营的 trains 里注入了新兵种（实得 %s）" % str(trains))
	var disk_b: Dictionary = _read_json("res://config/buildings.json").get("buildings", {})
	check(not (disk_b["barracks_sword"].get("trains", []) as Array).has(TEST_UID),
		"磁盘上的 buildings.json 没被改（注入只发生在内存）")
	check(EntityImporter.trainable_buildings().size() >= 5,
		"可选训练建筑至少 5 个（实得 %d）" % EntityImporter.trainable_buildings().size())

	# 内置兵种表必须完好（peasant hp 2026-10-27 晚平衡调整 40→60，见 config/units.json）
	check(absf(float(DataLoader.get_unit_def("peasant").get("hp", 0)) - 60.0) < 0.01, "内置 peasant 仍是 60 血")

# ---------------------------------------------------------------- 8

func _test_remove() -> void:
	var r: Dictionary = EntityImporter.remove_entity(EntityImporter.KIND_BUILDING, "house")
	check(not bool(r["ok"]), "内置建筑删不掉：%s" % str(r["message"]))
	check(not DataLoader.get_building_def("house").is_empty(), "house 还在")

	r = EntityImporter.remove_entity(EntityImporter.KIND_BUILDING, TEST_BID)
	check(bool(r["ok"]), "自建建筑删除成功：%s" % str(r["message"]))
	check(DataLoader.get_building_def(TEST_BID).is_empty(), "内存里的定义没了")
	check(DataLoader.get_asset_def("buildings", TEST_BID).is_empty(), "asset_map 里的映射也没了")
	check(not DataLoader.custom_building_ids.has(TEST_BID), "custom id 清单里没了")
	check(FileAccess.file_exists(TEST_BPNG), "PNG 文件保留（可以在「未注册」里找回）")
	check(AssetImporter.orphan_files().has("zz_selftest_tower.png"), "它落进了未注册分组")

	r = EntityImporter.remove_entity(EntityImporter.KIND_UNIT, TEST_UID)
	check(bool(r["ok"]), "自建兵种删除成功")
	check(DataLoader.get_unit_def(TEST_UID).is_empty(), "内存里查不到了")
	var trains2: Array = DataLoader.get_building_def("barracks_sword").get("trains", [])
	check(not trains2.has(TEST_UID), "刀兵营的 trains 里也没了（注入随 reload 一起复原）")
	check(trains2.has("sword"), "但原来的 sword 还在（没把兵营训练表一起清空）")

# ---------------------------------------------------------------- 工具

func _tmp_png(name: String, w: int, h: int, inner: Rect2i) -> String:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if inner.size.x > 0 and inner.size.y > 0:
		img.fill_rect(inner, Color(0.52, 0.46, 0.38, 1.0))
	var abs_path: String = ProjectSettings.globalize_path(TMP_DIR + "/" + name)
	var err: int = img.save_png(abs_path)
	if err != OK:
		print("  ⚠ 造图失败 %s（错误码 %d）" % [abs_path, err])
	return abs_path

func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t

## 存在则返回内容，不存在返回 null（用来区分"原来没有这个文件"）
func _read_text_or_null(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return _read_text(path)

func _read_json(path: String) -> Dictionary:
	var t: String = _read_text(path)
	if t == "":
		return {}
	var parsed = JSON.parse_string(t)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _cleanup() -> void:
	# 还原 asset_map.json（逐字节写回，不留格式化差异）
	if _map_backup != "":
		var f: FileAccess = FileAccess.open(AssetImporter.ASSET_MAP_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_map_backup)
			f.close()
	# 还原 custom_*.json：原来没有就删掉，别在工程里留一个"测试生成"的空表
	_restore_or_delete(EntityImporter.CUSTOM_UNITS_PATH, _cu_backup)
	_restore_or_delete(EntityImporter.CUSTOM_BUILDINGS_PATH, _cb_backup)
	DataLoader.reload_entities()
	DataLoader.reload_asset_map()
	check(DataLoader.get_building_def(TEST_BID).is_empty(), "清理后内存里没有测试建筑")
	check(DataLoader.get_unit_def(TEST_UID).is_empty(), "清理后内存里没有测试兵种")
	check(DataLoader.get_asset_def("buildings", TEST_BID).is_empty(), "清理后 asset_map 没有测试条目")

	for p in [TEST_BPNG, TEST_UPNG]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	check(not FileAccess.file_exists(TEST_BPNG) and not FileAccess.file_exists(TEST_UPNG), "测试图已删除")

	if _cu_backup == null:
		check(not FileAccess.file_exists(EntityImporter.CUSTOM_UNITS_PATH), "custom_units.json 已删（测试前本来就没有）")
	if _cb_backup == null:
		check(not FileAccess.file_exists(EntityImporter.CUSTOM_BUILDINGS_PATH), "custom_buildings.json 已删（测试前本来就没有）")

	# 删掉临时目录里的原图
	var tmp_abs: String = ProjectSettings.globalize_path(TMP_DIR)
	var d: DirAccess = DirAccess.open(tmp_abs)
	if d != null:
		for f2 in d.get_files():
			DirAccess.remove_absolute(tmp_abs + "/" + f2)
	DirAccess.remove_absolute(tmp_abs)

func _restore_or_delete(path: String, backup: Variant) -> void:
	if backup == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(str(backup))
		f.close()
