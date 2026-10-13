extends CanvasLayer
## GameUI — AoE4 风格主 HUD
## 顶部资源条、左上官府等级、右上科技按钮、底部命令面板、右下小地图

var _resource_bar: PanelContainer
var _res_container: HBoxContainer
var _age_bar: PanelContainer
var _topright: HBoxContainer
var _cmd_panel: PanelContainer
var _cmd_portrait: Panel
var _cmd_name: Label
var _cmd_hp_bar: ProgressBar = null
var _cmd_mp_bar: ProgressBar = null
var _cmd_stats: GridContainer
var _cmd_btns: GridContainer
var _minimap: Control
var _minimap_bg: ColorRect
var _minimap_canvas: Control
var _float_texts: Array = []
var _tech_panel: PanelContainer = null
var _tech_branch_tabs: HBoxContainer = null
var _tech_list: VBoxContainer = null
var _tech_progress: ProgressBar = null
var _cur_branch: String = "civilian"
var _diplo_panel: PanelContainer = null
var _diplo_list: VBoxContainer = null
var _settings_panel: PanelContainer = null
var _general_roster: HBoxContainer = null

# 官府等级名称
const AGE_NAMES = ["县府", "郡治", "州牧", "王城"]

func _ready() -> void:
	_build_ui()
	_connect_signals()

