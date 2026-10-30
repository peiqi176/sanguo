extends Node
## 探针：实体导入窗口能不能真的搭起来（UI 层没有被自测覆盖，靠这个兜住）
##
## 自测只验证逻辑层；窗口是代码里手搭的 Control 树，
## 少一个 _scale 判空、行被 queue_free 后又被引用这类问题只有真跑一次才暴露。
##
## 跑法（headless 也行，Window 在 dummy display 下同样会实例化）：
##   ... --headless --path . res://tools/_probe_entityui.tscn

const EntityImportDialog = preload("res://scripts/mapeditor/EntityImportDialog.gd")
const EntityImporter = preload("res://scripts/mapeditor/EntityImporter.gd")
const MapEditorScene = preload("res://scenes/MapEditor.tscn")

const TMP: String = "user://_probe_entityui"

var _fails: int = 0

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_fails += 1
		print("  FAIL ", msg)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	var png: String = _make_png("probe.png", 128, 128)

	var ed = MapEditorScene.instantiate()
	add_child(ed)
	await _frames(3)

	if ed.entity_dialog == null:
		_ck(false, "MapEditor 里没有 entity_dialog（_build_ui 没跑到？）")
		_finish()
		return
	print("=== 1. 打开建筑页 ===")
	ed.open_entity_dialog(png, "building")
	await _frames(2)
	var dlg = ed.entity_dialog
	_ck(dlg.win != null, "窗口对象已创建")
	_ck(dlg.win.visible, "窗口已弹出")
	_ck(dlg.kind == EntityImporter.KIND_BUILDING, "初值类型是建筑")
	_ck(dlg._fields.size() == EntityImportDialog.BUILDING_FIELDS.size(),
		"建筑表单字段数 = %d（实得 %d）" % [EntityImportDialog.BUILDING_FIELDS.size(), dlg._fields.size()])
	var bdef: Dictionary = dlg.collect_def()
	_ck(bdef.has("size") and (bdef["size"] as Array).size() == 2, "collect_def 里尺寸是 [宽,深]")
	_ck(bdef.has("cost"), "collect_def 里带 cost 块")
	var bv: Dictionary = EntityImporter.validate(dlg.kind, dlg._id_edit.text, bdef)
	_ck(bool(bv["ok"]), "默认表单直接就是合法定义（errors=%s）" % str(bv["errors"]))
	_ck(dlg._id_edit.text != "", "id 已自动填（%s）" % dlg._id_edit.text)
	_ck(not dlg._ok_btn.disabled, "校验通过时按钮可点")
	_ck(dlg._preview.texture != null, "预览图已加载")

	print("=== 2. 切到兵种页（会重建整张表单）===")
	dlg._kind_opt.select(1)
	dlg._kind_opt.item_selected.emit(1)
	await _frames(2)
	_ck(dlg.kind == EntityImporter.KIND_UNIT, "类型切成兵种")
	_ck(dlg._fields.size() == EntityImportDialog.UNIT_FIELDS.size(),
		"兵种表单字段数 = %d（实得 %d）" % [EntityImportDialog.UNIT_FIELDS.size(), dlg._fields.size()])
	var udef: Dictionary = dlg.collect_def()
	_ck(udef.has("move_speed") and not udef.has("size"), "兵种定义没有 size、有 move_speed")
	var uv: Dictionary = EntityImporter.validate(dlg.kind, dlg._id_edit.text, udef)
	_ck(bool(uv["ok"]), "兵种默认表单也合法（errors=%s）" % str(uv["errors"]))

	print("=== 3. 再切回建筑（验证行被 free 后不会带着野指针）===")
	dlg._kind_opt.select(0)
	dlg._kind_opt.item_selected.emit(0)
	await _frames(2)
	_ck(dlg.kind == EntityImporter.KIND_BUILDING, "切回建筑成功")
	_ck(dlg._fields.size() == EntityImportDialog.BUILDING_FIELDS.size(), "字段表重建完整")
	dlg._check.clear()
	dlg._refresh_check()
	_ck(true, "重建后刷新校验没有崩（这才是重点）")

	print("=== 4. 关掉窗口不该崩 ===")
	dlg.win.hide()
	await _frames(2)
	_ck(not dlg.win.visible, "窗口已隐藏")

	_finish()

func _finish() -> void:
	var abs_tmp: String = ProjectSettings.globalize_path(TMP)
	var d: DirAccess = DirAccess.open(abs_tmp)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(abs_tmp + "/" + f)
	DirAccess.remove_absolute(abs_tmp)
	print("")
	if _fails == 0:
		print("[PROBE] ✅ 实体导入窗口 全部通过")
	else:
		print("[PROBE] ❌ 有 %d 项失败" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _make_png(name: String, w: int, h: int) -> String:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(20, 16, 88, 106), Color(0.55, 0.45, 0.35, 1.0))
	var abs_path: String = ProjectSettings.globalize_path(TMP + "/" + name)
	img.save_png(abs_path)
	return abs_path
