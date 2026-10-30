extends RefCounted
## EditorUI —— 地图工坊的 UI 外壳（2026-10-29 重构：Excel 式 Ribbon 菜单栏）
##
## 版式（用户口径：地形 4 工具一块、地质一块、道路/草种可选、参考 Excel 菜单栏）：
##   ┌──────────────────────────────────────────────────────┐
##   │ [地形][地质][道路][物件][文件]      地图名 ● 撤销 重做 保存 试玩 │ ← 页签行
##   │ ┌─高度笔刷──┐ ┌─笔刷参数──┐ ┌─提示──┐                       │ ← 功能区（随页签换）
##   └──────────────────────────────────────────────────────┘
##   页签内容：
##     地形 = 高度笔刷（抬升/下压/平滑/平台）+ 笔刷参数
##     地质 = 草地（自动 + 5 草种）+ 地表层（沙/泥/岩/林）+ 笔刷参数
##     道路 = 石板路（自动 + 5 石种）+ 土路
##     物件 = 模式切换 + 右栏开合
##     文件 = 地图名 / 阵营 / 相机锁
##   状态条（左下）：当前笔刷 · 光标坐标 · toast
##
## 约定：EditorUI 直接读改 editor 的公开字段（brush_radius 等），不持有副本。
## 页签切换会重建控件，所有"可空引用"（radius_slider 等）在别的页签下是 null，
## 状态同步函数一律判空。

var editor = null            # MapEditor（弱类型，避免循环 preload）

const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")
const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")

## 阵营下拉的可选项（id 必须和 config/factions.json 里的对得上）
const OWNERS: Array = [
	{"id": "shu", "label": "蜀"},
	{"id": "wei", "label": "魏"},
	{"id": "wu", "label": "吴"},
	{"id": "neutral", "label": "中立"},
]

## Ribbon 页签定义（顺序 = 显示顺序）
const RIBBON_TABS: Array = [
	{"id": "terrain", "label": "地形"},
	{"id": "ground", "label": "地质"},
	{"id": "road", "label": "道路"},
	{"id": "object", "label": "物件"},
	{"id": "file", "label": "文件"},
]

# ---- 页签与功能区（随页签重建）----
var _tab_buttons: Array = []       # [{id, btn}]
var _active_tab: String = ""
var _tab_box: HBoxContainer = null

# ---- 功能区控件（仅当前页签存在；切页签后变 null）----
var mode_buttons: Array = []       # 高度笔刷 4 档按钮
var layer_buttons: Array = []      # [{layer, btn}] 全部作用层按钮
var variant_buttons: Array = []    # [{variant, layer, btn}] 变种按钮
var radius_slider: HSlider = null
var strength_slider: HSlider = null
var radius_val: Label = null
var strength_val: Label = null
var name_edit: LineEdit = null
var owner_option: OptionButton = null
var lock_btn: CheckButton = null

# ---- 页签行常驻控件 ----
var doc_label: Label = null
var undo_btn: Button = null
var redo_btn: Button = null

# ---- 左下状态条 ----
var mode_label: Label = null
var pos_label: Label = null
var toast_label: Label = null

## 右侧栏容器：留给调色板（M1-8）和检查器（M1-9）往里填
var right_host: VBoxContainer = null

var _toast_t: float = 0.0

func _init(ed) -> void:
	editor = ed

# ---------------------------------------------------------------- 构建

func build(parent: Node) -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	parent.add_child(layer)
	_build_ribbon(layer)
	_build_status(layer)
	_build_right_host(layer)
	_show_tab("terrain")
	# 初始状态同步（页签建好之后再刷一遍高亮与文案）
	set_mode_text(editor.mode)
	set_paint_layer(editor.paint_layer)
	set_paint_variant(editor.paint_variant)
	set_doc_text("—")

# ---------------------------------------------------------------- Ribbon