func _build_ui() -> void:
	# === 顶部中央资源条 ===
	_resource_bar = PanelContainer.new()
	_resource_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_resource_bar.offset_left = 200
	_resource_bar.offset_right = -200
	_resource_bar.offset_top = 8
	_resource_bar.offset_bottom = 40
	var res_style := StyleBoxFlat.new()
	res_style.bg_color = Color(0.23, 0.17, 0.10, 0.92)
	res_style.border_color = Color(0.79, 0.64, 0.29, 1.0)
	res_style.border_width_left = 1
	res_style.border_width_right = 1
	res_style.border_width_top = 1
	res_style.border_width_bottom = 1
	res_style.corner_radius_top_left = 6
	res_style.corner_radius_top_right = 6
	res_style.corner_radius_bottom_left = 6
	res_style.corner_radius_bottom_right = 6
	_resource_bar.add_theme_stylebox_override("panel", res_style)
	add_child(_resource_bar)
	_res_container = HBoxContainer.new()
	_res_container.add_theme_constant_override("separation", 8)
	_res_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_res_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_res_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_resource_bar.add_child(_res_container)
	_update_resource_bar()

	# === 左上官府等级条 ===
	_age_bar = PanelContainer.new()
	_age_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_age_bar.offset_left = 10
	_age_bar.offset_top = 8
	_age_bar.offset_right = 130
	_age_bar.offset_bottom = 40
	var age_style := StyleBoxFlat.new()
	age_style.bg_color = Color(0.12, 0.09, 0.05, 0.9)
	age_style.border_color = Color(0.79, 0.64, 0.29, 1.0)
	age_style.border_width_left = 1
	age_style.border_width_right = 1
	age_style.border_width_top = 1
	age_style.border_width_bottom = 1
	age_style.corner_radius_top_left = 6
	age_style.corner_radius_top_right = 6
	age_style.corner_radius_bottom_left = 6
	age_style.corner_radius_bottom_right = 6
	_age_bar.add_theme_stylebox_override("panel", age_style)
	add_child(_age_bar)
	var age_hbox: HBoxContainer = HBoxContainer.new()
	age_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_age_bar.add_child(age_hbox)
	_update_age_bar(age_hbox)

	# === 右上科技/设置按钮 ===
	_topright = HBoxContainer.new()
	_topright.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_topright.offset_left = -110
	_topright.offset_right = -10
	_topright.offset_top = 8
	_topright.offset_bottom = 40
	_topright.alignment = BoxContainer.ALIGNMENT_END
	add_child(_topright)
	for btext in ["科", "外", "设"]:
		var btn: Button = Button.new()
		btn.text = btext
		btn.custom_minimum_size = Vector2(30, 30)
		var tbs := StyleBoxFlat.new()
		tbs.bg_color = Color(0.29, 0.22, 0.14, 1.0)
		tbs.border_color = Color(0.79, 0.64, 0.29, 1.0)
		tbs.border_width_left = 1
		tbs.border_width_right = 1
		tbs.border_width_top = 1
		tbs.border_width_bottom = 1
		tbs.corner_radius_top_left = 5
		tbs.corner_radius_top_right = 5
		tbs.corner_radius_bottom_left = 5
		tbs.corner_radius_bottom_right = 5
		btn.add_theme_stylebox_override("normal", tbs)
		btn.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
		btn.pressed.connect(_on_topright_btn.bind(btext))
		_topright.add_child(btn)

	# === 底部命令面板 ===
	_cmd_panel = PanelContainer.new()
	_cmd_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_cmd_panel.offset_left = 10
	_cmd_panel.offset_right = -170
	_cmd_panel.offset_top = -145
	_cmd_panel.offset_bottom = -10
	var cmd_style := StyleBoxFlat.new()
	cmd_style.bg_color = Color(0.26, 0.19, 0.12, 0.95)
	cmd_style.border_color = Color(0.79, 0.64, 0.29, 1.0)
	cmd_style.border_width_top = 2
	cmd_style.border_width_left = 1
	cmd_style.border_width_right = 1
	cmd_style.border_width_bottom = 1
	_cmd_panel.add_theme_stylebox_override("panel", cmd_style)
	add_child(_cmd_panel)
	var cmd_hbox: HBoxContainer = HBoxContainer.new()
	cmd_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cmd_panel.add_child(cmd_hbox)

	# 左侧立绘区
	_cmd_portrait = Panel.new()
	_cmd_portrait.custom_minimum_size = Vector2(100, 0)
	_cmd_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.08, 0.04, 1.0)
	_cmd_portrait.add_theme_stylebox_override("panel", p_style)
	cmd_hbox.add_child(_cmd_portrait)
	var pv_vbox: VBoxContainer = VBoxContainer.new()
	pv_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	pv_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_cmd_portrait.add_child(pv_vbox)
	var pv_icon: Label = Label.new()
	pv_icon.text = "⚔"
	pv_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv_icon.add_theme_font_size_override("font_size", 36)
	pv_vbox.add_child(pv_icon)
	_cmd_name = Label.new()
	_cmd_name.text = "未选中"
	_cmd_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cmd_name.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	pv_vbox.add_child(_cmd_name)
	# HP 条
	_cmd_hp_bar = ProgressBar.new()
	_cmd_hp_bar.custom_minimum_size = Vector2(90, 8)
	_cmd_hp_bar.min_value = 0
	_cmd_hp_bar.max_value = 100
	_cmd_hp_bar.value = 100
	_cmd_hp_bar.show_percentage = false
	var hp_style := StyleBoxFlat.new()
	hp_style.bg_color = Color(0.2, 0.05, 0.05, 1.0)
	hp_style.corner_radius_top_left = 2
	hp_style.corner_radius_top_right = 2
	hp_style.corner_radius_bottom_left = 2
	hp_style.corner_radius_bottom_right = 2
	_cmd_hp_bar.add_theme_stylebox_override("background", hp_style)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.85, 0.15, 0.15, 1.0)
	hp_fill.corner_radius_top_left = 2
	hp_fill.corner_radius_top_right = 2
	hp_fill.corner_radius_bottom_left = 2
	hp_fill.corner_radius_bottom_right = 2
	_cmd_hp_bar.add_theme_stylebox_override("fill", hp_fill)
	pv_vbox.add_child(_cmd_hp_bar)
	# MP 条
	_cmd_mp_bar = ProgressBar.new()
	_cmd_mp_bar.custom_minimum_size = Vector2(90, 6)
	_cmd_mp_bar.min_value = 0
	_cmd_mp_bar.max_value = 100
	_cmd_mp_bar.value = 100
	_cmd_mp_bar.show_percentage = false
	var mp_style := StyleBoxFlat.new()
	mp_style.bg_color = Color(0.05, 0.05, 0.2, 1.0)
	mp_style.corner_radius_top_left = 2
	mp_style.corner_radius_top_right = 2
	mp_style.corner_radius_bottom_left = 2
	mp_style.corner_radius_bottom_right = 2
	_cmd_mp_bar.add_theme_stylebox_override("background", mp_style)
	var mp_fill := StyleBoxFlat.new()
	mp_fill.bg_color = Color(0.2, 0.4, 0.9, 1.0)
	mp_fill.corner_radius_top_left = 2
	mp_fill.corner_radius_top_right = 2
	mp_fill.corner_radius_bottom_left = 2
	mp_fill.corner_radius_bottom_right = 2
	_cmd_mp_bar.add_theme_stylebox_override("fill", mp_fill)
	pv_vbox.add_child(_cmd_mp_bar)

	# 中间属性区
	_cmd_stats = GridContainer.new()
	_cmd_stats.columns = 2
	_cmd_stats.custom_minimum_size = Vector2(160, 0)
	_cmd_stats.add_theme_constant_override("h_separation", 4)
	_cmd_stats.add_theme_constant_override("v_separation", 4)
	cmd_hbox.add_child(_cmd_stats)
	_add_stat("攻", "0")
	_add_stat("防", "0")
	_add_stat("攻速", "0")
	_add_stat("移速", "0")
	_add_stat("士气", "0")
	_add_stat("等级", "Lv1")

	# 右侧命令按钮区
	var cmd_btns_container: VBoxContainer = VBoxContainer.new()
	cmd_btns_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_hbox.add_child(cmd_btns_container)
	_cmd_btns = GridContainer.new()
	_cmd_btns.columns = 6
	_cmd_btns.add_theme_constant_override("h_separation", 5)
	_cmd_btns.add_theme_constant_override("v_separation", 5)
	_cmd_btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_btns_container.add_child(_cmd_btns)
	# 占位按钮
	for i in range(12):
		var cb: Button = Button.new()
		cb.text = ""
		cb.custom_minimum_size = Vector2(44, 38)
		cb.disabled = true
		_cmd_btns.add_child(cb)

	# === 右下小地图 ===
	_minimap = Control.new()
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -160
	_minimap.offset_right = -10
	_minimap.offset_top = -155
	_minimap.offset_bottom = -10
	var mm_style := StyleBoxFlat.new()
	mm_style.bg_color = Color(0.08, 0.06, 0.04, 0.92)
	mm_style.border_color = Color(0.79, 0.64, 0.29, 1.0)
	mm_style.border_width_left = 1
	mm_style.border_width_right = 1
	mm_style.border_width_top = 1
	mm_style.border_width_bottom = 1
	mm_style.corner_radius_top_left = 6
	mm_style.corner_radius_top_right = 6
	mm_style.corner_radius_bottom_left = 6
	mm_style.corner_radius_bottom_right = 6
	var mm_panel: Panel = Panel.new()
	mm_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	mm_panel.add_theme_stylebox_override("panel", mm_style)
	_minimap.add_child(mm_panel)
	# 势力图例
	var legend: HBoxContainer = HBoxContainer.new()
	legend.set_anchors_preset(Control.PRESET_TOP_WIDE)
	legend.offset_top = 4
	legend.offset_bottom = 18
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 6)
	_minimap.add_child(legend)
	for info in [["#b93a3a","魏"],["#4fae4f","蜀"],["#4a7fce","吴"]]:
		var dot_lbl: Label = Label.new()
		dot_lbl.text = info[1]
		dot_lbl.add_theme_color_override("font_color", Color.from_string(info[0], Color.WHITE))
		legend.add_child(dot_lbl)
	# 小地图画布
	_minimap_canvas = Control.new()
	_minimap_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap_canvas.offset_top = 22
	_minimap_canvas.offset_bottom = -4
	_minimap_canvas.offset_left = 4
	_minimap_canvas.offset_right = -4
	_minimap_canvas.draw.connect(_on_minimap_draw)
	_minimap.add_child(_minimap_canvas)
	add_child(_minimap)

