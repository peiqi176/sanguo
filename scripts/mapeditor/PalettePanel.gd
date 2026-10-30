extends RefCounted
## PalettePanel —— 右侧调色板（分类 + 搜索 + 对象清单）
##
## 数据全部来自 config/*.json，不在这里硬编码任何 id。
## 点一个条目 = 进入放置模式（由 ObjectLayer 接管鼠标）。
##
## 贴图来源：DataLoader.get_sprite_texture()（asset_map.json 的 60 条映射）。
## 没贴图的条目会退化成纯文字 —— 这是有意的，方便一眼看出哪些资产还缺。

const ObjectSpawner = preload("res://scripts/mapruntime/ObjectSpawner.gd")
const AssetImporter = preload("res://scripts/mapeditor/AssetImporter.gd")
const EntityImporter = preload("res://scripts/mapeditor/EntityImporter.gd")

## 分类定义：key → { 显示名, DataLoader 里的类别名（取贴图用）, 数据源 }
## orphan = assets/sprites/ 里躺着但没写进 asset_map.json 的图，
##          点一下就能走导入流程（M3-5）。灰显是为了和"已注册"一眼区分。
const CATS: Array = [
	{"key": "building", "label": "建筑", "asset": "buildings"},
	{"key": "unit", "label": "单位", "asset": "units"},
	{"key": "resource", "label": "资源", "asset": "resources"},
	{"key": "deco", "label": "装饰", "asset": ""},
	{"key": "village", "label": "村庄", "asset": "villages"},
	{"key": "horse", "label": "野马", "asset": "horses"},
	{"key": "orphan", "label": "未注册", "asset": ""},
]

## 调色板分类 key ←→ asset_map 分类名的反向表（导入成功后跳回对应分类用）
const KEY_TO_ASSET: Dictionary = {
	"building": "buildings",
	"unit": "units",
	"village": "village",
	"horse": "wild_horse",
}

var editor = null

var panel: PanelContainer = null
var list: ItemList = null
var search_edit: LineEdit = null
var select_btn: Button = null
var count_label: Label = null

var _cat: String = "building"
var _ids: Array = []          # 当前分类的 id 列表（与 list 行号一一对应）
var _sel_id: String = ""      # 当前选中的 id（删除按钮用）
var _cat_buttons: Dictionary = {}

func _init(ed) -> void:
	editor = ed

# ---------------------------------------------------------------- 构建