func _build_ribbon(layer: CanvasLayer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.offset_left = 8.0
	panel.offset_right = -8.0
	panel.offset_top = 8.0
	panel.grow_vertical = Control.GROW_DIRECTION_END
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.115, 0.125, 0.145, 0.96)
	sb.border_color = Color(0.30, 0.33, 0.38)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	# ---- 第一行：页签 + 常驻操作 ----
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	vb.add_child(row)

	var tgroup := ButtonGroup.new()
	for td in RIBBON_TABS:
		var b: Button = Button.new()
		b.text = str(td["label"])
		b.toggle_mode = true
		b.button_group = tgroup
		b.flat = true
		b.add_theme_font_size_override("font_size", 15)
		var tid: String = str(td["id"])
		b.pressed.connect(func() -> void: _show_tab(tid))
		row.add_child(b)
		_tab_buttons.append({"id": tid, "btn": b})

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	doc_label = Label.new()
	doc_label.text = "—"
	doc_label.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68))
	row.add_child(doc_label)

	undo_btn = Button.new()
	undo_btn.text = "撤销"
	undo_btn.tooltip_text = "Ctrl+Z"
	undo_btn.disabled = true
	undo_btn.pressed.connect(func() -> void: editor._undo())
	row.add_child(undo_btn)

	redo_btn = Button.new()
	redo_btn.text = "重做"
	redo_btn.tooltip_text = "Ctrl+Y"
	redo_btn.disabled = true
	redo_btn.pressed.connect(func() -> void: editor._redo())
	row.add_child(redo_btn)

	var save_btn: Button = Button.new()
	save_btn.text = "保存"
	save_btn.tooltip_text = "Ctrl+S"
	save_btn.pressed.connect(func() -> void: editor._save_map(""))
	row.add_child(save_btn)

	var play_btn: Button = Button.new()
	play_btn.text = "试玩 ▶"
	play_btn.tooltip_text = "F5：保存后直接进游戏，跑的就是这张图"
	play_btn.pressed.connect(func() -> void: editor._save_and_play())
	row.add_child(play_btn)

	vb.add_child(HSeparator.new())

	# ---- 第二行：当前页签的功能区 ----
	_tab_box = HBoxContainer.new()
	_tab_box.add_theme_constant_override("separation", 16)
	vb.add_child(_tab_box)

## 切换页签：清空功能区重建（控件引用随之换新，旧引用全部作废）
func _show_tab(tab_id: String) -> void:
	_active_tab = tab_id
	for tb in _tab_buttons:
		var btn: Button = tb["btn"]
		btn.set_pressed_no_signal(str(tb["id"]) == tab_id)
	for c in _tab_box.get_children():
		c.queue_free()
	mode_buttons.clear()
	layer_buttons.clear()
	variant_buttons.clear()
	radius_slider = null
	strength_slider = null
	radius_val = null
	strength_val = null
	name_edit = null
	owner_option = null
	lock_btn = null
	match tab_id:
		"terrain":
			_build_tab_terrain()
		"ground":
			_build_tab_ground()
		"road":
			_build_tab_road()
		"object":
			_build_tab_object()
		"file":
			_build_tab_file()
	# 重建后按当前状态补高亮
	_sync_mode_buttons()
	_sync_layer_buttons()
	_sync_variant_buttons()

## 功能区里的一个"组"：带标题小字 + 竖分隔线（Excel Ribbon 组样式）
func _group(title: String) -> VBoxContainer:
	var g: VBoxContainer = VBoxContainer.new()
	g.add_theme_constant_override("separation", 4)
	var cap: Label = Label.new()
	cap.text = title
	cap.add_theme_color_override("font_color", Color(0.52, 0.72, 0.95))
	cap.add_theme_font_size_override("font_size", 12)
	g.add_child(cap)
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	g.add_child(body)
	g.set_meta("body", body)
	_tab_box.add_child(g)
	var sep: VSeparator = VSeparator.new()
	_tab_box.add_child(sep)
	return g

func _group_body(g: VBoxContainer) -> HBoxContainer:
	return g.get_meta("body") as HBoxContainer

# ---------------------------------------------------------------- 页签内容