func _add_stat(label_str: String, value_str: String) -> void:
	var stat_panel: Panel = Panel.new()
	stat_panel.custom_minimum_size = Vector2(74, 28)
	var s_style := StyleBoxFlat.new()
	s_style.bg_color = Color(0.14, 0.10, 0.06, 1.0)
	s_style.border_color = Color(0.29, 0.22, 0.14, 1.0)
	s_style.border_width_left = 1
	s_style.border_width_right = 1
	s_style.border_width_top = 1
	s_style.border_width_bottom = 1
	s_style.corner_radius_top_left = 4
	s_style.corner_radius_top_right = 4
	s_style.corner_radius_bottom_left = 4
	s_style.corner_radius_bottom_right = 4
	stat_panel.add_theme_stylebox_override("panel", s_style)
	_cmd_stats.add_child(stat_panel)
	var sv: VBoxContainer = VBoxContainer.new()
	sv.set_anchors_preset(Control.PRESET_FULL_RECT)
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	stat_panel.add_child(sv)
	var lbl: Label = Label.new()
	lbl.text = label_str
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.73, 0.63, 0.45, 1.0))
	lbl.add_theme_font_size_override("font_size", 9)
	sv.add_child(lbl)
	var val: Label = Label.new()
	val.text = value_str
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	val.name = "val"
	sv.add_child(val)

func _update_resource_bar() -> void:
	for child in _res_container.get_children():
		child.queue_free()
	var faction: String = GameManager.player_faction
	var res_defs: Dictionary = DataLoader.factions.get("resources", {})
	for res_id in ["food", "wood", "stone", "gold"]:
		var info: Dictionary = res_defs.get(res_id, {})
		var chip: HBoxContainer = HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		var icon_lbl: Label = Label.new()
		icon_lbl.text = info.get("icon", "?")
		icon_lbl.add_theme_font_size_override("font_size", 14)
		chip.add_child(icon_lbl)
		var name_lbl: Label = Label.new()
		name_lbl.text = info.get("name", res_id)
		name_lbl.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
		chip.add_child(name_lbl)
		var amount: float = GameManager.get_resource(faction, res_id)
		var amt_lbl: Label = Label.new()
		amt_lbl.text = "%.0f" % amount
		amt_lbl.add_theme_color_override("font_color", Color.from_string(info.get("color", "#ffffff"), Color.WHITE))
		chip.add_child(amt_lbl)
		_res_container.add_child(chip)
	# 人口
	var pop: Dictionary = GameManager.get_population(faction)
	var pop_chip: HBoxContainer = HBoxContainer.new()
	pop_chip.add_theme_constant_override("separation", 3)
	var pi: Label = Label.new()
	pi.text = "👥"
	pi.add_theme_font_size_override("font_size", 14)
	pop_chip.add_child(pi)
	var pl: Label = Label.new()
	pl.text = "人口 %d/%d" % [pop["used"], pop["cap"]]
	pl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 1.0))
	pop_chip.add_child(pl)
	_res_container.add_child(pop_chip)
	# 民心
	var mor_chip: HBoxContainer = HBoxContainer.new()
	mor_chip.add_theme_constant_override("separation", 3)
	var mi: Label = Label.new()
	mi.text = "❤"
	mi.add_theme_font_size_override("font_size", 14)
	mor_chip.add_child(mi)
	var ml: Label = Label.new()
	ml.text = "民心 %.0f" % GameManager.get_morale(faction)
	ml.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5, 1.0))
	mor_chip.add_child(ml)
	_res_container.add_child(mor_chip)

	# 马匹储备
	var horse_chip: HBoxContainer = HBoxContainer.new()
	horse_chip.add_theme_constant_override("separation", 3)
	var hi: Label = Label.new()
	hi.text = "🐎"
	hi.add_theme_font_size_override("font_size", 14)
	horse_chip.add_child(hi)
	var hl: Label = Label.new()
	var horse_count: int = GameManager.factions[faction].horses if "horses" in GameManager.factions[faction] else 0
	hl.text = "马匹 %d" % horse_count
	hl.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1.0))
	horse_chip.add_child(hl)
	_res_container.add_child(horse_chip)
	# 占领村庄
	var vill_count: int = 0
	for v in GameManager.villages:
		if is_instance_valid(v) and v.village_owner == faction:
			vill_count += 1
	var vill_chip: HBoxContainer = HBoxContainer.new()
	vill_chip.add_theme_constant_override("separation", 3)
	var vi: Label = Label.new()
	vi.text = "🏘"
	vi.add_theme_font_size_override("font_size", 14)
	vill_chip.add_child(vi)
	var vl: Label = Label.new()
	vl.text = "村庄 %d" % vill_count
	vl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6, 1.0))
	vill_chip.add_child(vl)
	_res_container.add_child(vill_chip)
func _update_age_bar(container: HBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	var faction: String = GameManager.player_faction
	var cur_level: int = GameManager.get_government_level(faction)
	for i in range(4):
		var age_lbl: Label = Label.new()
		var lv: int = i + 1
		var active: bool = lv <= cur_level
		age_lbl.text = "官%d\n%s" % [lv, AGE_NAMES[i]]
		age_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if active:
			age_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.69, 1.0))
		else:
			age_lbl.add_theme_color_override("font_color", Color(0.45, 0.38, 0.25, 1.0))
		container.add_child(age_lbl)
	# 升级按钮
	if GameManager.can_upgrade_government(faction):
		var up_btn: Button = Button.new()
		up_btn.text = "↑"
		up_btn.custom_minimum_size = Vector2(24, 24)
		up_btn.pressed.connect(_on_upgrade_government)
		container.add_child(up_btn)

func _on_upgrade_government() -> void:
	if GameManager.upgrade_government(GameManager.player_faction):
		EventBus.float_text.emit("官府升级！", Vector3.ZERO, Color.GOLD)
		_update_age_bar(_age_bar.get_child(0))

func _on_topright_btn(btn_text: String) -> void:
	match btn_text:
		"科": _toggle_tech_panel()
		"外": _toggle_diplo_panel()
		"设": _toggle_settings_panel()


func _toggle_tech_panel() -> void:
	if _tech_panel and _tech_panel.visible:
		_tech_panel.visible = false
		return
	if _tech_panel == null:
		_build_tech_panel()
	_refresh_tech_panel()
	_tech_panel.visible = true

