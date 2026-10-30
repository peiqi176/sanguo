extends RefCounted
## InspectorPanel —— 选中对象的属性面板
##
## 只做"M1 够用"的那部分：看信息、改归属、改资源量、删除。
## 建筑 HP/成本的地图级 override 属于 Object Editor 概念，放到 M5。
##
## 所有改动都写回 doc（数据真相），再让 ObjectLayer 重建那个节点，
## 而不是直接改节点字段 —— 否则存盘时 doc 里还是旧值，改了等于白改。

const FACTION_LABELS: Array = [
	{"id": "shu", "label": "蜀"},
	{"id": "wei", "label": "魏"},
	{"id": "wu", "label": "吴"},
	{"id": "neutral", "label": "中立"},
]

var editor = null

var panel: PanelContainer = null
var title_label: Label = null
var info_label: Label = null
var owner_row: HBoxContainer = null
var owner_option: OptionButton = null
var amount_row: HBoxContainer = null
var amount_edit: LineEdit = null
var del_btn: Button = null

var _idx: int = -1
var _updating: bool = false

func _init(ed) -> void:
	editor = ed

func build(parent: Node) -> void:
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(304, 0)
	panel.visible = false
	parent.add_child(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	title_label = Label.new()
	title_label.text = "选中"
	title_label.add_theme_font_size_override("font_size", 16)
	vb.add_child(title_label)

	info_label = Label.new()
	info_label.text = "—"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info_label)

	owner_row = HBoxContainer.new()
	var ol: Label = Label.new()
	ol.text = "归属"
	ol.custom_minimum_size = Vector2(48, 0)
	owner_row.add_child(ol)
	owner_option = OptionButton.new()
	owner_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for f in FACTION_LABELS:
		owner_option.add_item(str(f["label"]))
	owner_option.item_selected.connect(_on_owner_changed)
	owner_row.add_child(owner_option)
	vb.add_child(owner_row)

	amount_row = HBoxContainer.new()
	var al: Label = Label.new()
	al.text = "资源量"
	al.custom_minimum_size = Vector2(48, 0)
	amount_row.add_child(al)
	amount_edit = LineEdit.new()
	amount_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_edit.text_submitted.connect(func(_t: String): _on_amount_changed())
	amount_row.add_child(amount_edit)
	vb.add_child(amount_row)

	del_btn = Button.new()
	del_btn.text = "删除 (Delete)"
	del_btn.pressed.connect(func(): editor.delete_selected())
	vb.add_child(del_btn)

# ---------------------------------------------------------------- 显示

func show_object(idx: int, obj: Dictionary) -> void:
	if panel == null:
		return
	if typeof(obj) != TYPE_DICTIONARY or obj.is_empty():
		clear()
		return

	_idx = idx
	_updating = true
	panel.visible = true

	var kind: String = str(obj.get("kind", ""))
	var id: String = str(obj.get("id", ""))
	var gp = obj.get("grid", [0, 0])
	var gx: int = int(gp[0]) if typeof(gp) == TYPE_ARRAY and (gp as Array).size() >= 2 else 0
	var gy: int = int(gp[1]) if typeof(gp) == TYPE_ARRAY and (gp as Array).size() >= 2 else 0

	title_label.text = "%s · %s" % [_kind_label(kind), _name_of(kind, id)]
	info_label.text = "id：%s\n格子：(%d, %d)" % [id, gx, gy]

	# 归属只对有阵营概念的对象有意义
	var has_owner: bool = (kind == "building" or kind == "unit")
	owner_row.visible = has_owner
	if has_owner:
		var owner_id: String = str(obj.get("owner", "shu"))
		for i in range(FACTION_LABELS.size()):
			if str(FACTION_LABELS[i]["id"]) == owner_id:
				owner_option.select(i)
				break

	# 资源量只对非矿洞的资源点有意义（矿洞是无限）
	var is_res: bool = (kind == "resource")
	amount_row.visible = is_res and not bool(obj.get("is_mine", false))
	if amount_row.visible:
		amount_edit.text = str(int(obj.get("amount", 800)))

	_updating = false

func clear() -> void:
	_idx = -1
	if panel != null:
		panel.visible = false

func current_index() -> int:
	return _idx

# ---------------------------------------------------------------- 改值

func _on_owner_changed(i: int) -> void:
	if _updating or _idx < 0:
		return
	var fid: String = str(FACTION_LABELS[clampi(i, 0, FACTION_LABELS.size() - 1)]["id"])
	editor.change_selected_owner(fid)

func _on_amount_changed() -> void:
	if _updating or _idx < 0 or amount_edit == null:
		return
	var v: int = int(amount_edit.text)
	editor.change_selected_amount(maxi(v, 1))
	amount_edit.text = str(maxi(v, 1))

# ---------------------------------------------------------------- 文案

func _kind_label(kind: String) -> String:
	match kind:
		"building": return "建筑"
		"unit": return "单位"
		"resource": return "资源"
		"village": return "村庄"
		"horse": return "野马"
		"deco": return "装饰"
	return kind

func _name_of(kind: String, id: String) -> String:
	match kind:
		"building":
			var bd: Dictionary = DataLoader.get_building_def(id)
			return str(bd.get("name", id))
		"unit":
			var ud: Dictionary = DataLoader.get_unit_def(id)
			return str(ud.get("name", id))
	return id