func _build_tab_terrain() -> void:
	# —— 高度笔刷（1~4）：地形 4 工具独立一块 ——
	var g1: VBoxContainer = _group("高度笔刷（1~4）")
	var mrow: HBoxContainer = HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 4)
	_group_body(g1).add_child(mrow)
	mode_buttons.clear()
	var mgroup := ButtonGroup.new()   # 独立于作用层组：层与模式是两件事，各自有高亮
	var mdefs: Array = [
		{"mode": TerrainBrush.Mode.RAISE, "label": "抬升", "tip": "1：升高地形"},
		{"mode": TerrainBrush.Mode.LOWER, "label": "下压", "tip": "2：压低地形（压到水位下成河）"},
		{"mode": TerrainBrush.Mode.SMOOTH, "label": "平滑", "tip": "3：抹平起伏"},
		{"mode": TerrainBrush.Mode.FLATTEN, "label": "平台", "tip": "4：压成起笔点高度（建城用地基）"},
	]
	for md in mdefs:
		var mb: Button = Button.new()
		mb.text = str(md["label"])
		mb.tooltip_text = str(md["tip"])
		mb.toggle_mode = true
		mb.button_group = mgroup
		mb.custom_minimum_size = Vector2(64, 0)
		var mv: int = int(md["mode"])
		mb.pressed.connect(func() -> void:
			editor.set_tool_mode(editor.Tool.TERRAIN)
			editor._set_paint_layer(-1)
			editor._set_mode(mv))
		mode_buttons.append(mb)
		mrow.add_child(mb)

	# —— 笔刷参数 ——
	var g2: VBoxContainer = _group("笔刷参数")
	_add_brush_sliders(_group_body(g2))

	# —— 提示 ——
	var g3: VBoxContainer = _group("提示")
	_add_hint(_group_body(g3), "WASD 平移 · Q/E 旋转 · 滚轮缩放\n左键拖动 = 用当前笔刷")

func _build_tab_ground() -> void:
	# —— 草地：自动 + 5 草种（点草种自动切到草地层）——
	var g1: VBoxContainer = _group("草地（G）")
	var grow: HBoxContainer = HBoxContainer.new()
	grow.add_theme_constant_override("separation", 4)
	_group_body(g1).add_child(grow)
	var vgroup := ButtonGroup.new()
	_add_variant_button(grow, vgroup, -1, SplatBrush.LAYER_GRASS, "自动",
			"擦掉手选草种，恢复程序噪声分带（犬牙交错的天然草甸）")
	for gv in SplatBrush.GRASS_VARIANTS:
		_add_variant_button(grow, vgroup, int(gv["id"]), SplatBrush.LAYER_GRASS,
				str(gv["label"]), str(gv["tip"]))

	# —— 地表层：沙/泥/岩/林 ——
	var g2: VBoxContainer = _group("地表（5~8）")
	var lrow: HBoxContainer = HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 4)
	_group_body(g2).add_child(lrow)
	var lgroup := ButtonGroup.new()
	_add_layer_button(lrow, lgroup, SplatBrush.Layer.SAND, "沙地", "5：刷沙地（河滩/沙洲/戈壁）")
	_add_layer_button(lrow, lgroup, SplatBrush.Layer.DIRT, "泥土", "6：刷泥土（庭院/耕地边缘）")
	_add_layer_button(lrow, lgroup, SplatBrush.Layer.ROCK, "岩石", "7：刷裸岩（矿坑/崖脚/乱石滩）")
	_add_layer_button(lrow, lgroup, SplatBrush.Layer.FOREST, "林地", "8：刷森林地被（林下腐叶/苔藓）")

	# —— 笔刷参数 ——
	var g3: VBoxContainer = _group("笔刷参数")
	_add_brush_sliders(_group_body(g3))

	# —— 提示 ——
	var g4: VBoxContainer = _group("提示")
	_add_hint(_group_body(g4), "按住 Shift 拖动 = 擦除（恢复程序群系）")