func _build_tech_panel() -> void:
	_tech_panel = PanelContainer.new()
	_tech_panel.set_anchors_preset(Control.PRESET_CENTER)
	_tech_panel.custom_minimum_size = Vector2(560, 440)
	var tp_style := StyleBoxFlat.new()
	tp_style.bg_color = Color(0.15, 0.11, 0.07, 0.97)
	tp_style.border_color = Color(0.79, 0.64, 0.29, 1.0)
	tp_style.border_width_left = 2
	tp_style.border_width_right = 2
	tp_style.border_width_top = 2
	tp_style.border_width_bottom = 2
	tp_style.corner_radius_top_left = 10
	tp_style.corner_radius_top_right = 10
	tp_style.corner_radius_bottom_left = 10
	tp_style.corner_radius_bottom_right = 10
	_tech_panel.add_theme_stylebox_override("panel", tp_style)
	add_child(_tech_panel)
	var tv: VBoxContainer = VBoxContainer.new()
	tv.set_anchors_preset(Control.PRESET_FULL_RECT)
	tv.add_theme_constant_override("separation", 8)
	_tech_panel.add_child(tv)
	# 标题栏
	var title_hbox: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "翰林院 · 科技树"
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	title.add_theme_font_size_override("font_size", 18)
	title_hbox.add_child(title)
	title_hbox.add_spacer(true)
	var close_btn: Button = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(30, 28)
	close_btn.pressed.connect(_toggle_tech_panel)
	title_hbox.add_child(close_btn)
	tv.add_child(title_hbox)
	# 进度条
	_tech_progress = ProgressBar.new()
	_tech_progress.custom_minimum_size = Vector2(0, 18)
	_tech_progress.min_value = 0
	_tech_progress.max_value = 100
	tv.add_child(_tech_progress)
	# 分支标签
	_tech_branch_tabs = HBoxContainer.new()
	_tech_branch_tabs.add_theme_constant_override("separation", 6)
	tv.add_child(_tech_branch_tabs)
	for info in [["civilian","民生"],["military","军事"],["siege","器械"]]:
		var tb: Button = Button.new()
		tb.text = info[1]
		tb.custom_minimum_size = Vector2(80, 28)
		tb.pressed.connect(_on_tech_tab.bind(info[0]))
		_tech_branch_tabs.add_child(tb)
	# 科技列表滚动区
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tv.add_child(scroll)
	_tech_list = VBoxContainer.new()
	_tech_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tech_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_tech_list)

func _on_tech_tab(branch: String) -> void:
	_cur_branch = branch
	_refresh_tech_panel()

func _refresh_tech_panel() -> void:
	if _tech_panel == null or not _tech_panel.visible:
		return
	# 更新进度
	var faction: String = GameManager.player_faction
	var completion: float = GameManager.get_tech_completion(faction) * 100.0
	_tech_progress.value = completion
	# 更新标签高亮
	for i in range(_tech_branch_tabs.get_child_count()):
		var btn: Button = _tech_branch_tabs.get_child(i)
		var branch_ids: Array = ["civilian", "military", "siege"]
		if i < branch_ids.size():
			btn.modulate = Color(1, 1, 1, 1) if branch_ids[i] == _cur_branch else Color(0.6, 0.6, 0.6, 1)
	# 清空列表
	for child in _tech_list.get_children():
		child.queue_free()
	var branches: Dictionary = DataLoader.tech.get("branches", {})
	if not branches.has(_cur_branch):
		return
	var techs: Dictionary = branches[_cur_branch].get("techs", {})
	var researched: Array = GameManager.factions[faction].researched_techs
	var gov_level: int = GameManager.get_government_level(faction)
	for tech_id in techs.keys():
		var tdef: Dictionary = techs[tech_id]
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		# 名称+效果
		var info_v: VBoxContainer = VBoxContainer.new()
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl: Label = Label.new()
		var is_done: bool = researched.has(tech_id)
		var prefix: String = "✅ " if is_done else "📜 "
		name_lbl.text = "%s%s" % [prefix, tdef.get("name", tech_id)]
		name_lbl.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0) if is_done else Color(0.8, 0.75, 0.6, 1.0))
		info_v.add_child(name_lbl)
		# 效果描述
		var eff_str: String = ""
		var effects: Dictionary = tdef.get("effect", {})
		for ek in effects.keys():
			eff_str += "%s+%s  " % [ek, str(effects[ek])]
		var eff_lbl: Label = Label.new()
		eff_lbl.text = "效果: %s" % eff_str
		eff_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6, 1.0))
		eff_lbl.add_theme_font_size_override("font_size", 11)
		info_v.add_child(eff_lbl)
		# 花费+前置
		var cost_str: String = ""
		var cost: Dictionary = tdef.get("cost", {})
		for ck in cost.keys():
			cost_str += "%s:%d " % [ck, cost[ck]]
		var req_str: String = ""
		if tdef.has("requires"):
			req_str = " 需: " + ", ".join(tdef["requires"])
		var cost_lbl: Label = Label.new()
		cost_lbl.text = "花费: %s%s | 官府Lv%d | %ds" % [cost_str, req_str, tdef.get("gov_req", 1), tdef.get("time", 30)]
		cost_lbl.add_theme_color_override("font_color", Color(0.73, 0.63, 0.45, 1.0))
		cost_lbl.add_theme_font_size_override("font_size", 10)
		info_v.add_child(cost_lbl)
		row.add_child(info_v)
		# 研究按钮
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(70, 32)
		if is_done:
			btn.text = "已研究"
			btn.disabled = true
		elif gov_level < tdef.get("gov_req", 1):
			btn.text = "官府不足"
			btn.disabled = true
		elif not GameManager.can_afford(faction, cost):
			btn.text = "资源不足"
			btn.disabled = true
		else:
			btn.text = "研究"
			btn.pressed.connect(_on_research_tech.bind(_cur_branch, tech_id))
		row.add_child(btn)
		_tech_list.add_child(row)

func _on_research_tech(branch: String, tech_id: String) -> void:
	if GameManager.research_tech(GameManager.player_faction, branch, tech_id):
		EventBus.float_text.emit("研究完成: %s" % tech_id, Vector3.ZERO, Color.GREEN)
		_refresh_tech_panel()
		_update_age_bar(_age_bar.get_child(0))
	else:
		EventBus.float_text.emit("研究失败", Vector3.ZERO, Color.RED)

func _toggle_diplo_panel() -> void:
	if _diplo_panel and _diplo_panel.visible:
		_diplo_panel.visible = false
		return
	if _diplo_panel == null:
		_build_diplo_panel()
	_refresh_diplo_panel()
	_diplo_panel.visible = true

