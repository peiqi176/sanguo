extends Node3D
## 素材导入自测（M3-1 / M3-2）：校验规则 + 导入往返 + 缓存刷新
##
## 跑法：
##   Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --quit-after 120 \
##     res://tools/_selftest_assetimport.tscn
##
## 这个用例会**临时**改 config/asset_map.json 并往 assets/sprites/ 拷一张 _selftest_*.png，
## 结束时全部还原（asset_map 从内存备份写回、测试图删除）。断在中途也不会留下垃圾 —
## 新加的图名固定以 _selftest_ 开头，一眼能认出来。

const AssetImporter = preload("res://scripts/mapeditor/AssetImporter.gd")

const TEST_ID: String = "_selftest_crate"
const TEST_PNG: String = "res://assets/sprites/_selftest_crate.png"
const TMP_DIR: String = "user://_selftest_import"

var fails: int = 0
var checks: int = 0
var _map_backup: String = ""

func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)

func _ready() -> void:
	_map_backup = _read_text(AssetImporter.ASSET_MAP_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))

	print("=== 1. 校验：拒绝不该放进来的图 ===")
	_test_validate_reject()

	print("=== 2. 校验：合规图 + 提醒项 ===")
	_test_validate_accept()

	print("=== 3. 导入往返 ===")
	_test_import_roundtrip()

	print("=== 4. 未注册图 / 已注册判定 ===")
	_test_registry()

	_cleanup()
	print("")
	print("[SELFTEST] %d 项检查，%d 项失败" % [checks, fails])
	if fails == 0:
		print("[SELFTEST] ✅ 素材导入全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# ---------------------------------------------------------------- 1

func _test_validate_reject() -> void:
	var v: Dictionary = AssetImporter.validate("")
	check(not bool(v["ok"]), "空路径被拒")
	check(str(v["errors"][0]).contains("没有选择文件"), "空路径原因具体：%s" % str(v["errors"][0]))

	v = AssetImporter.validate("C:/绝对不存在的路径/x.png")
	check(not bool(v["ok"]), "不存在的文件被拒")
	check(str(v["errors"][0]).contains("文件不存在"), "原因含「文件不存在」")

	# 全透明图
	var empty: String = _tmp_png("empty.png", 128, 128, Rect2i(0, 0, 0, 0))
	v = AssetImporter.validate(empty)
	check(not bool(v["ok"]), "全透明图被拒")
	check(str(v["errors"]).contains("完全透明"), "原因含「完全透明」")

	# 太小
	var tiny: String = _tmp_png("tiny.png", 16, 16, Rect2i(2, 2, 8, 8))
	v = AssetImporter.validate(tiny)
	check(not bool(v["ok"]), "16×16 被拒")
	check(str(v["errors"]).contains("尺寸太小"), "原因含「尺寸太小」")

# ---------------------------------------------------------------- 2

func _test_validate_accept() -> void:
	# 正常图：内容占满下方
	var good: String = _tmp_png("good.png", 256, 256, Rect2i(48, 40, 160, 216))
	var v: Dictionary = AssetImporter.validate(good)
	check(bool(v["ok"]), "256² 合规图通过（错误：%s）" % str(v["errors"]))
	check(int(v["info"]["height"]) == 256, "读到高度 256")
	check(float(v["info"]["pad_ratio"]) < 0.01, "底边留白接近 0（实得 %.3f）" % float(v["info"]["pad_ratio"]))
	check((v["warnings"] as Array).is_empty(), "没有多余警告（实得 %s）" % str(v["warnings"]))

	# 底边留白过半 → 只警告不拦
	var floaty: String = _tmp_png("floaty.png", 256, 256, Rect2i(48, 10, 160, 90))
	v = AssetImporter.validate(floaty)
	check(bool(v["ok"]), "留白大的图仍然可导入（警告不拦人）")
	var joined: String = str(v["warnings"])
	check(joined.contains("底边留白"), "警告里点名「底边留白」：%s" % joined)

	# 非正方形 → 提醒
	var wide: String = _tmp_png("wide.png", 320, 160, Rect2i(20, 20, 280, 120))
	v = AssetImporter.validate(wide)
	check(str(v["warnings"]).contains("不是正方形"), "非正方形给出提醒")

# ---------------------------------------------------------------- 3

func _test_import_roundtrip() -> void:
	var src: String = _tmp_png("crate.png", 256, 256, Rect2i(40, 48, 176, 200))

	# id 合法性
	var bad: Dictionary = AssetImporter.import_file(src, "buildings", "Bad-Id", 1.5, false)
	check(not bool(bad["ok"]), "非法 id 被拒")
	check(str(bad["message"]).contains("小写字母"), "原因说明 id 规则：%s" % str(bad["message"]))

	var bad_cat: Dictionary = AssetImporter.import_file(src, "不是分类", "x", 1.5, false)
	check(not bool(bad_cat["ok"]), "未知分类被拒")

	# 正常导入
	var before: int = AssetImporter.category_ids("buildings").size()
	var res: Dictionary = AssetImporter.import_file(src, "buildings", TEST_ID, 1.6, false)
	check(bool(res["ok"]), "导入成功：%s" % str(res["message"]))
	check(FileAccess.file_exists(TEST_PNG), "PNG 已拷进 assets/sprites/")
	check(str(res["sprite"]) == "_selftest_crate.png", "落盘文件名 = 实体 id")

	var after: int = AssetImporter.category_ids("buildings").size()
	check(after == before + 1, "asset_map 多了一条（%d → %d）" % [before, after])

	# asset_map 里的字段
	var adef: Dictionary = DataLoader.get_asset_def("buildings", TEST_ID)
	check(not adef.is_empty(), "DataLoader 已能看到新条目（reload_asset_map 生效）")
	check(is_zero_approx(float(adef.get("offset_y", -1))), "offset_y 写入 0")
	check(absf(float(adef.get("scale", 0)) - 1.6) < 1e-5, "scale 写入 1.6")

	# 关键验收：刚导入（还没有 .import）就能取到纹理 + 算出贴地高度
	var tex: Texture2D = DataLoader.get_sprite_texture("buildings", TEST_ID)
	check(tex != null, "未导入的 PNG 也能取到纹理（运行时解码兜底）")
	if tex != null:
		var anchor: float = DataLoader.get_sprite_anchor_y("buildings", TEST_ID, 1.6)
		var rect: Rect2i = DataLoader.get_sprite_content_rect("buildings", TEST_ID)
		var ps: float = DataLoader.get_sprite_pixel_size("buildings", tex) * 1.6
		var content_bottom: float = anchor - float(tex.get_height()) * ps * 0.5 + float(tex.get_height() - rect.end.y) * ps
		check(absf(content_bottom) < 1e-4, "新图同样满足接地不变量（偏差 %.6f）" % content_bottom)
		check(anchor > 0.0, "新图 anchor 为正（%.4f）" % anchor)

	# 重复导入同 id = 覆盖，不该报错也不该多一条
	var again: Dictionary = AssetImporter.import_file(src, "buildings", TEST_ID, 1.7, false)
	check(bool(again["ok"]), "同 id 再导入 = 覆盖，允许")
	check(str(again["message"]).contains("覆盖"), "提示是「覆盖」而不是「新增」")
	check(AssetImporter.category_ids("buildings").size() == after, "覆盖不会新增条目")

# ---------------------------------------------------------------- 4

func _test_registry() -> void:
	check(AssetImporter.is_registered("_selftest_crate.png"), "新导入的文件被判为已注册")
	# 2026-10-29 起贴片已全部删除（改走 GLB），历史 orphan PNG（3180-1.png 等）不复存在。
	# orphan 机制的判定逻辑改用一张临时落盘、不入映射的探针图验证。
	var probe: String = "res://assets/sprites/_selftest_orphan_probe.png"
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.6, 1.0))
	img.save_png(ProjectSettings.globalize_path(probe))
	var orphans: Array = AssetImporter.orphan_files()
	check(not orphans.has("_selftest_crate.png"), "未注册清单里没有刚导入的图")
	check(orphans.has("_selftest_orphan_probe.png"), "未注册清单能看到新落盘的探针图")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe))
	var orphans2: Array = AssetImporter.orphan_files()
	check(not orphans2.has("_selftest_orphan_probe.png"), "删掉探针图后清单同步更新")