func _build_tab_road() -> void:
	# —— 石板路：自动 + 5 石种（点石种自动切到石板路层；131 长苔石自动贴路缘）——
	var g1: VBoxContainer = _group("石板路（9）")
	var prow: HBoxContainer = HBoxContainer.new()
	prow.add_theme_constant_override("separation", 4)
	_group_body(g1).add_child(prow)
	var vgroup := ButtonGroup.new()
	_add_variant_button(prow, vgroup, -1, SplatBrush.Layer.PAVED, "自动",
			"多种石板按世界噪声自动分段混铺，路段之间不重样")
	for pv in SplatBrush.PAVED_VARIANTS:
		_add_variant_button(prow, vgroup, int(pv["id"]), SplatBrush.Layer.PAVED,
				str(pv["label"]), str(pv["tip"]))

	# —— 土路：无变种，三段式路肩自动补 ——
	var g2: VBoxContainer = _group("土路（0）")
	var rrow: HBoxContainer = HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 4)
	_group_body(g2).add_child(rrow)
	var lgroup := ButtonGroup.new()
	_add_layer_button(rrow, lgroup, SplatBrush.Layer.ROAD, "土路",
			"0：乡道/田间小径（两侧自动补泥土路肩）")

	# —— 提示 ——
	var g3: VBoxContainer = _group("提示")
	_add_hint(_group_body(g3), "长苔石板不用选：路缘权重越高苔越多\nShift 拖动 = 擦除道路与路肩")

func _build_tab_object() -> void:
	# —— 模式 ——
	var g1: VBoxContainer = _group("模式")
	var mrow: HBoxContainer = HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 4)
	_group_body(g1).add_child(mrow)
	var sel: Button = Button.new()
	sel.text = "选择 / 移动"
	sel.tooltip_text = "V：点选对象，Delete 删除"
	sel.pressed.connect(func() -> void: editor.set_tool_mode(editor.Tool.SELECT))
	mrow.add_child(sel)
	var back: Button = Button.new()
	back.text = "返回地形笔刷"
	back.tooltip_text = "Esc：回到地形编辑"
	back.pressed.connect(func() -> void: editor.set_tool_mode(editor.Tool.TERRAIN))
	mrow.add_child(back)

	# —— 右栏 ——
	var g2: VBoxContainer = _group("物件面板")
	var tgl: Button = Button.new()
	tgl.text = "显示 / 隐藏右栏"
	tgl.tooltip_text = "右侧调色板：树/岩石/装饰/建筑/单位 → 左键落位"
	tgl.pressed.connect(func() -> void:
		if right_host != null:
			right_host.visible = not right_host.visible)
	_group_body(g2).add_child(tgl)

	# —— 提示 ——
	var g3: VBoxContainer = _group("提示")
	_add_hint(_group_body(g3), "右栏调色板选物件 → 地图上左键放置\n右键取消 · 放置阵营在「文件」页签")

func _build_tab_file() -> void:
	# —— 地图 ——
	var g1: VBoxContainer = _group("地图")
	var frow: HBoxContainer = HBoxContainer.new()
	frow.add_theme_constant_override("separation", 6)
	_group_body(g1).add_child(frow)

	var nl: Label = Label.new()
	nl.text = "地图名"
	frow.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.text = str(editor.doc.map_name) if editor.doc != null else "自定义地图"
	name_edit.custom_minimum_size = Vector2(160, 0)
	frow.add_child(name_edit)

	var ol: Label = Label.new()
	ol.text = "绘制阵营"
	frow.add_child(ol)
	owner_option = OptionButton.new()
	for f in OWNERS:
		owner_option.add_item(str(f["label"]))
	owner_option.item_selected.connect(func(i: int) -> void:
		var idx: int = clampi(i, 0, OWNERS.size() - 1)
		editor.paint_owner = str(OWNERS[idx]["id"]))
	frow.add_child(owner_option)

	lock_btn = CheckButton.new()
	lock_btn.text = "锁定相机（2.5D）"
	lock_btn.tooltip_text = "锁定俯视角与朝向，和游戏内一致"
	lock_btn.toggled.connect(func(on: bool) -> void:
		if editor.cam_ctrl != null and editor.cam_ctrl.has_method("set_yaw_lock"):
			editor.cam_ctrl.pitch_locked = on
			editor.cam_ctrl.set_yaw_lock(on, 0.0, 360.0))
	frow.add_child(lock_btn)

	# —— 快捷键 ——
	var g2: VBoxContainer = _group("快捷键")
	_add_hint(_group_body(g2),
			"1~4 高度 · 5~8 地表 · 9 石板路 · 0 土路 · G 草地\nCtrl+Z 撤销 · Ctrl+Y 重做 · Ctrl+S 保存 · F5 试玩")

# ---------------------------------------------------------------- 控件工厂

