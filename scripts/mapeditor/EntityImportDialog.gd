extends RefCounted
## EntityImportDialog —— 「导入建筑 / 导入兵种」窗口（M3-6）
##
## 和 AssetImportDialog 的区别：
##   那个窗口只回答"这张图挂到哪个已有 id 上"；
##   这个窗口回答"这张图 + 这套数值 = 一个全新的建筑/兵种"，
##   导入完直接出现在调色板里、能摆进地图、进游戏能建造/出战。
##
## 为什么把玩法数值也放在这个窗口里，而不是先导贴图再手改 JSON：
##   少一次"改完 JSON 忘了重启 → 调色板还是旧的"的踩坑；
##   而且 id / 名称 / 尺寸 / 造价 这几项一旦写错，后面很难发现（贴图是对的，行为是错的）。

const EntityImporter = preload("res://scripts/mapeditor/EntityImporter.gd")
const AssetImporter = preload("res://scripts/mapeditor/AssetImporter.gd")

## 字段声明表：key / 显示名 / 范围 / 缺省值 / 单位后缀
## 建筑和兵种各一套，UI 按表生成，加字段只改这里。
const BUILDING_FIELDS: Array = [
	{"key": "size_x", "label": "占地宽", "min": 1, "max": 8, "step": 1, "def": 2, "suffix": "格"},
	{"key": "size_y", "label": "占地深", "min": 1, "max": 8, "step": 1, "def": 2, "suffix": "格"},
	{"key": "hp", "label": "血量", "min": 10, "max": 100000, "step": 10, "def": 600, "suffix": ""},
	{"key": "build_time", "label": "建造时间", "min": 0, "max": 600, "step": 1, "def": 25, "suffix": "秒"},
	{"key": "pop_provide", "label": "人口上限", "min": 0, "max": 100, "step": 1, "def": 0, "suffix": ""},
	{"key": "cost_wood", "label": "造价 · 木", "min": 0, "max": 100000, "step": 10, "def": 120, "suffix": ""},
	{"key": "cost_food", "label": "造价 · 粮", "min": 0, "max": 100000, "step": 10, "def": 0, "suffix": ""},
	{"key": "cost_gold", "label": "造价 · 金", "min": 0, "max": 100000, "step": 10, "def": 0, "suffix": ""},
	{"key": "cost_iron", "label": "造价 · 铁", "min": 0, "max": 100000, "step": 10, "def": 0, "suffix": ""},
]

const UNIT_FIELDS: Array = [
	{"key": "hp", "label": "血量", "min": 1, "max": 100000, "step": 5, "def": 80, "suffix": ""},
	{"key": "atk", "label": "攻击", "min": 0, "max": 9999, "step": 1, "def": 10, "suffix": ""},
	{"key": "def", "label": "防御", "min": 0, "max": 9999, "step": 1, "def": 4, "suffix": ""},
	{"key": "move_speed", "label": "移速", "min": 0.2, "max": 20.0, "step": 0.1, "def": 2.6, "suffix": "m/s"},
	{"key": "atk_speed", "label": "攻速", "min": 0.1, "max": 10.0, "step": 0.1, "def": 1.0, "suffix": "次/秒"},
	{"key": "range", "label": "射程", "min": 0.0, "max": 40.0, "step": 0.1, "def": 0.6, "suffix": "m"},
	{"key": "morale", "label": "士气", "min": 0, "max": 200, "step": 5, "def": 60, "suffix": ""},
	{"key": "pop_cost", "label": "人口", "min": 0, "max": 20, "step": 1, "def": 1, "suffix": ""},
	{"key": "train_time", "label": "训练时间", "min": 0, "max": 600, "step": 1, "def": 20, "suffix": "秒"},
	{"key": "cost_wood", "label": "造价 · 木", "min": 0, "max": 100000, "step": 10, "def": 20, "suffix": ""},
	{"key": "cost_gold", "label": "造价 · 金", "min": 0, "max": 100000, "step": 10, "def": 10, "suffix": ""},
]

