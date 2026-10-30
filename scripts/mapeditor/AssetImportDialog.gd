extends RefCounted
## AssetImportDialog —— 「拖一张 PNG 进来 → 三步变可摆资产」的窗口（M3-1）
##
## 交互只做两件事：
##   1. 实时显示 AssetImporter.validate() 的结论（错误红、警告黄、用量灰）
##   2. 点「导入并注册」→ 拷文件 + 写 asset_map.json + 刷 DataLoader + 刷调色板
##
## 刻意不做的事：
##   · 不自动裁切 / 不自动缩放 —— 素材问题要在源文件里修，这里偷偷改会让人对不上账
##   · 不做批量导入 —— 批量该走 Agnes 生成脚本 + tools/normalize_sprites.py

const AssetImporter = preload("res://scripts/mapeditor/AssetImporter.gd")

var editor = null
var win: Window = null
var path: String = ""

var _preview: TextureRect = null
var _meta: RichTextLabel = null
var _check: RichTextLabel = null
var _cat: OptionButton = null
var _id_edit: LineEdit = null
var _existing: OptionButton = null
var _scale: SpinBox = null
var _ok_btn: Button = null
var _cat_order: Array = []

func _init(ed) -> void:
	editor = ed

# ---------------------------------------------------------------- 打开

func open(path_hint: String) -> void:
	_build()
	path = path_hint
	_refresh_all()
	win.popup_centered(Vector2i(600, 520))

# ---------------------------------------------------------------- 构建

func _build() -> void:
	if win != null:
		return
	win = Window.new()
	win.title = "导入贴图"
	win.exclusive = false
	win.unresizable = false
	win.close_requested.connect(func(): win.hide())
	editor.add_child(win)

	var root: MarginContainer = MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root.add_theme_constant_override(m, 12)
	win.add_child(root)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	root.add_child(vb)

	# ── 上半：预览 + 元信息
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)

	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(180, 180)
	top.add_child(frame)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_preview)

	var rv: VBoxContainer = VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 6)
	top.add_child(rv)

	_meta = RichTextLabel.new()
	_meta.bbcode_enabled = true
	_meta.fit_content = true
	_meta.custom_minimum_size = Vector2(0, 82)
	rv.add_child(_meta)

	_cat = OptionButton.new()
	for cat in AssetImporter.DEFAULT_SCALE.keys():
		_cat_order.append(cat)
		_cat.add_item(str(AssetImporter.CATEGORY_LABELS.get(cat, cat)))
	_cat.item_selected.connect(func(_i: int):
		_refresh_existing()
		_scale.value = float(AssetImporter.DEFAULT_SCALE.get(_current_cat(), 1.0)))
	rv.add_child(_labeled("分类", _cat))

	_existing = OptionButton.new()
	_existing.item_selected.connect(func(i: int):
		if i <= 0:
			_id_edit.text = ""
		else:
			_id_edit.text = str(_existing.get_item_text(i)))
	rv.add_child(_labeled("已有 id", _existing))

	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "新 id，如 warehouse（小写字母/数字/下划线）"
	rv.add_child(_labeled("实体 id", _id_edit))

	_scale = SpinBox.new()
	_scale.min_value = 0.1
	_scale.max_value = 10.0
	_scale.step = 0.05
	_scale.value = 1.5
	rv.add_child(_labeled("缩放", _scale))

	# ── 校验结果
	_check = RichTextLabel.new()
	_check.bbcode_enabled = true
	_check.fit_content = false
	_check.custom_minimum_size = Vector2(0, 110)
	_check.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_check)

	# ── 底部按钮
	var brow: HBoxContainer = HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(brow)

	var cancel: Button = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): win.hide())
	brow.add_child(cancel)

	_ok_btn = Button.new()
	_ok_btn.text = "导入并注册"
	_ok_btn.pressed.connect(_on_import)
	brow.add_child(_ok_btn)

func _labeled(text: String, ctrl: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var l: Label = Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(64, 0)
	row.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ctrl)
	return row

# ---------------------------------------------------------------- 刷新

func _current_cat() -> String:
	var i: int = _cat.selected
	if i < 0 or i >= _cat_order.size():
		return "buildings"
	return str(_cat_order[i])

func _refresh_all() -> void:
	_refresh_preview()
	_refresh_meta()
	_refresh_check()
	_refresh_existing()

func _refresh_preview() -> void:
	if path == "":
		_preview.texture = null
		return
	var abs_path: String = path
	if abs_path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(abs_path)
	var img: Image = Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		_preview.texture = null
		return
	# 预览用缩小图，避免 4096² 的原图撑爆显存
	var pw: int = img.get_width()
	var ph: int = img.get_height()
	var cap: int = 512
	if pw > cap or ph > cap:
		var k: float = float(cap) / float(maxi(pw, ph))
		img.resize(maxi(int(pw * k), 1), maxi(int(ph * k), 1), Image.INTERPOLATE_BILINEAR)
	_preview.texture = ImageTexture.create_from_image(img)

func _refresh_meta() -> void:
	if _meta == null:
		return
	var v: Dictionary = AssetImporter.validate(path)
	var info: Dictionary = v.get("info", {})
	_meta.clear()
	_meta.append_text("[color=#9a9a9a]文件[/color]  %s\n" % path.get_file())
	_meta.append_text("[color=#9a9a9a]尺寸[/color]  %s\n" % str(info.get("size_label", "—")))
	_meta.append_text("[color=#9a9a9a]内容[/color]  %s\n" % str(info.get("content_label", "—")))
	var pad: float = float(info.get("pad_ratio", 0.0)) * 100.0
	var pad_col: String = "#c8c8c8" if pad <= 25.0 else "#e0b040"
	_meta.append_text("[color=#9a9a9a]底边留白[/color]  [color=%s]%.1f%%[/color]\n" % [pad_col, pad])

func _refresh_check() -> void:
	if _check == null:
		return
	var v: Dictionary = AssetImporter.validate(path)
	_check.clear()
	var errs: Array = v.get("errors", [])
	var warns: Array = v.get("warnings", [])
	if errs.is_empty() and warns.is_empty():
		_check.append_text("[color=#6ad06a]✅ 没有发现问题，可以直接导入[/color]")
	for e in errs:
		_check.append_text("[color=#e06060]✖ %s[/color]\n" % str(e))
	for w in warns:
		_check.append_text("[color=#e0b040]⚠ %s[/color]\n" % str(w))
	if _ok_btn != null:
		_ok_btn.disabled = not bool(v.get("ok", false))

func _refresh_existing() -> void:
	if _existing == null:
		return
	_existing.clear()
	_existing.add_item("（新建）")
	for id in AssetImporter.category_ids(_current_cat()):
		_existing.add_item(str(id))
	_existing.select(0)

# ---------------------------------------------------------------- 导入

func _on_import() -> void:
	var id: String = _id_edit.text.strip_edges()
	if id == "":
		_toast("请先填实体 id（新建）或从「已有 id」里选一个（覆盖）")
		return
	var cat: String = _current_cat()
	var res: Dictionary = AssetImporter.import_file(path, cat, id, float(_scale.value), false)
	if bool(res.get("ok", false)):
		_toast("✅ " + str(res.get("message", "")))
		if editor.palette != null:
			editor.palette.refresh()
			editor.palette.focus_cat(cat)
		win.hide()
	else:
		_toast("❌ " + str(res.get("message", "")))

func _toast(msg: String) -> void:
	if editor._ui != null:
		editor._ui.show_toast(msg)
	print("[AssetImporter] ", msg)