## 作用层按钮（沙/泥/岩/林/土路；石板路走变种组）
func _add_layer_button(row: HBoxContainer, group: ButtonGroup, layer: int,
		label: String, tip: String) -> void:
	var b: Button = Button.new()
	b.text = label
	b.tooltip_text = tip
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(56, 0)
	b.pressed.connect(func() -> void:
		editor.set_tool_mode(editor.Tool.TERRAIN)
		editor._set_paint_layer(layer))
	layer_buttons.append({"layer": layer, "btn": b})
	row.add_child(b)

## 变种按钮：设置变种 + 顺带切到对应作用层（草种→草地，石种→石板路）
func _add_variant_button(row: HBoxContainer, group: ButtonGroup, variant: int,
		layer: int, label: String, tip: String) -> void:
	var b: Button = Button.new()
	b.text = label
	b.tooltip_text = tip
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(56, 0)
	b.pressed.connect(func() -> void:
		editor.set_tool_mode(editor.Tool.TERRAIN)
		editor._set_paint_variant(variant)
		editor._set_paint_layer(layer))
	variant_buttons.append({"variant": variant, "layer": layer, "btn": b})
	row.add_child(b)

## 笔刷半径/强度滑杆（地形/地质/道路三个页签共用一套参数）
func _add_brush_sliders(body: HBoxContainer) -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	body.add_child(col)
	col.add_child(_slider_row("半径", 2.0, 40.0, editor.brush_radius, "%.0f m",
		func(v: float) -> void:
			editor.brush_radius = v
			if radius_val != null:
				radius_val.text = "%.0f m" % v))
	col.add_child(_slider_row("强度", 0.05, 2.0, editor.brush_strength, "%.2f",
		func(v: float) -> void:
			editor.brush_strength = v
			if strength_val != null:
				strength_val.text = "%.2f" % v))

## 提示文字块
func _add_hint(body: HBoxContainer, text: String) -> void:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.62, 0.62, 0.62))
	l.add_theme_font_size_override("font_size", 12)
	body.add_child(l)

func _slider_row(label_text: String, lo: float, hi: float, val: float,
		fmt: String, on_change: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l: Label = Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(36, 0)
	row.add_child(l)
	var s: HSlider = HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = val
	s.custom_minimum_size = Vector2(140, 0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(on_change)
	row.add_child(s)
	if label_text == "半径":
		radius_slider = s
		radius_val = Label.new()
		radius_val.text = fmt % val
		radius_val.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95))
		row.add_child(radius_val)
	elif label_text == "强度":
		strength_slider = s
		strength_val = Label.new()
		strength_val.text = fmt % val
		strength_val.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95))
		row.add_child(strength_val)
	return row

## 左下状态条：当前笔刷 / 光标 / toast
func _build_status(layer: CanvasLayer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_top = -132.0
	panel.offset_bottom = -16.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.13, 0.85)
	sb.border_color = Color(0.28, 0.30, 0.34)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)

	mode_label = Label.new()
	mode_label.add_theme_font_size_override("font_size", 14)
	vb.add_child(mode_label)

	pos_label = Label.new()
	pos_label.text = "光标：—"
	pos_label.add_theme_color_override("font_color", Color(0.66, 0.66, 0.66))
	vb.add_child(pos_label)

	toast_label = Label.new()
	toast_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.custom_minimum_size = Vector2(280, 0)
	vb.add_child(toast_label)

## 右侧栏：贴在右上角（Ribbon 占掉顶部 ~150px，右栏从它下面开始）
func _build_right_host(layer: CanvasLayer) -> void:
	right_host = VBoxContainer.new()
	right_host.anchor_left = 1.0
	right_host.anchor_right = 1.0
	right_host.offset_left = -320.0
	right_host.offset_right = -16.0
	right_host.offset_top = 170.0
	right_host.offset_bottom = 16.0
	right_host.grow_vertical = Control.GROW_DIRECTION_END
	right_host.add_theme_constant_override("separation", 8)
	layer.add_child(right_host)

# ---------------------------------------------------------------- 状态更新