var editor = null
var win: Window = null
var path: String = ""
var kind: String = EntityImporter.KIND_BUILDING

var _preview: TextureRect = null
var _meta: RichTextLabel = null
var _check: RichTextLabel = null
var _kind_opt: OptionButton = null
var _cat_opt: OptionButton = null
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _scale: SpinBox = null
var _form: VBoxContainer = null
var _ok_btn: Button = null
var _train_opt: OptionButton = null
var _train_ids: Array = []            # 与 _train_opt 的行一一对应（index 0 = 不训练）
var _auto_id: String = ""             # 上一次自动生成的 id（用户没手改过就跟名称联动）
var _fields: Dictionary = {}          # key → SpinBox
var _field_rows: Array = []           # 生成出来的行，切类型时整批清掉重建

func _init(ed) -> void:
	editor = ed

# ---------------------------------------------------------------- 打开

func open(png_path: String, kind_hint: String = "") -> void:
	_build()
	path = png_path
	if kind_hint != "":
		kind = kind_hint
	_sync_kind_ui()
	_refresh_all()
	# 720×820 是按"兵种页最长（11 个数值 + 训练建筑 + 缩放）"量的：
	# 小一号就会把「取消/导入」按钮顶出窗口底部（实拍踩过）。
	win.popup_centered(Vector2i(720, 700))

# ---------------------------------------------------------------- 构建

func _build() -> void:
	if win != null:
		return
	win = Window.new()
	win.title = "导入建筑 / 兵种"
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

	# ── 顶部：预览 + 图片元信息
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)

	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(160, 160)
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
	_meta.custom_minimum_size = Vector2(0, 78)
	rv.add_child(_meta)

	_kind_opt = OptionButton.new()
	_kind_opt.add_item("建筑")
	_kind_opt.add_item("兵种")
	_kind_opt.item_selected.connect(func(i: int):
		kind = EntityImporter.KIND_BUILDING if i == 0 else EntityImporter.KIND_UNIT
		_sync_kind_ui())
	rv.add_child(_labeled("类型", _kind_opt))

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "显示名，如 望楼 / 连弩兵"
	_name_edit.text_changed.connect(_on_name_changed)
	rv.add_child(_labeled("名称", _name_edit))

	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "实体 id，如 watchtower（小写字母/数字/下划线）"
	_id_edit.text_changed.connect(func(t: String): _refresh_check())
	rv.add_child(_labeled("实体 id", _id_edit))

	# ── 中部：滚动的属性表单
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 4)
	scroll.add_child(_form)

	# ── 校验结果
	_check = RichTextLabel.new()
	_check.bbcode_enabled = true
	_check.fit_content = false
	_check.custom_minimum_size = Vector2(0, 84)
	# 不要 EXPAND：否则多出来的高度全被这块空白吃掉，窗口下半截空一大片
	# （滚动区已经是 EXPAND，空白应该归表单）
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

func _labeled(text: String, ctrl: Control, label_w: int = 76) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var l: Label = Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(label_w, 0)
	row.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ctrl)
	return row

# ---------------------------------------------------------------- 类型切换

## 切类型：重建属性表单 + 换 category 下拉 + 按新类型补一个没被占用的 id
func _sync_kind_ui() -> void:
	if _kind_opt != null:
		_kind_opt.select(0 if kind == EntityImporter.KIND_BUILDING else 1)
	_rebuild_fields()
	_rebuild_category_opt()
	if _name_edit != null and _name_edit.text.strip_edges() == "":
		_name_edit.text = "新" + str(EntityImporter.KIND_LABELS.get(kind, "实体"))
	if _id_edit != null:
		_auto_id = EntityImporter.next_free_id(kind, _ascii_hint(_name_edit.text if _name_edit != null else ""))
		_id_edit.text = _auto_id
	if _scale != null:
		_scale.value = 2.6 if kind == EntityImporter.KIND_BUILDING else 0.85
	_refresh_check()