func _build_diplo_panel() -> void:
	_diplo_panel = PanelContainer.new()
	_diplo_panel.set_anchors_preset(Control.PRESET_CENTER)
	_diplo_panel.custom_minimum_size = Vector2(520, 380)
	var dp_style := StyleBoxFlat.new()
	dp_style.bg_color = Color(0.15, 0.11, 0.07, 0.97)
	dp_style.border_color = Color(0.79, 0.64, 0.29, 1.0)
	dp_style.border_width_left = 2
	dp_style.border_width_right = 2
	dp_style.border_width_top = 2
	dp_style.border_width_bottom = 2
	dp_style.corner_radius_top_left = 10
	dp_style.corner_radius_top_right = 10
	dp_style.corner_radius_bottom_left = 10
	dp_style.corner_radius_bottom_right = 10
	_diplo_panel.add_theme_stylebox_override("panel", dp_style)
	add_child(_diplo_panel)
	var tv: VBoxContainer = VBoxContainer.new()
	tv.set_anchors_preset(Control.PRESET_FULL_RECT)
	tv.add_theme_constant_override("separation", 8)
	_diplo_panel.add_child(tv)
	var title_hbox: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "外交 · 国策"
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	title.add_theme_font_size_override("font_size", 18)
	title_hbox.add_child(title)
	title_hbox.add_spacer(true)
	var close_btn: Button = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(30, 28)
	close_btn.pressed.connect(_toggle_diplo_panel)
	title_hbox.add_child(close_btn)
	tv.add_child(title_hbox)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tv.add_child(scroll)
	_diplo_list = VBoxContainer.new()
	_diplo_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diplo_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_diplo_list)

func _refresh_diplo_panel() -> void:
	if _diplo_panel == null or not _diplo_panel.visible:
		return
	for child in _diplo_list.get_children():
		child.queue_free()
	var player: String = GameManager.player_faction
	var factions_def: Dictionary = DataLoader.factions.get("factions", {})
	var actions: Dictionary = DataLoader.diplomacy.get("actions", {})
	for other_id in factions_def.keys():
		if other_id == player:
			continue
		var other_def: Dictionary = factions_def[other_id]
		var trust: int = GameManager.get_trust(player, other_id)
		var relation: String = GameManager.get_relation(player, other_id)
		var rel_names: Dictionary = { "alliance": "结盟", "neutral": "中立", "war": "交战", "trade": "贸易" }
		var row_panel: Panel = Panel.new()
		var r_style := StyleBoxFlat.new()
		r_style.bg_color = Color(0.12, 0.09, 0.05, 1.0)
		r_style.border_color = Color(0.29, 0.22, 0.14, 1.0)
		r_style.border_width_left = 1
		r_style.border_width_right = 1
		r_style.border_width_top = 1
		r_style.border_width_bottom = 1
		row_panel.add_theme_stylebox_override("panel", r_style)
		_diplo_list.add_child(row_panel)
		var row_v: VBoxContainer = VBoxContainer.new()
		row_v.set_anchors_preset(Control.PRESET_FULL_RECT)
		row_panel.add_child(row_v)
		var header: HBoxContainer = HBoxContainer.new()
		var name_lbl: Label = Label.new()
		name_lbl.text = "%s (%s)" % [other_def.get("name", other_id), other_def.get("leader", "")]
		name_lbl.add_theme_color_override("font_color", Color.from_string(other_def.get("color", "#ffffff"), Color.WHITE))
		header.add_child(name_lbl)
		header.add_spacer(true)
		var trust_lbl: Label = Label.new()
		trust_lbl.text = "信任: %d  关系: %s" % [trust, rel_names.get(relation, relation)]
		trust_lbl.add_theme_color_override("font_color", Color(0.73, 0.63, 0.45, 1.0))
		header.add_child(trust_lbl)
		row_v.add_child(header)
		# 行动按钮
		var btns_hbox: HBoxContainer = HBoxContainer.new()
		btns_hbox.add_theme_constant_override("separation", 4)
		for action_id in actions.keys():
			var adef: Dictionary = actions[action_id]
			var btn: Button = Button.new()
			btn.text = adef.get("name", action_id)
			btn.custom_minimum_size = Vector2(60, 26)
			btn.pressed.connect(_on_diplo_action.bind(other_id, action_id))
			btns_hbox.add_child(btn)
		row_v.add_child(btns_hbox)

func _on_diplo_action(target: String, action_id: String) -> void:
	if GameManager.diplomatic_action(GameManager.player_faction, target, action_id):
		var aname: String = DataLoader.diplomacy["actions"][action_id].get("name", action_id)
		EventBus.float_text.emit("%s成功: %s" % [aname, target], Vector3.ZERO, Color.GREEN)
		_refresh_diplo_panel()
	else:
		EventBus.float_text.emit("外交行动失败（条件不足）", Vector3.ZERO, Color.RED)

func _toggle_settings_panel() -> void:
	if _settings_panel and _settings_panel.visible:
		_settings_panel.visible = false
		return
	if _settings_panel == null:
		_build_settings_panel()
	_settings_panel.visible = true