## 左下状态条第一行：当前笔刷的完整描述（层 + 变种一起说清）
func _update_mode_label() -> void:
	if mode_label == null:
		return
	var layer: int = editor.paint_layer if editor != null else -1
	var mode: int = editor.mode if editor != null else -1
	var variant: int = editor.paint_variant if editor != null else -1
	if layer < 0:
		if mode < 0:
			mode_label.text = "未选笔刷（1~4 高度 · 5~8 地表 · 9/0 道路 · G 草地）"
		else:
			var names: PackedStringArray = ["抬升", "下压", "平滑", "平台"]
			mode_label.text = "笔刷：高度·%s（1~4 切换）" % names[clampi(mode, 0, names.size() - 1)]
		return
	match layer:
		SplatBrush.Layer.SAND:
			mode_label.text = "笔刷：地表·沙地（Shift=擦除）"
		SplatBrush.Layer.DIRT:
			mode_label.text = "笔刷：地表·泥土（Shift=擦除）"
		SplatBrush.Layer.ROCK:
			mode_label.text = "笔刷：地表·岩石（Shift=擦除）"
		SplatBrush.Layer.FOREST:
			mode_label.text = "笔刷：地表·林地（Shift=擦除）"
		SplatBrush.Layer.PAVED:
			mode_label.text = "石板路·%s（Shift=擦除）" % _variant_name(SplatBrush.PAVED_VARIANTS, variant)
		SplatBrush.Layer.ROAD:
			mode_label.text = "笔刷：土路（两侧自动补路肩 · Shift=擦除）"
		SplatBrush.LAYER_GRASS:
			mode_label.text = "草地·%s（Shift=擦除手选草种）" % _variant_name(SplatBrush.GRASS_VARIANTS, variant)
		_:
			mode_label.text = "未选笔刷"

func _variant_name(defs: Array, variant: int) -> String:
	if variant < 0:
		return "自动分带"
	for d in defs:
		if int(d["id"]) == variant:
			return str(d["label"])
	return "自动分带"

func set_mode_text(_m: int) -> void:
	_sync_mode_buttons()
	_update_mode_label()

## 同步作用层按钮的高亮（键盘 5~8/0/G 切层时也要亮起来）
func set_paint_layer(layer: int) -> void:
	_sync_mode_buttons()
	_sync_layer_buttons()
	_sync_variant_buttons()
	_update_mode_label()

## 同步变种按钮高亮
func set_paint_variant(_v: int) -> void:
	_sync_variant_buttons()
	_update_mode_label()

func _sync_layer_buttons() -> void:
	var layer: int = editor.paint_layer if editor != null else -1
	for pair in layer_buttons:
		var b: Button = pair["btn"]
		if b != null:
			b.set_pressed_no_signal(int(pair["layer"]) == layer)

func _sync_variant_buttons() -> void:
	if editor == null:
		return
	var layer: int = editor.paint_layer
	var variant: int = editor.paint_variant
	for pair in variant_buttons:
		var b: Button = pair["btn"]
		if b != null:
			b.set_pressed_no_signal(int(pair["layer"]) == layer and int(pair["variant"]) == variant)

## 模式按钮高亮：只在"高度"作用层（paint_layer < 0）时亮对应档，
## 刷地表时四个模式按钮全部熄灭（模式对拼图层无意义）。
func _sync_mode_buttons() -> void:
	var active: int = -1
	if editor != null and editor.paint_layer < 0 and editor.mode >= 0:
		active = clampi(editor.mode, 0, mode_buttons.size() - 1)
	for i in range(mode_buttons.size()):
		var mb: Button = mode_buttons[i]
		if mb != null:
			mb.set_pressed_no_signal(i == active)

func set_pos_text(t: String) -> void:
	if pos_label != null:
		pos_label.text = t

func set_doc_text(t: String) -> void:
	if doc_label != null:
		doc_label.text = t

func set_undo_state(can_undo: bool, can_redo: bool, undo_n: int) -> void:
	if undo_btn != null:
		undo_btn.disabled = not can_undo
		undo_btn.text = "撤销" if undo_n <= 0 else "撤销(%d)" % undo_n
	if redo_btn != null:
		redo_btn.disabled = not can_redo

func show_toast(msg: String) -> void:
	if toast_label != null:
		toast_label.text = msg
		_toast_t = 3.5

func tick(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0 and toast_label != null:
			toast_label.text = ""