func _rebuild_fields() -> void:
	if _form == null:
		return
	for r in _field_rows:
		if is_instance_valid(r):
			r.queue_free()
	_field_rows.clear()
	_fields.clear()
	# 子类别下拉和缩放都挂在被重建的行上，必须把引用一起丢掉。
	# 只置空 _cat_opt 不够谨慎不彻底：留着旧引用，下次进来 is null 判断会放过它，
	# 对着一个已 free 的 OptionButton 调 clear() 会直接炸。
	_cat_opt = null
	_scale = null
	_train_opt = null
	_train_ids.clear()

	var defs: Array = BUILDING_FIELDS if kind == EntityImporter.KIND_BUILDING else UNIT_FIELDS
	# 两列网格：兵种有 11 个数值，一列排下来要 340px 高，
	# 窗口再高也放不下（第一次实拍时「贴图缩放」被挤到滚动区外面）。
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_child(grid)
	# 只把 grid 本体记进 _field_rows：子行跟着 grid 一起 free，
	# 再单独 free 子行会撞上 "Attempted to free a freed object"。
	_field_rows.append(grid)

	for d in defs:
		var sp: SpinBox = SpinBox.new()
		sp.min_value = float(d["min"])
		sp.max_value = float(d["max"])
		sp.step = float(d["step"])
		sp.value = float(d["def"])
		sp.custom_minimum_size = Vector2(120, 0)
		sp.value_changed.connect(func(_v: float): _refresh_check())
		var row: HBoxContainer = _labeled(str(d["label"]), sp, 62)
		var suffix: String = str(d.get("suffix", ""))
		if suffix != "":
			var sl: Label = Label.new()
			sl.text = suffix
			sl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.62))
			row.add_child(sl)
		grid.add_child(row)
		_fields[str(d["key"])] = sp

	# 训练建筑：只有兵种需要。不挂的话这个兵进游戏后没有任何地方能造出来，
	# 只能在地图编辑器里摆着 —— 所以默认给刀兵营，而不是留空让人踩坑。
	if kind == EntityImporter.KIND_UNIT:
		_train_opt = OptionButton.new()
		_train_ids = []
		_train_opt.add_item("不训练（只能在地图编辑器里摆）")
		var list: Array = EntityImporter.trainable_buildings()
		var def_pick: int = 0
		for it in list:
			_train_opt.add_item("%s（%s）" % [str(it["name"]), str(it["id"])])
			_train_ids.append(str(it["id"]))
		for i in range(_train_ids.size()):
			if str(_train_ids[i]) == "barracks_sword":
				def_pick = i + 1
		_train_opt.select(def_pick)
		_train_opt.item_selected.connect(func(_i: int): _refresh_check())
		_form.add_child(_labeled("由谁训练", _train_opt))
		_field_rows.append(_train_opt.get_parent())

	# 缩放：不放进字段表，因为它属于"美术"而不是"玩法"
	_scale = SpinBox.new()
	_scale.min_value = 0.1
	_scale.max_value = 10.0
	_scale.step = 0.05
	_scale.value = 2.6 if kind == EntityImporter.KIND_BUILDING else 0.85
	var srow: HBoxContainer = _labeled("贴图缩放", _scale)
	var hint: Label = Label.new()
	hint.text = "1.0 ≈ 贴图 1px 当 1cm"
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	srow.add_child(hint)
	_form.add_child(srow)
	_field_rows.append(srow)

func _rebuild_category_opt() -> void:
	if _cat_opt == null:
		_cat_opt = OptionButton.new()
		_cat_opt.item_selected.connect(func(_i: int): _refresh_check())
		var row: HBoxContainer = _labeled("子类别", _cat_opt)
		# 插到 _form 的第 0 行之后（尺寸等字段之前看起来更顺）
		_form.add_child(row)
		_form.move_child(row, 0)
		_field_rows.append(row)
	_cat_opt.clear()
	var cats: Array = EntityImporter.BUILDING_CATEGORIES if kind == EntityImporter.KIND_BUILDING else EntityImporter.UNIT_CATEGORIES
	var labels: Dictionary = EntityImporter.BUILDING_CATEGORY_LABELS if kind == EntityImporter.KIND_BUILDING else EntityImporter.UNIT_CATEGORY_LABELS
	for c in cats:
		_cat_opt.add_item("%s（%s）" % [str(labels.get(c, c)), c])
	_cat_opt.select(0)