func _build_settings_panel() -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	_settings_panel.custom_minimum_size = Vector2(360, 280)
	var sp_style := StyleBoxFlat.new()
	sp_style.bg_color = Color(0.15, 0.11, 0.07, 0.97)
	sp_style.border_color = Color(0.79, 0.64, 0.29, 1.0)
	sp_style.border_width_left = 2
	sp_style.border_width_right = 2
	sp_style.border_width_top = 2
	sp_style.border_width_bottom = 2
	sp_style.corner_radius_top_left = 10
	sp_style.corner_radius_top_right = 10
	sp_style.corner_radius_bottom_left = 10
	sp_style.corner_radius_bottom_right = 10
	_settings_panel.add_theme_stylebox_override("panel", sp_style)
	add_child(_settings_panel)
	var tv: VBoxContainer = VBoxContainer.new()
	tv.set_anchors_preset(Control.PRESET_FULL_RECT)
	tv.add_theme_constant_override("separation", 10)
	_settings_panel.add_child(tv)
	var title_hbox: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "设置"
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	title.add_theme_font_size_override("font_size", 18)
	title_hbox.add_child(title)
	title_hbox.add_spacer(true)
	var close_btn: Button = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(30, 28)
	close_btn.pressed.connect(_toggle_settings_panel)
	title_hbox.add_child(close_btn)
	tv.add_child(title_hbox)
	# 游戏速度
	var speed_lbl: Label = Label.new()
	speed_lbl.text = "游戏速度"
	speed_lbl.add_theme_color_override("font_color", Color(0.73, 0.63, 0.45, 1.0))
	tv.add_child(speed_lbl)
	var speed_hbox: HBoxContainer = HBoxContainer.new()
	for spd in [0.5, 1.0, 2.0, 4.0]:
		var btn: Button = Button.new()
		btn.text = "x%.1f" % spd
		btn.custom_minimum_size = Vector2(60, 28)
		btn.pressed.connect(_on_speed_change.bind(spd))
		speed_hbox.add_child(btn)
	tv.add_child(speed_hbox)
	# 暂停
	var pause_btn: Button = Button.new()
	pause_btn.text = "暂停/继续"
	pause_btn.custom_minimum_size = Vector2(0, 32)
	pause_btn.pressed.connect(_on_toggle_pause)
	tv.add_child(pause_btn)
	# 税率
	var tax_lbl: Label = Label.new()
	tax_lbl.text = "税率"
	tax_lbl.add_theme_color_override("font_color", Color(0.73, 0.63, 0.45, 1.0))
	tv.add_child(tax_lbl)
	var tax_hbox: HBoxContainer = HBoxContainer.new()
	for rate in ["low", "medium", "high"]:
		var names: Dictionary = { "low": "低税", "medium": "中税", "high": "高税" }
		var btn: Button = Button.new()
		btn.text = names.get(rate, rate)
		btn.custom_minimum_size = Vector2(70, 28)
		btn.pressed.connect(_on_tax_change.bind(rate))
		tax_hbox.add_child(btn)
	tv.add_child(tax_hbox)

func _on_speed_change(spd: float) -> void:
	GameManager.set_game_speed(spd)
	EventBus.float_text.emit("速度 x%.1f" % spd, Vector3.ZERO, Color.CYAN)

func _on_toggle_pause() -> void:
	GameManager.set_paused(not GameManager.paused)
	EventBus.float_text.emit("已暂停" if GameManager.paused else "继续", Vector3.ZERO, Color.YELLOW)

func _on_tax_change(rate: String) -> void:
	GameManager.set_tax_rate(GameManager.player_faction, rate)
	var names: Dictionary = { "low": "低税", "medium": "中税", "high": "高税" }
	EventBus.float_text.emit("税率: %s" % names.get(rate, rate), Vector3.ZERO, Color.GOLD)

func _on_building_selected(building: Node) -> void:
	if not is_instance_valid(building):
		return
	var bdef: Dictionary = DataLoader.get_building_def(building.building_id)
	_cmd_name.text = bdef.get("name", building.building_id)
	# 显示建筑属性
	_set_stat(0, "血量", "%.0f/%.0f" % [building.hp, building.max_hp])
	_set_stat(1, "等级", "Lv%d" % building.def.get("level", 1))
	_set_stat(2, "人口", "+%d" % bdef.get("pop_provide", 0))
	_set_stat(3, "产出", "")
	_set_stat(4, "队列", "%d" % building.training_queue.size())
	_set_stat(5, "", "")
	# 显示可训练单位按钮
	_build_train_buttons(building)

func _on_building_deselected() -> void:
	_on_unit_deselected()

func _build_train_buttons(building: Node) -> void:
	_clear_cmd_btns()
	var bdef: Dictionary = DataLoader.get_building_def(building.building_id)
	var trainable: Array = bdef.get("trains", [])
	for unit_id in trainable:
		var udef: Dictionary = DataLoader.get_unit_def(unit_id)
		var btn: Button = Button.new()
		btn.text = udef.get("name", unit_id)
		btn.custom_minimum_size = Vector2(52, 38)
		btn.pressed.connect(_on_train_unit.bind(building, unit_id))
		_cmd_btns.add_child(btn)
	# 驻军卸载按钮
	if building.can_garrison:
		var unload_btn: Button = Button.new()
		var gcount: int = building.get_garrison_count()
		unload_btn.text = '驻军 %d/%d\n卸载' % [gcount, building.garrison_cap]
		unload_btn.custom_minimum_size = Vector2(52, 38)
		unload_btn.pressed.connect(_on_unload_garrison.bind(building))
		_cmd_btns.add_child(unload_btn)
	# 显示训练队列
	for item in building.training_queue:
		var unit_id: String = item["unit_id"]
		var udef: Dictionary = DataLoader.get_unit_def(unit_id)
		var btn: Button = Button.new()
		var time_left: float = item.get("time_left", 0)
		btn.text = "%s %.0fs" % [udef.get("name", unit_id), time_left]
		btn.custom_minimum_size = Vector2(52, 38)
		btn.disabled = true
		_cmd_btns.add_child(btn)

func _on_train_unit(building: Node, unit_id: String) -> void:
	if building.train_unit(unit_id):
		var udef: Dictionary = DataLoader.get_unit_def(unit_id)
		EventBus.float_text.emit("训练: %s" % udef.get("name", unit_id), building.global_position + Vector3(0, 3, 0), Color.GREEN)
		_on_building_selected(building)
	else:
		EventBus.float_text.emit("无法训练", building.global_position + Vector3(0, 3, 0), Color.RED)

func _on_unload_garrison(building: Node) -> void:
	if is_instance_valid(building) and building.has_method("unload_all"):
		building.unload_all()
		_on_building_selected(building)

func _build_general_roster() -> void:
	_general_roster = HBoxContainer.new()
	_general_roster.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_general_roster.offset_left = 200
	_general_roster.offset_right = -200
	_general_roster.offset_top = 44
	_general_roster.offset_bottom = 70
	_general_roster.alignment = BoxContainer.ALIGNMENT_CENTER
	_general_roster.add_theme_constant_override("separation", 6)
	add_child(_general_roster)