# ---------------------------------------------------------------- 工具

## 造一张测试 PNG：canvas 全透明，在 inner 区域填不透明色
func _tmp_png(name: String, w: int, h: int, inner: Rect2i) -> String:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if inner.size.x > 0 and inner.size.y > 0:
		img.fill_rect(inner, Color(0.55, 0.42, 0.30, 1.0))
	var rel: String = TMP_DIR + "/" + name
	var abs_path: String = ProjectSettings.globalize_path(rel)
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

func _cleanup() -> void:
	# 还原 asset_map.json（内存备份，逐字节还原，不留格式化差异）
	if _map_backup != "":
		var f: FileAccess = FileAccess.open(AssetImporter.ASSET_MAP_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_map_backup)
			f.close()
		DataLoader.reload_asset_map()
		check(DataLoader.get_asset_def("buildings", TEST_ID).is_empty(), "已还原 asset_map.json（测试条目已消失）")

	# 删掉测试拷贝的图
	if FileAccess.file_exists(TEST_PNG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PNG))
	check(not FileAccess.file_exists(TEST_PNG), "已删除测试图 _selftest_crate.png")

	# 清掉临时目录
	var tmp_abs: String = ProjectSettings.globalize_path(TMP_DIR)
	var d: DirAccess = DirAccess.open(tmp_abs)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(tmp_abs + "/" + f)
	DirAccess.remove_absolute(tmp_abs)