func _current_category() -> String:
	var cats: Array = EntityImporter.BUILDING_CATEGORIES if kind == EntityImporter.KIND_BUILDING else EntityImporter.UNIT_CATEGORIES
	var i: int = _cat_opt.selected if _cat_opt != null else 0
	if i < 0 or i >= cats.size():
		return str(cats[0])
	return str(cats[i])

# ---------------------------------------------------------------- 收集定义

## 把界面上的字段拼回一个 def（结构同 units.json / buildings.json 里的条目）
func collect_def() -> Dictionary:
	var d: Dictionary = {
		"name": _name_edit.text.strip_edges() if _name_edit != null else "",
		"category": _current_category(),
		"cost": {},
	}
	var cost: Dictionary = {}
	for k in _fields.keys():
		var key: String = str(k)
		var val: float = float((_fields[k] as SpinBox).value)
		if key.begins_with("cost_"):
			if val > 0.0:
				cost[key.substr(5)] = int(round(val))
		else:
			d[key] = val
	d["cost"] = cost

	if kind == EntityImporter.KIND_BUILDING:
		d["size"] = [int(d.get("size_x", 2)), int(d.get("size_y", 2))]
		d.erase("size_x")
		d.erase("size_y")
		d["pop_provide"] = int(d.get("pop_provide", 0))
	else:
		d["pop_cost"] = int(d.get("pop_cost", 1))
		var ti: int = _train_opt.selected if _train_opt != null else 0
		var tf: Array = []
		if ti > 0 and ti - 1 < _train_ids.size():
			tf.append(str(_train_ids[ti - 1]))
		d["train_from"] = tf
	return d

# ---------------------------------------------------------------- 刷新

func _refresh_all() -> void:
	_refresh_preview()
	_refresh_meta()
	_refresh_check()

func _refresh_preview() -> void:
	if _preview == null:
		return
	if path == "":
		_preview.texture = null
		return
	var abs_path: String = path
	if abs_path.begins_with("res://") or abs_path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(abs_path)
	var img: Image = Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		_preview.texture = null
		return
	# 预览用缩略图，4096² 的原图直接塞给 TextureRect 会瞬间吃掉几百 MB
	var cap: int = 480
	var pw: int = img.get_width()
	var ph: int = img.get_height()
	if pw > cap or ph > cap:
		var k: float = float(cap) / float(maxi(pw, ph))
		img.resize(maxi(int(pw * k), 1), maxi(int(ph * k), 1), Image.INTERPOLATE_BILINEAR)
	_preview.texture = ImageTexture.create_from_image(img)

func _refresh_meta() -> void:
	if _meta == null:
		return
	var info: Dictionary = AssetImporter.validate(path).get("info", {})
	_meta.clear()
	_meta.append_text("[color=#9a9a9a]文件[/color]  %s\n" % (path.get_file() if path != "" else "（未选择）"))
	_meta.append_text("[color=#9a9a9a]尺寸[/color]  %s\n" % str(info.get("size_label", "—")))
	_meta.append_text("[color=#9a9a9a]内容[/color]  %s\n" % str(info.get("content_label", "—")))
	_meta.append_text("[color=#9a9a9a]底边留白[/color]  %.1f%%\n" % (float(info.get("pad_ratio", 0.0)) * 100.0))