func _refresh_general_roster() -> void:
	if _general_roster == null:
		return
	for child in _general_roster.get_children():
		child.queue_free()
	var player: String = GameManager.player_faction
	for u in GameManager.all_units:
		if is_instance_valid(u) and u.has_method("get_faction") and u.get_faction() == player and "is_general" in u and u.is_general:
			var gdef: Dictionary = DataLoader.get_general_def(u.general_id)
			var btn: Button = Button.new()
			var hp_pct: float = u.hp / u.max_hp if u.max_hp > 0 else 1.0
			var mp_pct: float = u.mp / u.max_mp if u.max_mp > 0 else 1.0
			btn.text = "%s\n%.0f%% %.0f%%" % [gdef.get("name", "?"), hp_pct * 100, mp_pct * 100]
			btn.custom_minimum_size = Vector2(72, 28)
			btn.pressed.connect(_on_general_roster_click.bind(u))
			_general_roster.add_child(btn)

func _on_general_roster_click(general: Node) -> void:
	if is_instance_valid(general):
		var sel: SelectionManager = get_node_or_null("/root/Main/SelectionManager")
		if sel:
			sel.select_unit(general)
func _connect_signals() -> void:
	EventBus.resources_changed.connect(_on_resources_changed)
	EventBus.float_text.connect(_on_float_text)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.units_selected.connect(_on_units_selected)
	EventBus.unit_deselected.connect(_on_unit_deselected)
	EventBus.building_selected.connect(_on_building_selected)
	EventBus.building_deselected.connect(_on_building_deselected)
	EventBus.government_upgraded.connect(_on_government_upgraded)
	EventBus.tech_researched.connect(_on_tech_researched)

func _on_resources_changed(_faction: String) -> void:
	_update_resource_bar()

func _on_government_upgraded(_faction: String, _level: int) -> void:
	_update_age_bar(_age_bar.get_child(0))

func _on_tech_researched(_faction: String, _tech_id: String) -> void:
	_update_resource_bar()
	_refresh_tech_panel()
	_update_age_bar(_age_bar.get_child(0))

func _on_unit_selected(unit: Node) -> void:
	_show_unit_info(unit)

func _on_units_selected(units: Array) -> void:
	if units.size() > 0:
		_show_unit_info(units[0])
		# 显示选中数量
		_cmd_name.text = "%s x%d" % [DataLoader.get_unit_def(units[0].unit_id).get("name", units[0].unit_id), units.size()]

func _on_unit_deselected() -> void:
	_cmd_name.text = "未选中"
	if _cmd_hp_bar:
		_cmd_hp_bar.value = 0
	if _cmd_mp_bar:
		_cmd_mp_bar.value = 0
		_cmd_mp_bar.visible = false
	_clear_stats()
	_clear_cmd_btns()

func _show_build_menu() -> void:
	_clear_cmd_btns()
	var buildings: Dictionary = DataLoader.buildings.get("buildings", {})
	var gov_level: int = GameManager.get_government_level(GameManager.player_faction)
	var count: int = 0
	for building_id in buildings.keys():
		if count >= 12:
			break
		var bdef: Dictionary = buildings[building_id]
		if bdef.get("government_req", 1) > gov_level:
			continue
		if building_id in ["government", "wall_inner", "wall_outer", "wall_fort"]:
			continue
		var cb: Button = Button.new()
		cb.text = bdef.get("name", building_id)
		cb.custom_minimum_size = Vector2(44, 38)
		cb.pressed.connect(_on_build_pressed.bind(building_id))
		_cmd_btns.add_child(cb)
		count += 1
	# 修理提示按钮
	var repair_btn: Button = Button.new()
	repair_btn.text = '修理'
	repair_btn.custom_minimum_size = Vector2(44, 38)
	repair_btn.pressed.connect(_on_repair_hint)
	_cmd_btns.add_child(repair_btn)

func _on_repair_hint() -> void:
	EventBus.float_text.emit('右键点击受损建筑进行修理', Vector3.ZERO, Color.CYAN)

func _on_build_pressed(building_id: String) -> void:
	if has_node("/root/Main"):
		get_node("/root/Main").start_build_mode(building_id)

func _show_unit_info(unit: Node) -> void:
	if not is_instance_valid(unit):
		return
	var udef: Dictionary = DataLoader.get_unit_def(unit.unit_id)
	_cmd_name.text = udef.get("name", unit.unit_id)
	# HP/MP 条
	if _cmd_hp_bar:
		var hp_pct: float = unit.hp / unit.max_hp if unit.max_hp > 0 else 1.0
		_cmd_hp_bar.value = hp_pct * 100.0
	if _cmd_mp_bar and "mp" in unit and "max_mp" in unit:
		var mp_pct: float = unit.mp / unit.max_mp if unit.max_mp > 0 else 1.0
		_cmd_mp_bar.value = mp_pct * 100.0
		_cmd_mp_bar.visible = true
	else:
		_cmd_mp_bar.visible = false
	_set_stat(0, "攻", "%.0f" % unit.atk)
	_set_stat(1, "防", "%.0f" % unit.defense)
	_set_stat(2, "攻速", "%.1f" % unit.atk_speed)
	_set_stat(3, "移速", "%.1f" % unit.move_speed)
	_set_stat(4, "士气", "%.0f" % unit.morale)
	_set_stat(5, "等级", "Lv%d" % unit.level)
	# 农夫显示建造菜单
	if unit.unit_id == "peasant":
		_show_build_menu()
	else:
		_build_cmd_btns(unit)

func _set_stat(index: int, label_str: String, value_str: String) -> void:
	if index >= _cmd_stats.get_child_count():
		return
	var stat_panel: Panel = _cmd_stats.get_child(index)
	if stat_panel.get_child_count() > 0:
		var sv: VBoxContainer = stat_panel.get_child(0)
		if sv.get_child_count() >= 2:
			(sv.get_child(1) as Label).text = value_str

func _clear_stats() -> void:
	for i in range(6):
		_set_stat(i, "", "0")

func _build_cmd_btns(unit: Node) -> void:
	_clear_cmd_btns()
	var udef: Dictionary = DataLoader.get_unit_def(unit.unit_id)
	var cmd_list: Array = udef.get("commands", ["move", "attack", "stop"])
	for cmd_id in cmd_list:
		var cb: Button = Button.new()
		var labels: Dictionary = {
			"move": "移", "attack": "攻", "stop": "停",
			"gather": "采", "return": "返", "patrol": "巡",
			"formation": "阵", "rally": "旗"
		}
		cb.text = labels.get(cmd_id, cmd_id)
		cb.custom_minimum_size = Vector2(44, 38)
		cb.pressed.connect(_on_cmd_btn.bind(cmd_id, unit))
		_cmd_btns.add_child(cb)