func build(parent: Node) -> void:
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(304, 0)
	parent.add_child(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var head: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "调色板"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	select_btn = Button.new()
	select_btn.text = "选择 (V)"
	select_btn.toggle_mode = true
	select_btn.tooltip_text = "选择模式：左键点对象可选中，Delete 删除"
	select_btn.toggled.connect(func(on: bool):
		if on:
			editor.set_tool_mode(editor.Tool.SELECT)
		else:
			editor.set_tool_mode(editor.Tool.TERRAIN))
	head.add_child(select_btn)

	# 导入贴图：除了点这里，直接把 PNG 拖进窗口也能触发（MapEditor 接了 files_dropped）
	var import_btn: Button = Button.new()
	import_btn.text = "＋图"
	import_btn.tooltip_text = "把一张 PNG 挂到**已有**实体上（只换贴图，不改数值）"
	import_btn.pressed.connect(func(): _pick_file())
	head.add_child(import_btn)

	# 导入实体：图 + 玩法数值一起登记成新的建筑/兵种
	var entity_btn: Button = Button.new()
	entity_btn.text = "＋实体"
	entity_btn.tooltip_text = "导入一张 PNG 并登记成**新的**建筑/兵种（填血量、造价、尺寸/攻防）"
	entity_btn.pressed.connect(func(): _pick_file_entity())
	head.add_child(entity_btn)
	vb.add_child(head)

	# 分类按钮（6 个，两行三列用 HFlowContainer 自动折行）
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	var group: ButtonGroup = ButtonGroup.new()
	for c in CATS:
		var b: Button = Button.new()
		b.text = str(c["label"])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(60, 26)
		var key: String = str(c["key"])
		b.toggled.connect(func(on: bool):
			if on:
				_set_cat(key))
		flow.add_child(b)
		_cat_buttons[key] = b
	vb.add_child(flow)

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "搜索…"
	search_edit.clear_button_enabled = true
	search_edit.text_changed.connect(func(_t: String): _refresh_list())
	vb.add_child(search_edit)

	list = ItemList.new()
	list.custom_minimum_size = Vector2(288, 420)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(28, 28)
	list.icon_mode = ItemList.ICON_MODE_LEFT
	list.allow_reselect = true
	list.item_selected.connect(_on_item_selected)
	vb.add_child(list)

	# 底部：件数 + 删除。删除放这儿而不是顶部工具行 ——
	# 顶部已经有三个按钮，304px 宽再塞一个就会把标题挤没。
	var foot: HBoxContainer = HBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	vb.add_child(foot)

	count_label = Label.new()
	count_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(count_label)

	var del_btn: Button = Button.new()
	del_btn.text = "删除选中"
	del_btn.tooltip_text = "删除选中的自建建筑/兵种（内置的删不掉；PNG 会保留）"
	del_btn.pressed.connect(func(): _delete_selected())
	foot.add_child(del_btn)

	# 默认选第一个分类
	_set_cat("building")
	_cat_buttons["building"].set_pressed_no_signal(true)

# ---------------------------------------------------------------- 分类 / 列表

func _set_cat(key: String) -> void:
	_cat = key
	_refresh_list()

func _asset_cat() -> String:
	for c in CATS:
		if str(c["key"]) == _cat:
			return str(c["asset"])
	return ""

func _refresh_list() -> void:
	if list == null:
		return
	list.clear()
	_ids.clear()

	var kw: String = search_edit.text.strip_edges().to_lower() if search_edit != null else ""
	var asset_cat: String = _asset_cat()

	for id in _all_ids():
		var disp: String = _display_name(id)
		if kw != "" and not (str(id).to_lower().contains(kw) or disp.to_lower().contains(kw)):
			continue
		var idx: int = list.add_item(disp)
		list.set_item_metadata(idx, {"kind": _cat, "id": str(id)})
		_ids.append(str(id))
		if _cat == "orphan":
			# 未注册图：直接按文件路径取纹理（DataLoader 有"未导入 PNG"兜底解码），
			# 整行灰显，表示"这张图还没挂到任何实体上"
			var tex_o: Texture2D = DataLoader.load_texture_file(DataLoader.SPRITE_DIR + str(id))
			if tex_o != null:
				list.set_item_icon(idx, tex_o)
			list.set_item_custom_fg_color(idx, Color(0.62, 0.62, 0.62))
		elif asset_cat != "":
			var tex: Texture2D = DataLoader.get_sprite_texture(asset_cat, str(id))
			if tex != null:
				list.set_item_icon(idx, tex)

	if count_label != null:
		count_label.text = "%s：%d 项" % [_cat_label(), _ids.size()]

func _cat_label() -> String:
	for c in CATS:
		if str(c["key"]) == _cat:
			return str(c["label"])
	return _cat

## 各分类的 id 来源。有新资产类型时只改这里。
func _all_ids() -> Array:
	match _cat:
		"building":
			# ⚠️ buildings.json 的外层是 {_meta, buildings}，直接对 DataLoader.buildings 取 keys
			# 只会拿到 "_meta" 和 "buildings" 两个字面量 —— 建筑页会变成两行假数据。
			var bmap: Dictionary = DataLoader.buildings.get("buildings", {})
			return _sorted_keys(bmap)
		"unit":
			# units.json 同理（外层多了 level_curve / *_growth_per_level 等）
			var umap: Dictionary = DataLoader.units.get("units", {})
			return _sorted_keys(umap)
		"resource":
			return ["wood", "iron", "food"]
		"deco":
			return ObjectSpawner.deco_ids()
		"village":
			return ["village_0", "village_1", "village_2", "village_3", "village_4", "village_5"]
		"horse":
			return ["white", "red", "chitu", "dilu"]
		"orphan":
			return AssetImporter.orphan_files()
	return []

func _sorted_keys(d: Dictionary) -> Array:
	var ks: Array = d.keys()
	ks.sort_custom(func(a, b): return _display_name(a) < _display_name(b))
	return ks

func _display_name(id) -> String:
	match _cat:
		"building":
			var bd: Dictionary = DataLoader.get_building_def(str(id))
			var n: String = str(bd.get("name", ""))
			return "%s  %s" % [n, id] if n != "" else str(id)
		"unit":
			var ud: Dictionary = DataLoader.get_unit_def(str(id))
			var n2: String = str(ud.get("name", ""))
			return "%s  %s" % [n2, id] if n2 != "" else str(id)
		"deco":
			var info: Dictionary = ObjectSpawner.parse_deco_id(str(id))
			if str(info.get("kind", "")) == "tree":
				if info.has("species"):
					var sp: String = str(info["species"])
					var cn: String = str(TreeGLTF.SPECIES_CN.get(sp, sp))
					return "%s  %s" % [cn, sp]
				return "树  type=%d" % int(info.get("type", 0))
			match str(id):
				"buddha": return "佛像"
				"rock": return "岩石"
				"lantern": return "灯笼"
			return str(id)
		"horse":
			match str(id):
				"white": return "白马"
				"red": return "赤马"
				"chitu": return "赤兔"
				"dilu": return "的卢"
			return str(id)
		"resource":
			match str(id):
				"wood": return "木材"
				"iron": return "铁矿"
				"food": return "粮食"
			return str(id)
		"orphan":
			return "📄 " + str(id)
	return str(id)

# ---------------------------------------------------------------- 交互

func _on_item_selected(idx: int) -> void:
	var meta = list.get_item_metadata(idx)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var kind: String = str(meta.get("kind", ""))
	var id: String = str(meta.get("id", ""))
	_sel_id = id
	# 未注册图不进入放置模式，而是打开导入窗口：先告诉我"这是什么"，再变成可摆资产
	if kind == "orphan":
		editor.open_import_dialog(DataLoader.SPRITE_DIR + id)
		return
	editor.begin_placement(kind, id)

## 导入成功后重刷列表（AssetImporter 改了 asset_map.json 之后必须调）
func refresh() -> void:
	_sel_id = ""
	_refresh_list()

## 删除当前选中的自建实体。内置的、别的分类的都不许删，只提示不动作。
func _delete_selected() -> void:
	if _sel_id == "":
		_toast("先在列表里点一项，再按「－」")
		return
	if _cat != "building" and _cat != "unit":
		_toast("删除只在「建筑」「单位」两页可用（这一页本来就没有实体定义）")
		return
	var kind: String = "unit" if _cat == "unit" else "building"
	if not EntityImporter.is_custom(kind, _sel_id):
		_toast("「%s」是内置%s，改不了（自建的才能删）" % [
			_sel_id, str(EntityImporter.KIND_LABELS.get(kind, "实体"))])
		return
	var label: String = str(EntityImporter.KIND_LABELS.get(kind, "实体"))
	var dlg: ConfirmationDialog = ConfirmationDialog.new()
	dlg.title = "删除自建" + label
	dlg.dialog_text = "确定删除自建%s「%s」？\n\n· 定义与贴图映射都会被移除\n· PNG 文件保留，会落到「未注册」分组" % [label, _sel_id]
	dlg.ok_button_text = "删除"
	editor.add_child(dlg)
	var target_id: String = _sel_id
	var target_kind: String = kind
	dlg.confirmed.connect(func():
		var r: Dictionary = EntityImporter.remove_entity(target_kind, target_id)
		_toast(("✅ " if bool(r.get("ok", false)) else "❌ ") + str(r.get("message", "")))
		if bool(r.get("ok", false)):
			# 正拿着它当放置 ghost 的话，删完 ghost 还指着一个不存在的 id
			if editor.tool_mode == editor.Tool.PLACE:
				editor.cancel_placement()
			refresh()
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()

func _toast(msg: String) -> void:
	if editor != null and editor._ui != null:
		editor._ui.show_toast(msg)
	print("[Palette] ", msg)

## 跳到某个 asset_map 分类对应的调色板页（导入完成后自动跳过去看成果）
func focus_cat(asset_cat: String) -> void:
	for k in KEY_TO_ASSET.keys():
		if str(KEY_TO_ASSET[k]) == asset_cat:
			_set_cat(str(k))
			if _cat_buttons.has(str(k)):
				_cat_buttons[str(k)].set_pressed_no_signal(true)
			return

## 退出放置模式时把"选择"按钮也弹起来，避免状态显示不一致
func sync_mode(tool_mode: int, select_mode_value: int) -> void:
	if select_btn != null:
		select_btn.set_pressed_no_signal(tool_mode == select_mode_value)

## 系统文件选择框挑一张 PNG（拖拽入口见 MapEditor 的 files_dropped）
func _pick_file() -> void:
	var fd: FileDialog = FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png ; PNG 图片"])
	fd.title = "选择要导入的 PNG"
	fd.size = Vector2i(760, 520)
	editor.add_child(fd)
	fd.file_selected.connect(func(p: String):
		fd.queue_free()
		editor.open_import_dialog(p))
	fd.canceled.connect(func(): fd.queue_free())
	fd.popup_centered()

## 挑一张 PNG 当作「新建筑 / 新兵种」的立绘。类型初值跟着当前分类走：
## 在「单位」页点就是兵种，其余页一律先给建筑（窗口里还能改）。
func _pick_file_entity() -> void:
	var fd: FileDialog = FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png ; PNG 图片"])
	fd.title = "选择要导入的建筑 / 兵种立绘"
	fd.size = Vector2i(760, 520)
	editor.add_child(fd)
	var hint: String = "unit" if _cat == "unit" else "building"
	fd.file_selected.connect(func(p: String):
		fd.queue_free()
		editor.open_entity_dialog(p, hint))
	fd.canceled.connect(func(): fd.queue_free())
	fd.popup_centered()
