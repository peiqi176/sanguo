extends Node
## 截图：编辑器里的「导入建筑 / 兵种」长什么样
##
## 出两张：
##   docs/shot_entity_dialog.png   —— 导入窗口（属性表单全貌）
##   docs/shot_palette_custom.png  —— 导入完成后调色板里多出来的那一项
##
## 跑法（必须带窗口，headless 拍不到 UI）：
##   ... --path . res://tools/_shot_editor_import.tscn

const EntityImporter = preload("res://scripts/mapeditor/EntityImporter.gd")
const MapEditorScene = preload("res://scenes/MapEditor.tscn")

const BID: String = "zz_shot_watchtower"
const TMP: String = "user://_shot_editor"

var _ed = null
var _png: String = ""

func _ready() -> void:
	# 默认子窗口是独立 OS 窗口，抓不到主 viewport；嵌进来才能一起截
	get_window().gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	_png = _make_png()

	_ed = MapEditorScene.instantiate()
	add_child(_ed)
	await _f(10)
	print("[SHOT] 编辑器就绪")

	# ── A. 导入窗口
	_ed.open_entity_dialog(_png, "building")
	await _f(6)
	var dlg = _ed.entity_dialog
	if dlg == null:
		print("[SHOT] ❌ 没有 entity_dialog")
		get_tree().quit(1)
		return
	dlg._name_edit.text = "望楼"
	await _f(1)
	dlg._id_edit.text = BID
	if dlg._fields.has("hp"):
		dlg._fields["hp"].value = 900
	if dlg._fields.has("cost_wood"):
		dlg._fields["cost_wood"].value = 180
	if dlg._fields.has("cost_gold"):
		dlg._fields["cost_gold"].value = 40
	if dlg._fields.has("size_x"):
		dlg._fields["size_x"].value = 2
	if dlg._fields.has("size_y"):
		dlg._fields["size_y"].value = 2
	await _f(4)
	dlg._refresh_check()
	await _f(2)
	await _shot("res://docs/shot_entity_dialog.png")
	dlg.win.hide()
	await _f(3)

	# ── 真的导进去，再拍调色板
	var def: Dictionary = EntityImporter.default_building_def("望楼", Vector2i(2, 2))
	def["hp"] = 900
	def["cost"] = {"wood": 180, "gold": 40}
	var r: Dictionary = EntityImporter.import_entity(_png, EntityImporter.KIND_BUILDING, BID, def, 2.4)
	print("[SHOT] 导入结果：", r.get("message", ""))

	_ed.palette.refresh()
	_ed.palette._set_cat("building")
	await _f(3)
	_ed.palette.search_edit.text = "望楼"
	# LineEdit 只有"用户输入"才发 text_changed，代码赋值不发 ——
	# 这里必须手动刷一次，否则截出来的还是全表（写截图脚本时踩过）
	_ed.palette._refresh_list()
	await _f(4)
	await _shot("res://docs/shot_palette_custom.png")

	# ── 清理
	EntityImporter.remove_entity(EntityImporter.KIND_BUILDING, BID)
	var sp: String = "res://assets/sprites/%s.png" % BID
	if FileAccess.file_exists(sp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sp))
	_cleanup_tmp()
	print("[SHOT] ✅ 完成")
	get_tree().quit(0)

# ---------------------------------------------------------------- 工具

func _f(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(ProjectSettings.globalize_path(path))
	print("[SHOT] %s（%dx%d，错误码 %d）" % [path, img.get_width(), img.get_height(), err])

func _make_png() -> String:
	var w: int = 192
	var h: int = 320
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 一个"塔"的剪影：底座 + 塔身 + 檐口，够看出透明底和贴地位置
	img.fill_rect(Rect2i(40, 268, 112, 34), Color(0.42, 0.36, 0.30, 1.0))
	img.fill_rect(Rect2i(58, 96, 76, 176), Color(0.58, 0.50, 0.40, 1.0))
	img.fill_rect(Rect2i(36, 78, 120, 22), Color(0.30, 0.24, 0.20, 1.0))
	img.fill_rect(Rect2i(72, 44, 48, 36), Color(0.52, 0.44, 0.36, 1.0))
	var abs_path: String = ProjectSettings.globalize_path(TMP + "/watchtower.png")
	img.save_png(abs_path)
	return abs_path

func _cleanup_tmp() -> void:
	var abs_tmp: String = ProjectSettings.globalize_path(TMP)
	var d: DirAccess = DirAccess.open(abs_tmp)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(abs_tmp + "/" + f)
	DirAccess.remove_absolute(abs_tmp)
	# custom 文件若只剩空表就删掉
	for p in [EntityImporter.CUSTOM_UNITS_PATH, EntityImporter.CUSTOM_BUILDINGS_PATH]:
		if not FileAccess.file_exists(p):
			continue
		var fh: FileAccess = FileAccess.open(p, FileAccess.READ)
		var txt: String = fh.get_as_text() if fh != null else ""
		if fh != null:
			fh.close()
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_DICTIONARY:
			var body = parsed.get("units", parsed.get("buildings", {}))
			if typeof(body) == TYPE_DICTIONARY and (body as Dictionary).is_empty():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