func _refresh_check() -> void:
	if _check == null:
		return
	_check.clear()

	# ① 图片本身的问题
	var v: Dictionary = AssetImporter.validate(path)
	var img_errs: Array = v.get("errors", [])
	var img_warns: Array = v.get("warnings", [])

	# ② 定义的问题
	var dv: Dictionary = EntityImporter.validate(kind, _id_edit.text if _id_edit != null else "", collect_def())
	var def_errs: Array = dv.get("errors", [])
	var def_warns: Array = dv.get("warnings", [])

	var all_err: int = img_errs.size() + def_errs.size()
	if all_err == 0 and img_warns.is_empty() and def_warns.is_empty():
		_check.append_text("[color=#6ad06a]✅ 图片和属性都没问题，可以导入[/color]\n")
	for e in img_errs:
		_check.append_text("[color=#e06060]✖ 图片：%s[/color]\n" % str(e))
	for e in def_errs:
		_check.append_text("[color=#e06060]✖ 定义：%s[/color]\n" % str(e))
	for w in img_warns:
		# 建筑立绘天生是竖长方形（塔、望楼、城门），"不是正方形"这条只对单位有意义，
		# 而且文案里"会左右不对称"对 Sprite3D 也不成立 —— 这里直接咽掉，别烦人。
		if kind == EntityImporter.KIND_BUILDING and str(w).contains("不是正方形"):
			continue
		_check.append_text("[color=#e0b040]⚠ 图片：%s[/color]\n" % str(w))
	for w in def_warns:
		_check.append_text("[color=#e0b040]⚠ 定义：%s[/color]\n" % str(w))
	if all_err == 0:
		var id: String = (_id_edit.text if _id_edit != null else "").strip_edges()
		var verb: String = "覆盖自建" if EntityImporter.is_custom(kind, id) else "新增"
		_check.append_text("[color=#8ab4e8]→ 将%s%s「%s」，导入后直接出现在调色板里[/color]\n" % [
			verb, str(EntityImporter.KIND_LABELS.get(kind, "实体")),
			_name_edit.text.strip_edges() if _name_edit != null else ""])

	if _ok_btn != null:
		_ok_btn.disabled = all_err > 0

# ---------------------------------------------------------------- 导入

func _on_import() -> void:
	var id: String = _id_edit.text.strip_edges() if _id_edit != null else ""
	var res: Dictionary = EntityImporter.import_entity(path, kind, id, collect_def(),
		float(_scale.value) if _scale != null else -1.0)
	if bool(res.get("ok", false)):
		_toast("✅ " + str(res.get("message", "")))
		if editor.palette != null:
			editor.palette.refresh()
			editor.palette.focus_cat(str(EntityImporter.ASSET_CAT[kind]))
		# 导入完把 id 换成下一个空位，方便连着导第二个（同一张图换个数值就是新兵种）
		var next: String = EntityImporter.next_free_id(kind, _ascii_hint(_name_edit.text))
		_id_edit.text = next
		_refresh_check()
	else:
		_toast("❌ " + str(res.get("message", "")))

func _toast(msg: String) -> void:
	if editor != null and editor._ui != null:
		editor._ui.show_toast(msg)
	print("[EntityImporter] ", msg)

# ---------------------------------------------------------------- 内部

## 名称变化时，如果 id 还停在上一次"自动生成"的值上，就跟着名称走；
## 用户一旦手动改过 id（值不等于 _auto_id），就再也不去覆盖它 ——
## 自动改用户手填的东西是最招人烦的一类"贴心"。
func _on_name_changed(_t: String) -> void:
	if _id_edit != null and _id_edit.text == _auto_id:
		_auto_id = EntityImporter.next_free_id(kind, _ascii_hint(_name_edit.text))
		_id_edit.text = _auto_id
	_refresh_check()

## 中文名转 id 提示：非 ASCII 一律丢掉，剩下的拼一个可用的英文骨架。
## "望楼" → ""（所以会落到 custom_building），"Archer2" → "archer2"。
func _ascii_hint(name: String) -> String:
	var out: String = ""
	for i in range(name.length()):
		var ch: String = name[i]
		var low: String = ch.to_lower()
		if (low >= "a" and low <= "z") or (low >= "0" and low <= "9") or low == "_":
			out += low
		elif ch == " " or ch == "-":
			out += "_"
	return out.substr(0, 32)