func _clear_cmd_btns() -> void:
	for child in _cmd_btns.get_children():
		child.queue_free()

func _on_cmd_btn(cmd_id: String, unit: Node) -> void:
	match cmd_id:
		"stop": unit.state = Unit.State.IDLE
		_: EventBus.float_text.emit("指令: %s" % cmd_id, unit.global_position + Vector3(0, 2, 0), Color.CYAN)

func _on_float_text(text: String, position: Vector3, color: Color) -> void:
	if position == Vector3.ZERO:
		_show_center_text(text, color)
		return
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 100
	add_child(label)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		var screen_pos: Vector2 = camera.unproject_position(position)
		label.position = screen_pos
		label.position.y -= 20
	var tween: Tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 30, 1.0)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

func _show_center_text(text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-100, -50)
	label.size = Vector2(200, 30)
	add_child(label)
	var tween: Tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 40, 1.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(label.queue_free)

func _process(_delta: float) -> void:
	_draw_minimap()
	_refresh_general_roster()

func _draw_minimap() -> void:
	if _minimap_canvas:
		_minimap_canvas.queue_redraw()

func _on_minimap_draw() -> void:
	if not _minimap_canvas:
		return
	_minimap_canvas.draw_rect(Rect2(Vector2.ZERO, _minimap_canvas.size), Color(0.11, 0.09, 0.07, 1.0))
	var map_size: Vector2i = GameManager.map_size
	var mm_size: Vector2 = _minimap_canvas.size
	var scale: Vector2 = Vector2(mm_size.x / float(map_size.x), mm_size.y / float(map_size.y))
	# 绘制资源点
	for rn in GameManager.resource_nodes:
		if not is_instance_valid(rn):
			continue
		var gp: Vector2i = GameManager.grid.world_to_grid(rn.global_position)
		var px: Vector2 = Vector2(float(gp.x) * scale.x, float(gp.y) * scale.y)
		var c: Color = Color(0.8, 0.6, 0.3, 1.0)
		if rn.resource_type == "wood":
			c = Color(0.3, 0.5, 0.2, 1.0)
		elif rn.resource_type == "stone":
			c = Color(0.6, 0.6, 0.6, 1.0)
		elif rn.resource_type == "food":
			c = Color(0.8, 0.7, 0.2, 1.0)
		_minimap_canvas.draw_rect(Rect2(px - Vector2(1, 1), Vector2(2, 2)), c)
	# 绘制村庄
	for v in GameManager.villages:
		if not is_instance_valid(v):
			continue
		var gp: Vector2i = GameManager.grid.world_to_grid(v.global_position)
		var px: Vector2 = Vector2(float(gp.x) * scale.x, float(gp.y) * scale.y)
		var vc: Color = Color(0.8, 0.8, 0.8, 1.0) if v.village_owner == "" else _get_faction_color(v.village_owner)
		_minimap_canvas.draw_rect(Rect2(px - Vector2(2, 2), Vector2(4, 4)), vc)
		_minimap_canvas.draw_rect(Rect2(px - Vector2(3, 3), Vector2(6, 6)), Color(vc.r, vc.g, vc.b, 0.4))
	# 绘制野马
	for h in GameManager.wild_horses:
		if not is_instance_valid(h):
			continue
		var gp: Vector2i = GameManager.grid.world_to_grid(h.global_position)
		var px: Vector2 = Vector2(float(gp.x) * scale.x, float(gp.y) * scale.y)
		var hc: Color = Color(0.9, 0.9, 0.9, 1.0)
		match h.horse_type:
			"red": hc = Color(0.8, 0.2, 0.1, 1.0)
			"chitu": hc = Color(1.0, 0.1, 0.0, 1.0)
			"dilu": hc = Color(0.1, 0.1, 0.1, 1.0)
		_minimap_canvas.draw_circle(px, 2.0, hc)

	# 绘制建筑
	for b in GameManager.all_buildings:
		if not is_instance_valid(b):
			continue
		var gp: Vector2i = GameManager.grid.world_to_grid(b.global_position)
		var px: Vector2 = Vector2(float(gp.x) * scale.x, float(gp.y) * scale.y)
		var fac_color: Color = _get_faction_color(b.faction)
		_minimap_canvas.draw_rect(Rect2(px - Vector2(2, 2), Vector2(4, 4)), fac_color)
	# 绘制单位
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		var gp: Vector2i = GameManager.grid.world_to_grid(u.global_position)
		var px: Vector2 = Vector2(float(gp.x) * scale.x, float(gp.y) * scale.y)
		var fac_color: Color = _get_faction_color(u.faction)
		_minimap_canvas.draw_circle(px, 1.5, fac_color)
	# 绘制相机视口框
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam and GameManager.grid:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var cam_pos: Vector3 = cam.global_position
		var half_w: float = viewport_size.x * 0.012
		var half_h: float = viewport_size.y * 0.012
		var left_w: Vector3 = cam_pos - cam.global_transform.basis.x * half_w
		var right_w: Vector3 = cam_pos + cam.global_transform.basis.x * half_w
		var tl_world: Vector3 = left_w + cam.global_transform.basis.z * half_h
		var br_world: Vector3 = right_w - cam.global_transform.basis.z * half_h
		var tl_g: Vector2i = GameManager.grid.world_to_grid(tl_world)
		var br_g: Vector2i = GameManager.grid.world_to_grid(br_world)
		var tl_px: Vector2 = Vector2(float(tl_g.x) * scale.x, float(tl_g.y) * scale.y)
		var br_px: Vector2 = Vector2(float(br_g.x) * scale.x, float(br_g.y) * scale.y)
		_minimap_canvas.draw_rect(Rect2(tl_px, br_px - tl_px), Color(1.0, 1.0, 1.0, 0.0), false, 1.5)

func _get_faction_color(faction_id: String) -> Color:
	match faction_id:
		"wei": return Color(0.73, 0.23, 0.23, 1.0)
		"shu": return Color(0.31, 0.68, 0.31, 1.0)
		"wu": return Color(0.29, 0.50, 0.81, 1.0)
		_: return Color(0.73, 0.63, 0.45, 1.0)

func get_build_menu() -> PanelContainer:
	return null



















