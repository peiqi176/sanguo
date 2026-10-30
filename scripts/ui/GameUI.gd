extends CanvasLayer
## GameUI — AoE4 风格主 HUD
## 顶部资源条、左上官府等级、右上科技按钮、底部命令面板、右下小地图

var _resource_bar: PanelContainer
var _res_container: HBoxContainer
var _res_value_labels: Dictionary = {}  # res_id -> 数值 Label（资源栏只建一次，原地更新）
var _meta_value_labels: Dictionary = {} # pop/morale/horse/village -> Label
var _hud_meta_timer: float = 0.0       # 非资源数值刷新节流
var _age_bar: PanelContainer
var _topright: HBoxContainer
var _cmd_panel: PanelContainer
var _cmd_portrait: Panel
var _cmd_name: Label
var _cmd_hp_bar: ProgressBar = null
var _cmd_mp_bar: ProgressBar = null
var _cmd_stats: GridContainer
var _cmd_btns: GridContainer
var _build_page: int = 0                # 建造菜单分页（31 种建筑不可能一页放下）
var _build_cost_label: Label = null     # 建造模式下跟随鼠标的"所需资源"标签
var _minimap: Control
var _minimap_bg: ColorRect
var _minimap_canvas: Control
var _float_texts: Array = []            # 当前活跃的世界坐标飘字 Label
var _float_text_max: int = 40            # 并发飘字上限：超出丢弃，避免大战时压垮 UI
var _tech_panel: PanelContainer = null
var _tech_branch_tabs: HBoxContainer = null
var _tech_list: VBoxContainer = null
var _tech_progress: ProgressBar = null
var _cur_branch: String = "civilian"
var _elite_panel: PanelContainer = null
var _elite_list: VBoxContainer = null
var _office_panel: PanelContainer = null
var _office_list: VBoxContainer = null
var _diplo_panel: PanelContainer = null
var _diplo_list: VBoxContainer = null
var _settings_panel: PanelContainer = null
var _general_roster: HBoxContainer = null
var _roster_refresh_timer: float = 0.0   # 名册刷新节流计时
var _roster_signature: String = ""       # 上一次名册签名，无变化则跳过重绘
var _relic_hud: VBoxContainer = null      # 🪨 古碑任务进度条（右上常驻）
var _relic_refresh_timer: float = 0.0
var _transport_panel: PanelContainer = null
var _transport_src: OptionButton = null
var _transport_dst: OptionButton = null
var _transport_res: OptionButton = null
var _transport_amt: OptionButton = null
var _transport_sources: Array = []
var _transport_targets: Array = []

# 官府等级名称
const AGE_NAMES = ["县府", "郡治", "州牧", "王城"]

# 🏛 政务 5 岗（与 GameManager.get_official_bonus 对应）
const OFFICES = [
	{"id": "政务", "desc": "税收 +20%"},
	{"id": "科技", "desc": "研究速度 +25%"},
	{"id": "祭祀", "desc": "灾祸 -60% / 采集 +15%"},
	{"id": "治安", "desc": "守军防御 +20%"},
	{"id": "通商", "desc": "贸易价 +25%"},
]

func _ready() -> void:
	_build_ui()
	_connect_signals()
	_build_general_roster()  # 一次性创建武将名册容器（原遗漏导致名册从不显示）

func _build_ui() -> void:
	# === 顶部中央资源条（AoE4 风格：深色长条 + 铜金描边 + 图标大数字）===
	_resource_bar = PanelContainer.new()
	_resource_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_resource_bar.offset_left = 236
	_resource_bar.offset_right = -236
	_resource_bar.offset_top = 6
	_resource_bar.offset_bottom = 50
	var res_style := StyleBoxFlat.new()
	res_style.bg_color = Color(0.07, 0.055, 0.04, 0.94)
	res_style.border_color = Color(0.72, 0.57, 0.28, 0.95)
	res_style.border_width_left = 1
	res_style.border_width_right = 1
	res_style.border_width_top = 1
	res_style.border_width_bottom = 1
	res_style.corner_radius_top_left = 2
	res_style.corner_radius_top_right = 2
	res_style.corner_radius_bottom_left = 2
	res_style.corner_radius_bottom_right = 2
	res_style.shadow_color = Color(0, 0, 0, 0.55)
	res_style.shadow_size = 8
	res_style.shadow_offset = Vector2(0, 3)
	_resource_bar.add_theme_stylebox_override("panel", res_style)
	add_child(_resource_bar)
	# 顶部一条细高光，模拟金属条受光面（套一层 Control，避免被 PanelContainer 拉伸）
	var res_overlay := Control.new()
	res_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	res_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resource_bar.add_child(res_overlay)
	var res_glint := ColorRect.new()
	res_glint.color = Color(0.95, 0.85, 0.62, 0.18)
	res_glint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	res_glint.offset_left = 2
	res_glint.offset_right = -2
	res_glint.offset_top = 1
	res_glint.offset_bottom = 2
	res_glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res_overlay.add_child(res_glint)
	var res_inner := MarginContainer.new()
	res_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	res_inner.add_theme_constant_override("margin_left", 14)
	res_inner.add_theme_constant_override("margin_right", 14)
	res_inner.add_theme_constant_override("margin_top", 4)
	res_inner.add_theme_constant_override("margin_bottom", 4)
	_resource_bar.add_child(res_inner)
	_res_container = HBoxContainer.new()
	_res_container.add_theme_constant_override("separation", 10)
	_res_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_res_container.alignment = BoxContainer.ALIGNMENT_CENTER
	res_inner.add_child(_res_container)
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
	_topright.offset_left = -220
	_topright.offset_right = -10
	_topright.offset_top = 8
	_topright.offset_bottom = 40
	_topright.alignment = BoxContainer.ALIGNMENT_END
	add_child(_topright)
	for btext in ["科", "特", "政", "外", "调", "设"]:
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

	# === 右上：古碑任务进度（常驻，无古碑时隐藏）===
	_relic_hud = VBoxContainer.new()
	_relic_hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_relic_hud.offset_left = -250
	_relic_hud.offset_right = -10
	_relic_hud.offset_top = 46
	_relic_hud.offset_bottom = 200
	_relic_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relic_hud.visible = false
	add_child(_relic_hud)

	# === 底部命令面板（傲世三国风格大面板）===
	_cmd_panel = PanelContainer.new()
	_cmd_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_cmd_panel.offset_left = 10
	_cmd_panel.offset_right = -206
	_cmd_panel.offset_top = -210
	_cmd_panel.offset_bottom = -10
	var cmd_style := StyleBoxFlat.new()
	cmd_style.bg_color = Color(0.24, 0.17, 0.10, 0.96)
	cmd_style.border_color = Color(0.82, 0.66, 0.30, 1.0)
	cmd_style.border_width_top = 2
	cmd_style.border_width_left = 2
	cmd_style.border_width_right = 2
	cmd_style.border_width_bottom = 2
	_cmd_panel.add_theme_stylebox_override("panel", cmd_style)
	add_child(_cmd_panel)
	var cmd_hbox: HBoxContainer = HBoxContainer.new()
	cmd_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	cmd_hbox.add_theme_constant_override("separation", 10)
	_cmd_panel.add_child(cmd_hbox)

	# 左侧立绘区（加大）
	_cmd_portrait = Panel.new()
	_cmd_portrait.custom_minimum_size = Vector2(130, 0)
	_cmd_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.10, 0.07, 0.03, 1.0)
	p_style.border_color = Color(0.55, 0.42, 0.18, 1.0)
	p_style.border_width_left = 1
	p_style.border_width_right = 1
	p_style.border_width_top = 1
	p_style.border_width_bottom = 1
	_cmd_portrait.add_theme_stylebox_override("panel", p_style)
	cmd_hbox.add_child(_cmd_portrait)
	var pv_vbox: VBoxContainer = VBoxContainer.new()
	pv_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	pv_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_cmd_portrait.add_child(pv_vbox)
	var pv_icon: Label = Label.new()
	pv_icon.text = "⚔"
	pv_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv_icon.add_theme_font_size_override("font_size", 48)
	pv_vbox.add_child(pv_icon)
	_cmd_name = Label.new()
	_cmd_name.text = "未选中"
	_cmd_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cmd_name.add_theme_font_size_override("font_size", 14)
	_cmd_name.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	pv_vbox.add_child(_cmd_name)
	# HP 条
	_cmd_hp_bar = ProgressBar.new()
	_cmd_hp_bar.custom_minimum_size = Vector2(110, 10)
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
	_cmd_mp_bar.custom_minimum_size = Vector2(110, 8)
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

	# 中间属性区（双列加大）
	_cmd_stats = GridContainer.new()
	_cmd_stats.columns = 2
	_cmd_stats.custom_minimum_size = Vector2(180, 0)
	_cmd_stats.add_theme_constant_override("h_separation", 6)
	_cmd_stats.add_theme_constant_override("v_separation", 6)
	cmd_hbox.add_child(_cmd_stats)
	_add_stat("攻", "0")
	_add_stat("防", "0")
	_add_stat("攻速", "0")
	_add_stat("移速", "0")
	_add_stat("士气", "0")
	_add_stat("等级", "Lv1")

	# 右侧命令按钮区（8列 3行 = 24 按钮，傲世三国大按钮风格）
	var cmd_btns_container: VBoxContainer = VBoxContainer.new()
	cmd_btns_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_hbox.add_child(cmd_btns_container)
	_cmd_btns = GridContainer.new()
	_cmd_btns.columns = 8
	_cmd_btns.add_theme_constant_override("h_separation", 5)
	_cmd_btns.add_theme_constant_override("v_separation", 5)
	_cmd_btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_btns_container.add_child(_cmd_btns)
	# 占位按钮（24 个，够三行）
	for i in range(24):
		var cb: Button = Button.new()
		cb.text = ""
		cb.custom_minimum_size = Vector2(48, 44)
		var cbs := StyleBoxFlat.new()
		cbs.bg_color = Color(0.18, 0.13, 0.07, 1.0)
		cbs.border_color = Color(0.45, 0.34, 0.16, 1.0)
		cbs.border_width_left = 1
		cbs.border_width_right = 1
		cbs.border_width_top = 1
		cbs.border_width_bottom = 1
		cbs.corner_radius_top_left = 4
		cbs.corner_radius_top_right = 4
		cbs.corner_radius_bottom_left = 4
		cbs.corner_radius_bottom_right = 4
		cb.add_theme_stylebox_override("normal", cbs)
		cb.disabled = true
		_cmd_btns.add_child(cb)

	# === 右下「疆域图」小地图框（AoE4 风格：铜金外框 + 内嵌暗底 + 标题栏）===
	_minimap = PanelContainer.new()
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -200
	_minimap.offset_right = -10
	_minimap.offset_top = -240
	_minimap.offset_bottom = -10
	var mm_style := StyleBoxFlat.new()
	mm_style.bg_color = Color(0.07, 0.055, 0.04, 0.97)
	mm_style.border_color = Color(0.76, 0.60, 0.30, 1.0)
	mm_style.border_width_left = 2
	mm_style.border_width_right = 2
	mm_style.border_width_top = 2
	mm_style.border_width_bottom = 2
	mm_style.corner_radius_top_left = 3
	mm_style.corner_radius_top_right = 3
	mm_style.corner_radius_bottom_left = 3
	mm_style.corner_radius_bottom_right = 3
	mm_style.shadow_color = Color(0, 0, 0, 0.6)
	mm_style.shadow_size = 10
	mm_style.shadow_offset = Vector2(0, 4)
	_minimap.add_theme_stylebox_override("panel", mm_style)
	add_child(_minimap)

	# 内衬：再一圈细金线，做出"画框"层次（套一层 Control，保证 5px 内缩生效）
	var mm_overlay := Control.new()
	mm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	mm_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.add_child(mm_overlay)
	var mm_inner := PanelContainer.new()
	mm_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	mm_inner.offset_left = 5
	mm_inner.offset_right = -5
	mm_inner.offset_top = 5
	mm_inner.offset_bottom = -5
	var mm_inner_style := StyleBoxFlat.new()
	mm_inner_style.bg_color = Color(0.05, 0.045, 0.032, 1.0)
	mm_inner_style.border_color = Color(0.44, 0.34, 0.17, 1.0)
	mm_inner_style.border_width_left = 1
	mm_inner_style.border_width_right = 1
	mm_inner_style.border_width_top = 1
	mm_inner_style.border_width_bottom = 1
	mm_inner.add_theme_stylebox_override("panel", mm_inner_style)
	mm_overlay.add_child(mm_inner)

	var mm_vbox := VBoxContainer.new()
	mm_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	mm_vbox.add_theme_constant_override("separation", 3)
	mm_inner.add_child(mm_vbox)

	# 标题栏：左「疆域图」，右势力图例
	var title_row := HBoxContainer.new()
	title_row.custom_minimum_size = Vector2(0, 20)
	title_row.add_theme_constant_override("separation", 4)
	var mm_title := Label.new()
	mm_title.text = "疆 域 图"
	mm_title.add_theme_font_size_override("font_size", 12)
	mm_title.add_theme_color_override("font_color", Color(0.86, 0.74, 0.45))
	mm_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(mm_title)
	title_row.add_spacer(true)
	for info in [["#b93a3a","魏"],["#4fae4f","蜀"],["#4a7fce","吴"]]:
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 10)
		dot.add_theme_color_override("font_color", Color.from_string(info[0], Color.WHITE))
		dot.tooltip_text = str(info[1])
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(dot)
	mm_vbox.add_child(title_row)

	# 标题下的细金线
	var mm_rule := ColorRect.new()
	mm_rule.color = Color(0.62, 0.49, 0.24, 0.55)
	mm_rule.custom_minimum_size = Vector2(0, 1)
	mm_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mm_vbox.add_child(mm_rule)

	# 小地图画布（独立 Control：负责绘制与点击跳转）
	_minimap_canvas = Control.new()
	_minimap_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_minimap_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_minimap_canvas.custom_minimum_size = Vector2(176, 176)
	_minimap_canvas.clip_contents = true
	_minimap_canvas.draw.connect(_on_minimap_draw)
	_minimap_canvas.gui_input.connect(_on_minimap_gui_input)
	mm_vbox.add_child(_minimap_canvas)

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
	# 🔥 性能：资源栏只构建一次，之后原地更新数字。
	# 旧实现每次都 queue_free 全部子节点再重建 ~24 个控件，
	# 而资源变化信号每帧可来多次（建筑产出/征兵/交易），曾造成每秒 ~100ms 卡顿尖峰。
	if _res_container == null:
		return
	var faction: String = GameManager.player_faction
	if _res_value_labels.is_empty():
		_build_resource_bar(faction)
	for res_id in _res_value_labels:
		_res_value_labels[res_id].text = "%.0f" % GameManager.get_resource(faction, res_id)
	_update_hud_meta()

## 首次构建资源栏芯片（AoE4 风格：图标 + 大号数值，名称走 tooltip，不带文字标签）
## 资源数值存进 _res_value_labels；人口/民心/马匹/村庄存进 _meta_value_labels
func _build_resource_bar(faction: String) -> void:
	var res_defs: Dictionary = DataLoader.factions.get("resources", {})
	var main_res: Array = ["food", "wood", "iron", "gold", "bun", "wine"]
	var icon_chars: Dictionary = {"food": "粮", "wood": "木", "iron": "铁", "gold": "钱", "bun": "包", "wine": "酒"}
	for i in range(main_res.size()):
		var res_id: String = str(main_res[i])
		var info: Dictionary = res_defs.get(res_id, {})
		if i > 0:
			_res_container.add_child(_mk_res_divider())
		var val_lbl: Label = _mk_res_chip(
			str(icon_chars.get(res_id, "?")),
			Color.from_string(str(info.get("color", "#e8d7a8")), Color(0.91, 0.84, 0.66)),
			"%s：库存（顶部「调」可跨村调拨）" % str(info.get("name", res_id))
		)
		_res_value_labels[res_id] = val_lbl

	# 人口 / 民心 / 马匹 / 村庄：与资源同条，靠金色竖线分组
	var pop: Dictionary = GameManager.get_population(faction)
	_res_container.add_child(_mk_res_divider())
	_meta_value_labels["pop"] = _mk_res_chip(
		"民", Color(0.62, 0.82, 1.0),
		"人口（已用/上限）。上限靠建民居、升官府提高",
		"%d/%d" % [pop["used"], pop["cap"]], Color(0.62, 0.82, 1.0)
	)
	_res_container.add_child(_mk_res_divider())
	_meta_value_labels["morale"] = _mk_res_chip(
		"心", Color(0.5, 0.9, 0.5),
		"民心。过低会减税收、掉人口",
		"%.0f" % GameManager.get_morale(faction), Color(0.5, 0.9, 0.5)
	)
	_res_container.add_child(_mk_res_divider())
	_meta_value_labels["horse"] = _mk_res_chip(
		"马", Color(0.9, 0.7, 0.3),
		"可用马匹。骑乘中的马已被占用，下马后归还",
		"%d" % int(GameManager.get_resource(faction, "horse")), Color(0.9, 0.7, 0.3)
	)
	_res_container.add_child(_mk_res_divider())
	_meta_value_labels["village"] = _mk_res_chip(
		"村", Color(0.8, 0.8, 0.6),
		"已占领村庄数。村庄提供补给半径与征收",
		"%d" % _count_my_villages(faction), Color(0.8, 0.8, 0.6)
	)

## 一个资源芯片：带框单字图标 + 数值，返回数值 Label（供原地刷新）
## 用中文单字而非 emoji：默认字体缺 emoji 时会渲染成空白，单字在任何字体下都稳定
func _mk_res_chip(icon_char: String, icon_color: Color, tooltip: String, value_text: String = "0", value_color: Color = Color(0.96, 0.9, 0.75)) -> Label:
	var chip: HBoxContainer = HBoxContainer.new()
	chip.add_theme_constant_override("separation", 5)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.tooltip_text = tooltip
	var tile: PanelContainer = PanelContainer.new()
	tile.custom_minimum_size = Vector2(21, 21)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tile_style := StyleBoxFlat.new()
	tile_style.bg_color = Color(0.15, 0.12, 0.08, 1.0)
	tile_style.border_color = Color(icon_color.r, icon_color.g, icon_color.b, 0.7)
	tile_style.set_border_width_all(1)
	tile_style.set_corner_radius_all(3)
	tile.add_theme_stylebox_override("panel", tile_style)
	var icon_lbl: Label = Label.new()
	icon_lbl.text = icon_char
	icon_lbl.add_theme_font_size_override("font_size", 12)
	icon_lbl.add_theme_color_override("font_color", icon_color)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(icon_lbl)
	chip.add_child(tile)
	var val_lbl: Label = Label.new()
	val_lbl.name = "val"
	val_lbl.text = value_text
	val_lbl.add_theme_font_size_override("font_size", 16)
	val_lbl.add_theme_color_override("font_color", value_color)
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(val_lbl)
	_res_container.add_child(chip)
	return val_lbl

## 资源条分组竖线（AoE4 的铜金分隔）
func _mk_res_divider() -> Control:
	var sep := ColorRect.new()
	sep.color = Color(0.72, 0.57, 0.28, 0.30)
	sep.custom_minimum_size = Vector2(1, 26)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

func _count_my_villages(faction: String) -> int:
	var n: int = 0
	for v in GameManager.villages:
		if is_instance_valid(v) and v.village_owner == faction:
			n += 1
	return n

## 人口/民心/马匹/村庄这类"非资源"数值需要按时间刷新（资源变化信号不会触发）
func _update_hud_meta() -> void:
	if _meta_value_labels.is_empty():
		return
	var faction: String = GameManager.player_faction
	var pop: Dictionary = GameManager.get_population(faction)
	if _meta_value_labels.has("pop"):
		var used: int = int(pop["used"])
		var cap: int = int(pop["cap"])
		var pl: Label = _meta_value_labels["pop"]
		pl.text = "%d/%d" % [used, cap]
		# 人口顶满：变橙提醒玩家别再造人了
		pl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35) if used >= cap else Color(0.62, 0.82, 1.0))
	if _meta_value_labels.has("morale"):
		_meta_value_labels["morale"].text = "%.0f" % GameManager.get_morale(faction)
	if _meta_value_labels.has("horse"):
		_meta_value_labels["horse"].text = "%d" % int(GameManager.get_resource(faction, "horse"))
	if _meta_value_labels.has("village"):
		_meta_value_labels["village"].text = "%d" % _count_my_villages(faction)

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
		"特": _toggle_elite_panel()
		"政": _toggle_office_panel()
		"外": _toggle_diplo_panel()
		"调": _toggle_transport_panel()
		"设": _toggle_settings_panel()

# ==================== 🪨 古碑任务 HUD ====================

func _refresh_relic_hud() -> void:
	if _relic_hud == null:
		return
	for c in _relic_hud.get_children():
		_relic_hud.remove_child(c)
		c.queue_free()
	var any: bool = false
	for r in GameManager.relics:
		if not is_instance_valid(r):
			continue
		if not r.has_method("get_relic_name") or not r.has_method("get_hud_line"):
			continue
		any = true
		var lb: Label = Label.new()
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.add_theme_font_size_override("font_size", 13)
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lb.add_theme_constant_override("outline_size", 3)
		lb.text = str(r.get_hud_line())
		lb.add_theme_color_override("font_color", r.get_hud_color())
		_relic_hud.add_child(lb)
	_relic_hud.visible = any

func _on_relic_completed(_faction: String, _relic_id: String, relic_name: String) -> void:
	_show_center_text("🏆 古碑任务：%s" % relic_name, Color(0.95, 0.82, 0.35))

# ==================== 📦 资源调拨面板 ====================

func _toggle_transport_panel() -> void:
	if _transport_panel and _transport_panel.visible:
		_transport_panel.visible = false
		return
	if _transport_panel == null:
		_build_transport_panel()
	_refresh_transport_panel()
	_transport_panel.visible = true

func _build_transport_panel() -> void:
	_transport_panel = PanelContainer.new()
	_transport_panel.set_anchors_preset(Control.PRESET_CENTER)
	_transport_panel.custom_minimum_size = Vector2(380, 250)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.15, 0.11, 0.07, 0.97)
	st.border_color = Color(0.79, 0.64, 0.29, 1.0)
	st.border_width_left = 2
	st.border_width_right = 2
	st.border_width_top = 2
	st.border_width_bottom = 2
	st.corner_radius_top_left = 10
	st.corner_radius_top_right = 10
	st.corner_radius_bottom_left = 10
	st.corner_radius_bottom_right = 10
	_transport_panel.add_theme_stylebox_override("panel", st)
	add_child(_transport_panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_transport_panel.add_child(vb)
	var title: Label = Label.new()
	title.text = "📦 资源调拨（村庄 → 城池 / 村庄）"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63))
	vb.add_child(title)
	var row_src: HBoxContainer = HBoxContainer.new()
	var l1: Label = Label.new()
	l1.text = "来源村庄"
	l1.custom_minimum_size = Vector2(72, 0)
	_transport_src = OptionButton.new()
	_transport_src.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_src.add_child(l1)
	row_src.add_child(_transport_src)
	vb.add_child(row_src)
	var row_dst: HBoxContainer = HBoxContainer.new()
	var l2: Label = Label.new()
	l2.text = "目标"
	l2.custom_minimum_size = Vector2(72, 0)
	_transport_dst = OptionButton.new()
	_transport_dst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_dst.add_child(l2)
	row_dst.add_child(_transport_dst)
	vb.add_child(row_dst)
	var row_res: HBoxContainer = HBoxContainer.new()
	var l3: Label = Label.new()
	l3.text = "资源"
	l3.custom_minimum_size = Vector2(72, 0)
	_transport_res = OptionButton.new()
	for nm in ["粮草", "木材", "铁锭", "金币"]:
		_transport_res.add_item(nm)
	_transport_amt = OptionButton.new()
	for nm2 in ["50", "100", "200"]:
		_transport_amt.add_item(nm2)
	_transport_amt.select(1)
	row_res.add_child(l3)
	row_res.add_child(_transport_res)
	row_res.add_child(_transport_amt)
	vb.add_child(row_res)
	var go: Button = Button.new()
	go.text = "🚚 出发"
	go.custom_minimum_size = Vector2(0, 34)
	go.pressed.connect(_on_transport_go)
	vb.add_child(go)
	var hint: Label = Label.new()
	hint.text = "每个民夫载 50；被劫损失 50% 货物"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.75, 0.70, 0.60))
	vb.add_child(hint)
	var close: Button = Button.new()
	close.text = "关闭"
	close.pressed.connect(func(): _transport_panel.visible = false)
	vb.add_child(close)

func _refresh_transport_panel() -> void:
	if _transport_src == null:
		return
	_transport_sources.clear()
	_transport_targets.clear()
	_transport_src.clear()
	_transport_dst.clear()
	for v in GameManager.villages:
		if is_instance_valid(v) and v.village_owner == GameManager.player_faction:
			_transport_sources.append(v)
			_transport_src.add_item("%s Lv%d" % [v.village_id, v.level])
	# 目标：己方村庄 + 官府
	for v in GameManager.villages:
		if is_instance_valid(v) and v.village_owner == GameManager.player_faction:
			_transport_targets.append({"name": v.village_id, "pos": v.global_position})
			_transport_dst.add_item("%s Lv%d" % [v.village_id, v.level])
	var gov = GameManager.get_government(GameManager.player_faction)
	if gov != null and is_instance_valid(gov):
		_transport_targets.append({"name": "官府", "pos": gov.global_position})
		_transport_dst.add_item("官府（城池）")
	if _transport_sources.is_empty():
		_transport_src.add_item("（无己方村庄）")
	else:
		_transport_src.select(0)
	if not _transport_targets.is_empty():
		_transport_dst.select(0)
	_transport_src.disabled = _transport_sources.is_empty()
	_transport_dst.disabled = _transport_targets.is_empty()

func _on_transport_go() -> void:
	if _transport_src == null:
		return
	var si: int = _transport_src.selected
	var di: int = _transport_dst.selected
	if si < 0 or si >= _transport_sources.size() or di < 0 or di >= _transport_targets.size():
		return
	var src = _transport_sources[si]
	if not is_instance_valid(src):
		return
	var tgt: Dictionary = _transport_targets[di]
	if src.global_position.distance_to(tgt["pos"]) < 6.0:
		EventBus.float_text.emit("来源与目标过近，无需调拨", src.global_position + Vector3(0, 3, 0), Color.GRAY)
		return
	var res_ids: Array = ["food", "wood", "iron", "gold"]
	var rid: String = str(res_ids[clampi(_transport_res.selected, 0, 3)])
	var amounts: Array = [50.0, 100.0, 200.0]
	var amt: float = float(amounts[clampi(_transport_amt.selected, 0, 2)])
	var cap: float = float(DataLoader.logistics.get("transport", {}).get("capacity_per_peasant", 50.0))
	var peas: int = maxi(1, int(ceil(amt / maxf(cap, 1.0))))
	var team = src.send_transport(tgt["pos"], {rid: amt}, peas)
	if team == null:
		EventBus.float_text.emit("调拨失败：资源/民夫不足或超载", Vector3.ZERO, Color.RED)
	else:
		EventBus.float_text.emit("📦 运输队出发", src.global_position + Vector3(0, 3, 0), Color.YELLOW)

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
		var btn_585: Button = _tech_branch_tabs.get_child(i)
		var branch_ids: Array = ["civilian", "military", "siege"]
		if i < branch_ids.size():
			btn_585.modulate = Color(1, 1, 1, 1) if branch_ids[i] == _cur_branch else Color(0.6, 0.6, 0.6, 1)
	# 清空列表
	for child in _tech_list.get_children():
		child.queue_free()
	var branches: Dictionary = DataLoader.tech.get("branches", {})
	if not branches.has(_cur_branch):
		return
	var techs: Dictionary = branches[_cur_branch].get("techs", {})
	var researched: Array = GameManager.factions[faction].researched_techs
	var researching: Dictionary = GameManager.factions[faction].researching
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
		var research_btn: Button = Button.new()
		research_btn.custom_minimum_size = Vector2(70, 32)
		if is_done:
			research_btn.text = "已研究"
			research_btn.disabled = true
		elif researching.has(tech_id):
			research_btn.text = "研究中"
			research_btn.disabled = true
		elif gov_level < tdef.get("gov_req", 1):
			research_btn.text = "官府不足"
			research_btn.disabled = true
		elif not GameManager.can_afford(faction, cost):
			research_btn.text = "资源不足"
			research_btn.disabled = true
		else:
			research_btn.text = "研究"
			research_btn.pressed.connect(_on_research_tech.bind(_cur_branch, tech_id))
		row.add_child(research_btn)
		_tech_list.add_child(row)

func _on_research_tech(branch: String, tech_id: String) -> void:
	if GameManager.research_tech(GameManager.player_faction, branch, tech_id):
		EventBus.float_text.emit("开始研究: %s" % tech_id, Vector3.ZERO, Color.YELLOW)
		_refresh_tech_panel()
		_update_age_bar(_age_bar.get_child(0))
	else:
		EventBus.float_text.emit("研究失败", Vector3.ZERO, Color.RED)

# ==================== 特殊科技面板（13选3） ====================

func _toggle_elite_panel() -> void:
	if _elite_panel and _elite_panel.visible:
		_elite_panel.visible = false
		return
	if _elite_panel == null:
		_build_elite_panel()
	_refresh_elite_panel()
	_elite_panel.visible = true

func _build_elite_panel() -> void:
	_elite_panel = PanelContainer.new()
	_elite_panel.set_anchors_preset(Control.PRESET_CENTER)
	_elite_panel.custom_minimum_size = Vector2(600, 460)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.09, 0.06, 0.97)
	style.border_color = Color(0.85, 0.70, 0.30, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	_elite_panel.add_theme_stylebox_override("panel", style)
	add_child(_elite_panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 8)
	_elite_panel.add_child(vb)
	# 标题栏
	var title_hbox: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "🧪 特殊科技 · 十三选三"
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	title.add_theme_font_size_override("font_size", 18)
	title_hbox.add_child(title)
	title_hbox.add_spacer(true)
	var close_btn: Button = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(30, 28)
	close_btn.pressed.connect(_toggle_elite_panel)
	title_hbox.add_child(close_btn)
	vb.add_child(title_hbox)
	# 列表滚动区
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_elite_list = VBoxContainer.new()
	_elite_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_elite_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_elite_list)

func _refresh_elite_panel() -> void:
	if _elite_panel == null or not _elite_panel.visible:
		return
	for child in _elite_list.get_children():
		child.queue_free()
	var faction: String = GameManager.player_faction
	var unlocked: bool = GameManager.is_elite_unlocked(faction)
	var rules: Dictionary = DataLoader.tech_elite.get("research_rules", {})
	var max_sel: int = int(rules.get("max_selected", 3))
	var selected: Dictionary = GameManager.elite_techs.get(faction, {})
	var cost: Dictionary = rules.get("cost", {})
	var cost_str: String = ""
	for ck in cost.keys():
		cost_str += "%s:%d " % [ck, cost[ck]]
	# 状态行
	var status: Label = Label.new()
	if unlocked:
		status.text = "已选 %d/%d   |   每次消耗 %s" % [selected.size(), max_sel, cost_str]
	else:
		status.text = "🔒 未解锁：需 官府 Lv2 + 翰林院（%s）" % cost_str
	status.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5, 1.0) if unlocked else Color(0.85, 0.5, 0.4, 1.0))
	status.add_theme_font_size_override("font_size", 13)
	_elite_list.add_child(status)
	var cats: Dictionary = DataLoader.tech_elite.get("categories", {})
	for cat_key in cats.keys():
		var cat: Dictionary = cats[cat_key]
		var cat_lbl: Label = Label.new()
		cat_lbl.text = "── %s ──" % cat.get("name", cat_key)
		cat_lbl.add_theme_color_override("font_color", Color(0.8, 0.75, 0.55, 1.0))
		cat_lbl.add_theme_font_size_override("font_size", 13)
		_elite_list.add_child(cat_lbl)
		for t in cat.get("techs", []):
			var tid: String = t.get("id", "")
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var info_v: VBoxContainer = VBoxContainer.new()
			info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var name_lbl: Label = Label.new()
			var is_sel: bool = selected.has(tid)
			name_lbl.text = "%s%s" % ["✅ " if is_sel else "○ ", t.get("name", tid)]
			name_lbl.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0) if is_sel else Color(0.8, 0.78, 0.68, 1.0))
			info_v.add_child(name_lbl)
			var desc_lbl: Label = Label.new()
			desc_lbl.text = t.get("desc", "")
			desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6, 1.0))
			desc_lbl.add_theme_font_size_override("font_size", 11)
			info_v.add_child(desc_lbl)
			row.add_child(info_v)
			var sel_btn: Button = Button.new()
			sel_btn.custom_minimum_size = Vector2(72, 32)
			if is_sel:
				sel_btn.text = "已激活"
				sel_btn.disabled = true
			elif not unlocked:
				sel_btn.text = "未解锁"
				sel_btn.disabled = true
			elif selected.size() >= max_sel:
				sel_btn.text = "已选满"
				sel_btn.disabled = true
			elif not GameManager.can_afford(faction, cost):
				sel_btn.text = "资源不足"
				sel_btn.disabled = true
			else:
				sel_btn.text = "激活"
				sel_btn.pressed.connect(_on_elite_tech_pressed.bind(tid))
			row.add_child(sel_btn)
			_elite_list.add_child(row)

func _on_elite_tech_pressed(tech_id: String) -> void:
	if GameManager.select_elite_tech(GameManager.player_faction, tech_id):
		_refresh_elite_panel()
	else:
		EventBus.float_text.emit("无法激活该特殊科技", Vector3.ZERO, Color.RED)

# ==================== 政务任命面板（5岗） ====================

func _toggle_office_panel() -> void:
	if _office_panel and _office_panel.visible:
		_office_panel.visible = false
		return
	if _office_panel == null:
		_build_office_panel()
	_refresh_office_panel()
	_office_panel.visible = true

func _build_office_panel() -> void:
	_office_panel = PanelContainer.new()
	_office_panel.set_anchors_preset(Control.PRESET_CENTER)
	_office_panel.custom_minimum_size = Vector2(520, 400)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.09, 0.97)
	style.border_color = Color(0.72, 0.68, 0.35, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	_office_panel.add_theme_stylebox_override("panel", style)
	add_child(_office_panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 8)
	_office_panel.add_child(vb)
	var title_hbox: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "🏛 政务任命 · 五岗"
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	title.add_theme_font_size_override("font_size", 18)
	title_hbox.add_child(title)
	title_hbox.add_spacer(true)
	var close_btn: Button = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(30, 28)
	close_btn.pressed.connect(_toggle_office_panel)
	title_hbox.add_child(close_btn)
	vb.add_child(title_hbox)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_office_list = VBoxContainer.new()
	_office_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_office_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_office_list)

func _refresh_office_panel() -> void:
	if _office_panel == null or not _office_panel.visible:
		return
	for child in _office_list.get_children():
		child.queue_free()
	var faction: String = GameManager.player_faction
	var generals: Array = GameManager.get_all_generals_for_faction(faction)
	var appts: Dictionary = GameManager.appointed_officials.get(faction, {})
	var hint: Label = Label.new()
	hint.text = "任命武将担任要职（内政<60 时效果减半）；武将每月 +50 政务经验"
	hint.add_theme_color_override("font_color", Color(0.72, 0.70, 0.58, 1.0))
	hint.add_theme_font_size_override("font_size", 11)
	_office_list.add_child(hint)
	for off in OFFICES:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_lbl: Label = Label.new()
		name_lbl.text = "%s · %s" % [off["id"], off["desc"]]
		name_lbl.custom_minimum_size = Vector2(260, 0)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.65, 1.0))
		name_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(name_lbl)
		var opt: OptionButton = OptionButton.new()
		opt.custom_minimum_size = Vector2(180, 30)
		opt.add_item("空缺")
		for g in generals:
			opt.add_item(str(g.general_def.get("name", g.name)))
		var cur = appts.get(off["id"], null)
		var idx: int = 0
		for i in range(generals.size()):
			if generals[i] == cur:
				idx = i + 1
				break
		opt.selected = idx
		opt.item_selected.connect(_on_office_selected.bind(off["id"], generals))
		row.add_child(opt)
		_office_list.add_child(row)

func _on_office_selected(index: int, office_type: String, generals: Array) -> void:
	var faction: String = GameManager.player_faction
	var appts: Dictionary = GameManager.appointed_officials.get(faction, {})
	if index <= 0:
		appts.erase(office_type)
	else:
		appts[office_type] = generals[index - 1]
	GameManager.appointed_officials[faction] = appts
	if index <= 0:
		EventBus.float_text.emit("%s 已卸任" % office_type, Vector3.ZERO, Color.YELLOW)
	else:
		EventBus.float_text.emit("任命 %s → %s" % [generals[index - 1].general_def.get("name", ""), office_type], Vector3.ZERO, Color.GOLD)
	_refresh_office_panel.call_deferred()

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
		var btn_789: Button = Button.new()
		btn_789.text = "x%.1f" % spd
		btn_789.custom_minimum_size = Vector2(60, 28)
		btn_789.pressed.connect(_on_speed_change.bind(spd))
		speed_hbox.add_child(btn_789)
	tv.add_child(speed_hbox)
	# 暂停
	var pause_btn: Button = Button.new()
	pause_btn.text = "暂停/继续"
	pause_btn.custom_minimum_size = Vector2(0, 32)
	pause_btn.pressed.connect(_on_toggle_pause)
	tv.add_child(pause_btn)
	# 🔥 v4 税收调节滑条（0.1-0.5 金/人，>40% 红警告）
	var tax_title: Label = Label.new()
	tax_title.text = "💴 税收调节（金/人/月，最大0.5）"
	tax_title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	tv.add_child(tax_title)
	var tax_slider: HSlider = HSlider.new()
	tax_slider.custom_minimum_size = Vector2(300, 24)
	tax_slider.min_value = 0.1
	tax_slider.max_value = 0.5
	tax_slider.step = 0.05
	tax_slider.value = GameManager.get_tax_rate(GameManager.player_faction) if GameManager.get_tax_rate else 0.15
	tv.add_child(tax_slider)
	var tax_val_lbl: Label = Label.new()
	tax_val_lbl.text = "当前: %.2f 金/人/月" % tax_slider.value
	tax_val_lbl.add_theme_color_override("font_color", Color(0.96, 0.86, 0.63, 1.0))
	tv.add_child(tax_val_lbl)
	var tax_warn_lbl: Label = Label.new()
	tax_warn_lbl.visible = false
	tax_warn_lbl.text = "⚠️ 税收 >0.40 会导致人口负增长！"
	tax_warn_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 1.0))
	tv.add_child(tax_warn_lbl)
	tax_slider.value_changed.connect(func(v: float):
		tax_val_lbl.text = "当前: %.2f 金/人/月" % v
		tax_warn_lbl.visible = v > 0.40
		GameManager.set_tax_rate_value(GameManager.player_faction, v)
		EventBus.float_text.emit("税收 %.2f 金/人" % v, Vector3.ZERO, Color.GOLD)
	)

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
	# 🔥 v4 农夫指派制显示
	var wr_cur: int = building.workers.size() if "workers" in building else 0
	var wr_max: int = int(bdef.get("workers_max", 0))
	var wr_info: String = "%d/%d" % [wr_cur, wr_max] if wr_max > 0 else "—"
	_set_stat(0, "血量", "%.0f/%.0f" % [building.hp, building.max_hp])
	_set_stat(1, "等级", "Lv%d" % building.def.get("level", 1))
	_set_stat(2, "农夫", wr_info)
	# 产出显示
	var prod_str: String = ""
	if bdef.has("produces"):
		for pk in bdef["produces"].keys():
			prod_str += "%s %.1f/s " % [pk, float(bdef["produces"][pk]) * (float(wr_cur)/float(max(wr_max,1)) if wr_max>0 else 1.0)]
	if bdef.has("consumes"):
		for ck in bdef["consumes"].keys():
			prod_str += "(耗%s%.1f) " % [ck, float(bdef["consumes"][ck])]
	# 🏭 作坊类：直接显示配方（2谷+1肉→1包子）与单农夫效率
	if bdef.has("recipe") and building.has_method("get_recipe_text"):
		prod_str = building.get_recipe_text()
	_set_stat(3, "产出", prod_str if prod_str else "—")
	var queue_info: String = "%d训练 / %d入岗" % [building.training_queue.size(), wr_cur] if "training_queue" in building else str(wr_cur)
	_set_stat(4, "队列", queue_info)
	_set_stat(5, "造价", "")
	if bdef.has("cost"):
		var cost_str: String = ""
		for ck2 in bdef["cost"].keys():
			cost_str += "%s:%d " % [ck2, int(bdef["cost"][ck2])]
		_set_stat(5, "造价", cost_str)
	# 🔥 v4 重写按钮区
	_build_building_buttons(building)

func _on_building_deselected() -> void:
	_on_unit_deselected()

# 🔥 v4 新建筑按钮区（农夫指派制 + 训练 + 离岗 + 驻军）
func _build_building_buttons(building: Node) -> void:
	_clear_cmd_btns()
	var bdef: Dictionary = DataLoader.get_building_def(building.building_id)
	
	# --- 🔥 农夫指派：入岗 / 离岗 ---
	var wr_max: int = int(bdef.get("workers_max", 0))
	if wr_max > 0 and "workers" in building:
		# 入岗按钮（选中农夫时可点）
		var assign_btn: Button = Button.new()
		assign_btn.text = "👤 入岗"
		assign_btn.custom_minimum_size = Vector2(52, 38)
		assign_btn.tooltip_text = "选中农夫后点击此按钮指派到该建筑"
		assign_btn.pressed.connect(_on_assign_worker.bind(building))
		_cmd_btns.add_child(assign_btn)
		# 离岗按钮（全员离岗）
		var unassign_btn: Button = Button.new()
		unassign_btn.text = "🚪 离岗"
		unassign_btn.custom_minimum_size = Vector2(52, 38)
		unassign_btn.tooltip_text = "让所有农夫离开该建筑"
		unassign_btn.pressed.connect(_on_unassign_all.bind(building))
		_cmd_btns.add_child(unassign_btn)
	
	# --- 🔥 训练按钮（consumes_peasant 建筑不显示训练按钮，靠入岗自动训练）---
	var consumes_pea: bool = bdef.get("consumes_peasant", false)
	var trainable: Array = bdef.get("trains", [])
	if not consumes_pea and not trainable.is_empty():
		for unit_id in trainable:
			var udef: Dictionary = DataLoader.get_unit_def(unit_id)
			# 📖 科技未解锁的兵种不显示
			var req_tech: String = str(udef.get("requires_tech", ""))
			if req_tech != "" and not GameManager.is_tech_researched(building.faction, req_tech):
				continue
			# 🏛 官府等级不足的高级兵种不显示
			if GameManager.get_government_level(building.faction) < int(udef.get("gov_req", udef.get("government_req", 1))):
				continue
			var btn: Button = Button.new()
			btn.text = udef.get("name", unit_id)
			btn.custom_minimum_size = Vector2(52, 38)
			btn.pressed.connect(_on_train_unit.bind(building, unit_id))
			_cmd_btns.add_child(btn)
	
	# --- 🎖️ 兵种进阶改在「选中基础兵」的指令面板里（选中建筑时单位选择已被清空）---

	# 驻军卸载按钮
	if building.can_garrison:
		var gcount: int = building.get_garrison_count()
		var unload_btn: Button = Button.new()
		unload_btn.text = '驻军 %d/%d\n卸载' % [gcount, building.garrison_cap]
		unload_btn.custom_minimum_size = Vector2(52, 38)
		unload_btn.pressed.connect(_on_unload_garrison.bind(building))
		_cmd_btns.add_child(unload_btn)
	
	# 🔥 消耗农夫训练模式显示入岗进度（_worker_training）
	if "consumes_peasant" in building and building.consumes_peasant and "_worker_training" in building:
		var widx: int = 0
		for wid in building._worker_training.keys():
			var tleft: float = building._worker_training[wid]
			var tbtn: Button = Button.new()
			tbtn.text = "训练中 %.0fs" % tleft
			tbtn.custom_minimum_size = Vector2(52, 38)
			tbtn.disabled = true
			_cmd_btns.add_child(tbtn)
			widx += 1
			if widx >= 6:
				break

	# --- 🏪 服务建筑：市场 / 寺庙 / 客栈 / 营帐打包 ---
	match building.building_id:
		"market":
			var mk_btn: Button = Button.new()
			mk_btn.text = "🏪 市场交易"
			mk_btn.custom_minimum_size = Vector2(72, 38)
			mk_btn.pressed.connect(func() -> void: _open_service_popup("market", building))
			_cmd_btns.add_child(mk_btn)
		"temple":
			var tm_btn: Button = Button.new()
			tm_btn.text = "🛕 祭祀"
			tm_btn.custom_minimum_size = Vector2(72, 38)
			tm_btn.pressed.connect(func() -> void: _open_service_popup("temple", building))
			_cmd_btns.add_child(tm_btn)
		"inn":
			var inn_btn: Button = Button.new()
			inn_btn.text = "🏮 招募武将"
			inn_btn.custom_minimum_size = Vector2(72, 38)
			inn_btn.pressed.connect(func() -> void: _open_service_popup("inn", building))
			_cmd_btns.add_child(inn_btn)
		"tent":
			var pk_btn: Button = Button.new()
			pk_btn.text = "📦 打包搬迁"
			pk_btn.custom_minimum_size = Vector2(72, 38)
			pk_btn.tooltip_text = "拆除营帐并返还全部建造资源，然后在目标地点重建"
			pk_btn.pressed.connect(func() -> void:
				if building.pack_up():
					_on_building_deselected())
			_cmd_btns.add_child(pk_btn)

func _on_assign_worker(building: Node) -> void:
	"""把当前选中的农夫指派到该建筑"""
	var sel = get_node_or_null("/root/Main/SelectionManager")
	if sel == null:
		EventBus.float_text.emit("请先选中农夫", Vector3.ZERO, Color.RED)
		return
	var sel_units: Array = sel.selected_units
	var assigned: int = 0
	for u in sel_units:
		if not is_instance_valid(u):
			continue
		if u.unit_id != "peasant":
			continue
		if not building.has_method("assign_worker"):
			continue
		if building.assign_worker(u):
			assigned += 1
			# 自动让农夫走到建筑旁开始工作
			if u.has_method("command_work"):
				u.command_work(building)
	if assigned > 0:
		EventBus.float_text.emit("指派 %d 名农夫入岗" % assigned, building.global_position + Vector3(0, 3, 0), Color.GREEN)
	else:
		EventBus.float_text.emit("无可用农夫或岗位已满", building.global_position + Vector3(0, 3, 0), Color.RED)
	_on_building_selected(building)

func _on_unassign_all(building: Node) -> void:
	"""让所有农夫离岗"""
	if building.has_method("unassign_all_workers"):
		building.unassign_all_workers()
		EventBus.float_text.emit("全员离岗", building.global_position + Vector3(0, 3, 0), Color.YELLOW)
	_on_building_selected(building)

func _on_train_unit(building: Node, unit_id: String) -> void:
	if building.train_unit(unit_id):
		var udef: Dictionary = DataLoader.get_unit_def(unit_id)
		EventBus.float_text.emit("训练: %s" % udef.get("name", unit_id), building.global_position + Vector3(0, 3, 0), Color.GREEN)
		_on_building_selected(building)
	else:
		EventBus.float_text.emit("无法训练", building.global_position + Vector3(0, 3, 0), Color.RED)

func _on_promote_pressed(unit: Node, camp: Node, to_id: String) -> void:
	"""兵种进阶：需在训练营旁，点一下原地进阶；距离远则先自动前往"""
	if not is_instance_valid(unit) or not is_instance_valid(camp):
		return
	if unit.global_position.distance_to(camp.global_position) > 8.0:
		unit.command_move(camp.global_position + Vector3(2, 0, 0))
		EventBus.float_text.emit("前往训练营进阶", unit.global_position + Vector3(0, 3, 0), Color.CYAN)
		return
	var old_pos: Vector3 = unit.global_position
	if not camp.promote_unit(unit, to_id):
		return
	# 进阶后旧单位已释放，选中新单位
	var new_unit = null
	var best: float = 9999.0
	for u in GameManager.all_units:
		if not is_instance_valid(u) or u.unit_id != to_id or u.faction != camp.faction:
			continue
		var d: float = u.global_position.distance_to(old_pos)
		if d < best:
			best = d
			new_unit = u
	var sel = get_tree().root.find_child("SelectionManager", true, false)
	if sel != null and new_unit != null:
		sel.select_unit(new_unit)
		_show_unit_info(new_unit)

func _promotion_target_for(unit: Node) -> String:
	"""查该兵种可进阶到的目标 ID（读 training_camp 的 promotion_map）"""
	var tdef: Dictionary = DataLoader.get_building_def("training_camp")
	var pmap: Dictionary = tdef.get("promotion_map", {})
	return str(pmap.get(unit.unit_id, ""))

func _find_training_camp(faction_id: String):
	"""找一个已建成的本方训练营"""
	for b in GameManager.all_buildings:
		if not is_instance_valid(b):
			continue
		if b.building_id == "training_camp" and b.faction == faction_id and b.build_progress >= 1.0:
			return b
	return null

func _find_mustering_hall(faction_id: String):
	"""找一个已建成的本方点将台（用于士兵手动晋升武将）"""
	for b in GameManager.all_buildings:
		if not is_instance_valid(b):
			continue
		if b.building_id == "mustering_hall" and b.faction == faction_id and b.build_progress >= 1.0:
			return b
	return null

func _on_promote_general_pressed(unit: Node, hall: Node) -> void:
	"""士兵手动晋升武将：需站在点将台旁，距离远则先自动前往"""
	if not is_instance_valid(unit) or not is_instance_valid(hall):
		return
	if unit.global_position.distance_to(hall.global_position) > 8.0:
		unit.command_move(hall.global_position + Vector3(2, 0, 0))
		EventBus.float_text.emit("前往点将台晋升", unit.global_position + Vector3(0, 3, 0), Color.CYAN)
		return
	var old_pos: Vector3 = unit.global_position
	if not hall.promote_soldier_to_general(unit):
		return
	# 晋升后旧单位已释放，选中离原位置最近的新武将
	var new_gen = null
	var best: float = 9999.0
	for u in GameManager.all_units:
		if not is_instance_valid(u) or not ("is_general" in u) or not u.is_general:
			continue
		if u.faction != hall.faction:
			continue
		var d: float = u.global_position.distance_to(old_pos)
		if d < best:
			best = d
			new_gen = u
	var sel = get_tree().root.find_child("SelectionManager", true, false)
	if sel != null and new_gen != null:
		sel.select_unit(new_gen)
		_show_unit_info(new_gen)

func _on_unload_garrison(building: Node) -> void:
	if is_instance_valid(building) and building.has_method("unload_all"):
		building.unload_all()
		_on_building_selected(building)

func _build_general_roster() -> void:
	_general_roster = HBoxContainer.new()
	_general_roster.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_general_roster.offset_left = 200
	_general_roster.offset_right = -200
	_general_roster.offset_top = 56
	_general_roster.offset_bottom = 84
	_general_roster.alignment = BoxContainer.ALIGNMENT_CENTER
	_general_roster.add_theme_constant_override("separation", 6)
	add_child(_general_roster)

func _refresh_general_roster() -> void:
	if _general_roster == null:
		return
	var player: String = GameManager.player_faction
	# 构建签名：武将 id + 取整后的 HP%/MP%，无变化则跳过重绘（避免每帧销毁重建）
	var sig_parts: Array = []
	var generals: Array = []
	for u in GameManager.all_units:
		if is_instance_valid(u) and u.has_method("get_faction") and u.get_faction() == player and "is_general" in u and u.is_general:
			var hp_pct: int = int(u.hp / u.max_hp * 100) if u.max_hp > 0 else 100
			var mp_pct: int = int(u.mp / u.max_mp * 100) if u.max_mp > 0 else 100
			sig_parts.append("%s:%d:%d" % [u.general_id, hp_pct, mp_pct])
			generals.append(u)
	var new_sig: String = "|".join(sig_parts)
	if new_sig == _roster_signature:
		return
	_roster_signature = new_sig
	# 有变化才重建按钮
	for child in _general_roster.get_children():
		child.queue_free()
	for u in generals:
		var gdef: Dictionary = DataLoader.get_general_def(u.general_id)
		var gname: String = str(gdef.get("name", ""))
		if gname.is_empty():
			# 开局主将（如孙权）可能不在武将池配置里，避免名册上出现"?"
			gname = {"sunquan": "孙权", "liubei": "刘备", "caocao": "曹操"}.get(str(u.general_id), "主将")
		var btn: Button = Button.new()
		var hp_pct: float = u.hp / u.max_hp if u.max_hp > 0 else 1.0
		var mp_pct: float = u.mp / u.max_mp if u.max_mp > 0 else 1.0
		btn.text = "%s\n%.0f%% %.0f%%" % [gname, hp_pct * 100, mp_pct * 100]
		btn.custom_minimum_size = Vector2(72, 28)
		btn.pressed.connect(_on_general_roster_click.bind(u))
		_general_roster.add_child(btn)

func _on_general_roster_click(general: Node) -> void:
	if is_instance_valid(general):
		var sel = get_node_or_null("/root/Main/SelectionManager")
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
	EventBus.disaster_occurred.connect(_on_disaster_occurred)
	EventBus.relic_completed.connect(_on_relic_completed)

func _on_disaster_occurred(_disaster_id: String, disaster_name: String, victims: Array) -> void:
	"""灾祸公告：居中文字提示"""
	_show_center_text("⚠ 天灾·%s（受灾 %d 处）" % [disaster_name, victims.size()], Color(1.0, 0.45, 0.30))

func _on_resources_changed(faction: String) -> void:
	# 其他势力的资源变动与玩家资源栏无关，直接跳过（信号是按势力广播的）
	if faction != GameManager.player_faction:
		return
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
		# 显示选中数量（辎重车没有 unit_id，单独处理）
		if "unit_id" in units[0]:
			_cmd_name.text = "%s x%d" % [DataLoader.get_unit_def(units[0].unit_id).get("name", units[0].unit_id), units.size()]
		else:
			_cmd_name.text = "辎重车 x%d" % units.size()

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
	# 全部建筑都列出来，未解锁的置灰并写明原因（否则玩家不知道要先升官府/研究科技）
	# ⛔ is_neutral / category=natural 的是"地图生成的中立资源"（矿洞等），不进建造菜单——
	#   它们只能由地图摆出来，玩家不能造（用户 2026-10-24 明确）。
	var entries: Array = []
	for building_id in buildings.keys():
		if building_id in ["government", "wall_inner", "wall_outer", "wall_fort"]:
			continue
		var bdef: Dictionary = buildings[building_id]
		if bool(bdef.get("is_neutral", false)) or str(bdef.get("category", "")) == "natural":
			continue
		# ⛔ 官府 / 牌楼：开局自带，玩家不能自行建造（JSON 里 buildable = false）
		if bool(bdef.get("buildable", true)) == false:
			continue
		var lock_reason: String = ""
		var req_gov: int = int(bdef.get("government_req", 1))
		if req_gov > gov_level:
			lock_reason = "需官府 %d 级" % req_gov
		else:
			var rt: String = str(bdef.get("requires_tech", ""))
			if rt != "" and not GameManager.is_tech_researched(GameManager.player_faction, rt):
				lock_reason = "需科技：%s" % _tech_display_name(rt)
		entries.append({"id": building_id, "lock": lock_reason})
	var per_page: int = 11
	var page_count: int = maxi(1, int(ceil(float(entries.size()) / float(per_page))))
	_build_page = clampi(_build_page, 0, page_count - 1)
	var start: int = _build_page * per_page
	for i in range(start, mini(start + per_page, entries.size())):
		var entry: Dictionary = entries[i]
		var building_id: String = str(entry["id"])
		var bdef: Dictionary = buildings[building_id]
		var cb: Button = Button.new()
		cb.text = str(bdef.get("name", building_id))
		cb.custom_minimum_size = Vector2(44, 38)
		cb.disabled = str(entry["lock"]) != ""
		var lines: Array = []
		if str(entry["lock"]) != "":
			lines.append("🔒 " + str(entry["lock"]))
		var cost: Dictionary = bdef.get("cost", {})
		if not cost.is_empty():
			lines.append("造价: " + _cost_text(cost))
		cb.tooltip_text = "\n".join(lines)
		cb.pressed.connect(_on_build_pressed.bind(building_id))
		_cmd_btns.add_child(cb)
	# 分页导航
	if page_count > 1:
		var prev_btn: Button = Button.new()
		prev_btn.text = "◀"
		prev_btn.custom_minimum_size = Vector2(30, 38)
		prev_btn.disabled = _build_page <= 0
		prev_btn.pressed.connect(_on_build_page.bind(-1))
		_cmd_btns.add_child(prev_btn)
		var page_label: Label = Label.new()
		page_label.text = "%d/%d" % [_build_page + 1, page_count]
		_cmd_btns.add_child(page_label)
		var next_btn: Button = Button.new()
		next_btn.text = "▶"
		next_btn.custom_minimum_size = Vector2(30, 38)
		next_btn.disabled = _build_page >= page_count - 1
		next_btn.pressed.connect(_on_build_page.bind(1))
		_cmd_btns.add_child(next_btn)
	# 修理提示按钮
	var repair_btn: Button = Button.new()
	repair_btn.text = '修理'
	repair_btn.custom_minimum_size = Vector2(44, 38)
	repair_btn.pressed.connect(_on_repair_hint)
	_cmd_btns.add_child(repair_btn)

func _tech_display_name(tech_id: String) -> String:
	var branches: Dictionary = DataLoader.tech.get("branches", {})
	for branch in branches.values():
		var techs: Dictionary = branch.get("techs", {})
		if techs.has(tech_id):
			return str(techs[tech_id].get("name", tech_id))
	return tech_id

## 造价转中文（"wood 200" → "木材 200"）。建造菜单 tooltip 和建造模式跟随标签共用。
func _cost_text(cost: Dictionary) -> String:
	var names: Dictionary = {
		"food": "粮草", "wood": "木材", "iron": "铁锭",
		"gold": "金币", "bun": "草料", "wine": "酒",
		"stone": "石料",
	}
	var parts: Array = []
	for ck in cost.keys():
		parts.append("%s %d" % [names.get(ck, ck), int(cost[ck])])
	return " ".join(parts)

func _on_build_page(delta: int) -> void:
	_build_page += delta
	_show_build_menu()

func _on_repair_hint() -> void:
	EventBus.float_text.emit('右键点击受损建筑进行修理', Vector3.ZERO, Color.CYAN)

func _on_build_pressed(building_id: String) -> void:
	if has_node("/root/Main"):
		get_node("/root/Main").start_build_mode(building_id)

func _show_unit_info(unit: Node) -> void:
	if not is_instance_valid(unit):
		return
	# 🚚 辎重车（SupplyCart）没有 unit_id / atk / defense 等字段，单独走一条面板
	if not ("unit_id" in unit) and unit.has_method("command_setup"):
		_show_cart_info(unit)
		return
	var udef: Dictionary = DataLoader.get_unit_def(unit.unit_id)
	_cmd_name.text = "Lv%d %s" % [unit.level, udef.get("name", unit.unit_id)]
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
	# 🏃 体力 + 补给状态（只随时间衰减，圈内恢复 / 辎重车旁冻结）
	var st_txt: String = "%.0f" % unit.stamina
	var zone: String = str(unit.supply_state.get("zone_type", ""))
	var mode: String = str(unit.supply_state.get("mode", "none"))
	if mode == "hold":
		st_txt += " 🚚保"
	elif mode == "recover":
		st_txt += " 🏠%.1f/s" % float(unit.supply_state.get("recover_rate", 2.0))
	elif zone == "" and unit.stamina < 50.0:
		st_txt += " ⚠"
	_set_stat(5, "体力", st_txt)
	# 🚢 船只：把第 6 格换成载员
	if "passengers" in unit and "capacity" in unit and int(unit.capacity) > 0:
		_set_stat(5, "载员", "%d/%d" % [unit.passengers.size(), int(unit.capacity)])
	# 农夫显示建造菜单
	if unit.unit_id == "peasant":
		_show_build_menu()
	else:
		_build_cmd_btns(unit)

## 🚚 辎重车面板：车没有攻防字段，只显示载粮/载酒/光环/状态 + 扎营按钮
func _show_cart_info(cart: Node) -> void:
	_cmd_name.text = "辎重车"
	if _cmd_hp_bar:
		_cmd_hp_bar.value = (cart.hp / cart.max_hp * 100.0) if cart.max_hp > 0.0 else 100.0
	if _cmd_mp_bar:
		_cmd_mp_bar.visible = false
	_set_stat(0, "载粮", "%.0f" % cart.bun)
	_set_stat(1, "载酒", "%.0f" % cart.wine)
	_set_stat(2, "光环", "%.0f 格" % cart.aura_radius)
	var st_names: Array = ["收起", "行进", "扎营中", "已扎营", "打包中"]
	_set_stat(3, "状态", str(st_names[clampi(int(cart.state), 0, 4)]))
	_set_stat(4, "驻扎", "%d 人" % cart.garrisoned_units.size())
	_set_stat(5, "效果", "旁侧体力不降")
	_clear_cmd_btns()
	var setup_btn: Button = Button.new()
	setup_btn.text = "⛺ 扎营"
	setup_btn.custom_minimum_size = Vector2(64, 38)
	setup_btn.tooltip_text = "3 秒后就地转换为营帐：附近体力恢复 +4/s（城池/村庄只有 +2/s），并可训练 T1 兵"
	setup_btn.pressed.connect(_on_cart_setup.bind(cart))
	_cmd_btns.add_child(setup_btn)
	var pack_btn: Button = Button.new()
	pack_btn.text = "📦 打包"
	pack_btn.custom_minimum_size = Vector2(64, 38)
	pack_btn.tooltip_text = "取消扎营（若已在扎营中）"
	pack_btn.pressed.connect(_on_cart_pack.bind(cart))
	_cmd_btns.add_child(pack_btn)

func _on_cart_setup(cart: Node) -> void:
	if is_instance_valid(cart) and cart.has_method("command_setup"):
		cart.command_setup()
		_show_unit_info(cart)

func _on_cart_pack(cart: Node) -> void:
	if is_instance_valid(cart) and cart.has_method("command_pack"):
		cart.command_pack()
		_show_unit_info(cart)

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
		# 🔥 v4 士兵行为模式按钮（主动进攻/防守/睡觉/坚守）
	if not ("is_general" in unit and unit.is_general):
		# 士兵才显示（枚举值：ACTIVE_ATTACK=0, DEFENSE=1, SLEEP=2, HOLD=3）
		var b_labels: Dictionary = {
			0: "⚔ 主动",
			1: "🛡 防守",
			2: "💤 睡觉",
			3: "🚩 坚守"
		}
		for bmode in [0, 1, 2, 3]:
			var bb: Button = Button.new()
			bb.text = b_labels[bmode]
			bb.custom_minimum_size = Vector2(44, 38)
			if "behavior_mode" in unit and unit.behavior_mode == bmode:
				var active_style := StyleBoxFlat.new()
				active_style.bg_color = Color(0.30, 0.60, 0.30, 1.0)
				active_style.border_color = Color(0.85, 0.70, 0.30, 1.0)
				active_style.border_width_left = 2
				active_style.border_width_right = 2
				active_style.border_width_top = 2
				active_style.border_width_bottom = 2
				bb.add_theme_stylebox_override("normal", active_style)
			bb.pressed.connect(_on_behavior_btn.bind(bmode, unit))
			_cmd_btns.add_child(bb)

	# 🎖️ 兵种进阶：选中刀/枪/弓兵时显示（需本方训练营）
	var promote_to: String = _promotion_target_for(unit)
	if promote_to != "":
		var camp = _find_training_camp(unit.faction)
		var to_name: String = str(DataLoader.get_unit_def(promote_to).get("name", promote_to))
		var pbtn: Button = Button.new()
		pbtn.custom_minimum_size = Vector2(64, 38)
		if camp == null:
			pbtn.text = "🎖 需训练营"
			pbtn.disabled = true
			pbtn.tooltip_text = "先建造训练营（官府2级 + 研究兵力晋升）"
		else:
			pbtn.text = "🎖 进阶为%s" % to_name
			pbtn.tooltip_text = "在训练营旁点击即可进阶，消耗进阶兵种造价，保留等级与经验"
			pbtn.pressed.connect(_on_promote_pressed.bind(unit, camp, promote_to))
		_cmd_btns.add_child(pbtn)

	# 🎖️ 晋升武将：Lv5+ 士兵 + 本方点将台
	if unit.has_method("can_promote_to_general") and unit.can_promote_to_general():
		var hall = _find_mustering_hall(unit.faction)
		var gbtn: Button = Button.new()
		gbtn.custom_minimum_size = Vector2(64, 38)
		if hall == null:
			gbtn.text = "🎖 需点将台"
			gbtn.disabled = true
			gbtn.tooltip_text = "建造点将台（官府3级）后可自主晋升武将；5级30% / 6级60% / 7级100% 自动晋升"
		else:
			gbtn.text = "🎖 晋升武将"
			gbtn.tooltip_text = "在点将台旁晋升（花费 200 金），晋升后降 2 级并获得 1 个通用武将技"
			gbtn.pressed.connect(_on_promote_general_pressed.bind(unit, hall))
		_cmd_btns.add_child(gbtn)

	# 🐎 骑乘 / 下马
	_add_mount_button(unit)
	# ⚔ 战斗姿态（冲锋就绪 / 架枪中）
	_add_stance_label(unit)
	# 🍞 出征备粮（士兵携带包子）
	_add_ration_button(unit)
	# 🚢 船只下船
	_add_naval_button(unit)

func _add_naval_button(unit: Node) -> void:
	if not unit.has_method("unload_passengers") or not ("passengers" in unit):
		return
	var cap: int = int(unit.capacity) if "capacity" in unit else 0
	var nbtn: Button = Button.new()
	nbtn.custom_minimum_size = Vector2(64, 38)
	nbtn.text = "🚢 下船 %d/%d" % [unit.passengers.size(), cap]
	nbtn.tooltip_text = "把船上部队就近卸到陆地"
	nbtn.disabled = unit.passengers.is_empty()
	nbtn.pressed.connect(func():
		if not is_instance_valid(unit):
			return
		var n: int = unit.unload_passengers()
		EventBus.float_text.emit("下船 %d 人" % n, unit.global_position + Vector3(0, 3, 0), Color.CYAN)
		_show_unit_info(unit))
	_cmd_btns.add_child(nbtn)

func _add_stance_label(unit: Node) -> void:
	if not ("charge_ready" in unit) or not ("braced" in unit):
		return
	var txt: String = ""
	if unit.braced:
		txt = "⛏ 架枪中"
	elif unit.charge_ready:
		txt = "🐎 冲锋就绪"
	if txt == "":
		return
	var lb: Label = Label.new()
	lb.text = txt
	lb.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	lb.tooltip_text = "架枪：静止 2 秒后受骑兵冲锋伤害减半并反弹 30%；冲锋：骑兵连续冲刺 6 米后首击 ×1.8"
	_cmd_btns.add_child(lb)

func _add_ration_button(unit: Node) -> void:
	if not unit.has_method("load_field_rations"):
		return
	var udef: Dictionary = DataLoader.get_unit_def(unit.unit_id)
	var cat: String = str(udef.get("category", ""))
	if cat == "civilian" or cat == "siege" or cat == "naval" or cat == "":
		return
	var bun_cnt: float = GameManager.get_resource(unit.faction, "bun")
	if bun_cnt < 1.0:
		return
	var rbtn: Button = Button.new()
	rbtn.custom_minimum_size = Vector2(64, 38)
	var carried: float = float(unit.field_rations) if "field_rations" in unit else 0.0
	rbtn.text = "🍞 备粮 %.0f" % carried
	rbtn.tooltip_text = "出征前领取包子军粮（1 包子 = 每人 10 秒口粮）。圈外断粮会掉体力并降攻击"
	rbtn.pressed.connect(_on_ration_btn.bind(unit))
	_cmd_btns.add_child(rbtn)

func _on_ration_btn(unit: Node) -> void:
	if unit.has_method("load_field_rations"):
		unit.load_field_rations(300.0)
		_show_unit_info(unit)

func _add_mount_button(unit: Node) -> void:
	if not unit.has_method("command_mount"):
		return
	var udef: Dictionary = DataLoader.get_unit_def(unit.unit_id)
	var cat: String = str(udef.get("category", ""))
	# 天生骑兵/器械/船只不参与手动骑乘
	if cat == "cavalry" or cat == "siege" or cat == "naval":
		return
	var mbtn: Button = Button.new()
	mbtn.custom_minimum_size = Vector2(64, 38)
	if "_pending_mount" in unit and unit._pending_mount:
		mbtn.text = "🐎 取马中"
		mbtn.disabled = true
		mbtn.tooltip_text = "正在前往最近马厩集合点取马，到达后自动上马"
	elif "mounted" in unit and unit.mounted:
		mbtn.text = "🐎 下马"
		mbtn.tooltip_text = "下马，归还 1 匹可用马匹"
		mbtn.pressed.connect(_on_dismount_btn.bind(unit))
	else:
		var horse_cnt: int = int(GameManager.get_resource(unit.faction, "horse"))
		if horse_cnt < 1:
			mbtn.text = "🐎 无马"
			mbtn.disabled = true
			mbtn.tooltip_text = "可用马匹不足（马厩产马或捕获野马）"
		else:
			mbtn.text = "🐎 上马"
			mbtn.tooltip_text = "点击上马：离马厩近则直接上马；离得远会自动走到最近马厩集合点取马后上马"
			mbtn.pressed.connect(_on_mount_btn.bind(unit))
	_cmd_btns.add_child(mbtn)

func _on_mount_btn(unit: Node) -> void:
	if unit.has_method("command_mount"):
		unit.command_mount()
		_show_unit_info(unit)  # 刷新为「下马」

func _on_dismount_btn(unit: Node) -> void:
	if unit.has_method("command_dismount"):
		unit.command_dismount()
		_show_unit_info(unit)

func _on_behavior_btn(bmode: int, unit: Node) -> void:
	if "behavior_mode" in unit:
		if unit.has_method("set_behavior_mode"):
			unit.set_behavior_mode(bmode)
		else:
			unit.behavior_mode = bmode
		var names: Dictionary = {
			0: "⚔ 主动进攻",
			1: "🛡 防守",
			2: "💤 睡觉（无法反击）",
			3: "🚩 坚守（不追击）"
		}
		EventBus.float_text.emit("行为: %s" % names[bmode], unit.global_position + Vector3(0, 3, 0), Color.CYAN)
		_show_unit_info(unit)  # 刷新按钮状态

func _clear_cmd_btns() -> void:
	for child in _cmd_btns.get_children():
		child.queue_free()

func _on_cmd_btn(cmd_id: String, unit: Node) -> void:
	match cmd_id:
		"stop": unit.state = 0  # 0
		_: EventBus.float_text.emit("指令: %s" % cmd_id, unit.global_position + Vector3(0, 2, 0), Color.CYAN)

func _on_float_text(text: String, position: Vector3, color: Color) -> void:
	if position == Vector3.ZERO:
		_show_center_text(text, color)
		return
	# 并发上限：大战时飘字海量生成会压垮 UI，超出上限直接丢弃（系统居中文字不受限）
	if _float_texts.size() >= _float_text_max:
		return
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 100
	add_child(label)
	_float_texts.append(label)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		var screen_pos: Vector2 = camera.unproject_position(position)
		label.position = screen_pos
		label.position.y -= 20
	var tween: Tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 30, 1.0)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func():
		_float_texts.erase(label)
		if is_instance_valid(label):
			label.queue_free()
	)

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

func _process(delta: float) -> void:
	_draw_minimap()
	# 资源条里人口/民心/马匹/村庄不会发 resources_changed，按 0.5s 节流刷新
	_hud_meta_timer -= delta
	if _hud_meta_timer <= 0.0:
		_hud_meta_timer = 0.5
		_update_hud_meta()
	# 武将名册节流刷新（最多每 0.5s 一次，且内部签名无变化会直接跳过）
	_roster_refresh_timer -= delta
	if _roster_refresh_timer <= 0.0:
		_roster_refresh_timer = 0.5
		_refresh_general_roster()
	_relic_refresh_timer -= delta
	if _relic_refresh_timer <= 0.0:
		_relic_refresh_timer = 1.0
		_refresh_relic_hud()
	# 🏮 客栈弹窗：每秒刷新倒计时（名单由客栈按月自动换，玩家不能手动刷）
	if _svc_kind == "inn" and _svc_popup != null and is_instance_valid(_svc_popup) and _svc_popup.visible:
		_svc_timer -= delta
		if _svc_timer <= 0.0:
			_svc_timer = 1.0
			_refresh_service()
	_update_build_cost_label()

## 建造模式：在鼠标旁常驻显示"建筑名 + 所需资源"，鼠标移到哪跟到哪。
## 悬停建造菜单按钮时也有 tooltip，但进入摆放后按钮已失焦，所以这里补一个跟随标签。
func _update_build_cost_label() -> void:
	var main: Node = get_node_or_null("/root/Main")
	var bid: String = ""
	if main != null and "_build_mode" in main:
		bid = str(main._build_mode)
	if bid == "":
		if _build_cost_label != null:
			_build_cost_label.visible = false
		return
	if _build_cost_label == null:
		_build_cost_label = Label.new()
		_build_cost_label.add_theme_font_size_override("font_size", 14)
		_build_cost_label.add_theme_color_override("font_color", Color(1, 0.96, 0.85))
		_build_cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_build_cost_label.add_theme_constant_override("outline_size", 4)
		_build_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_build_cost_label)
	var bdef: Dictionary = DataLoader.get_building_def(bid)
	var cost: Dictionary = bdef.get("cost", {})
	var txt: String = "🏗 %s" % str(bdef.get("name", bid))
	if not cost.is_empty():
		txt += "\n需要: " + _cost_text(cost)
	_build_cost_label.text = txt
	_build_cost_label.visible = true
	var mp: Vector2 = _build_cost_label.get_viewport().get_mouse_position()
	_build_cost_label.position = mp + Vector2(18, 14)

func _draw_minimap() -> void:
	if _minimap_canvas:
		_minimap_canvas.queue_redraw()

func _on_minimap_gui_input(event: InputEvent) -> void:
	if not _minimap_canvas:
		return
	# 左键或右键按下 = 跳转相机
	if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		var click_pos: Vector2 = event.position
		var mm_canvas_size: Vector2 = _minimap_canvas.size
		var map_size_px: Vector2i = GameManager.map_size
		if map_size_px.x == 0 or map_size_px.y == 0:
			return
		var mm_scale: Vector2 = Vector2(mm_canvas_size.x / float(map_size_px.x), mm_canvas_size.y / float(map_size_px.y))
		var gx: int = int(click_pos.x / mm_scale.x)
		var gz: int = int(click_pos.y / mm_scale.y)
		var world_pos: Vector3 = GameManager.grid.grid_to_world(Vector2i(gx, gz))
		var cam_controllers: Array = get_tree().get_nodes_in_group("camera_controller")
		for c in cam_controllers:
			if c.has_method("focus_on"):
				c.focus_on(world_pos)
				print("[GameUI] 🗺 小地图跳转 → grid(%d,%d) world(%s)" % [gx, gz, world_pos])
				break

func _on_minimap_draw() -> void:
	if not _minimap_canvas:
		return
	var mm_size: Vector2 = _minimap_canvas.size
	_minimap_canvas.draw_rect(Rect2(Vector2.ZERO, mm_size), Color(0.09, 0.075, 0.055, 1.0))
	# 细网格：让"疆域图"有沙盘感（绘制成本很低，纯线条）
	var grid_step: float = 24.0
	var gx: float = grid_step
	while gx < mm_size.x:
		_minimap_canvas.draw_line(Vector2(gx, 0), Vector2(gx, mm_size.y), Color(0.55, 0.45, 0.25, 0.07))
		gx += grid_step
	var gy: float = grid_step
	while gy < mm_size.y:
		_minimap_canvas.draw_line(Vector2(0, gy), Vector2(mm_size.x, gy), Color(0.55, 0.45, 0.25, 0.07))
		gy += grid_step
	var map_size: Vector2i = GameManager.map_size
	var scale: Vector2 = Vector2(mm_size.x / float(map_size.x), mm_size.y / float(map_size.y))
	# 绘制资源点
	for rn in GameManager.resource_nodes:
		if not is_instance_valid(rn):
			continue
		var rgp: Vector2i = GameManager.grid.world_to_grid(rn.global_position)
		var rpx: Vector2 = Vector2(float(rgp.x) * scale.x, float(rgp.y) * scale.y)
		var rc: Color = Color(0.8, 0.6, 0.3, 1.0)
		if rn.resource_type == "wood":
			rc = Color(0.3, 0.5, 0.2, 1.0)
		elif rn.resource_type == "iron":
			rc = Color(0.6, 0.55, 0.5, 1.0)
		elif rn.resource_type == "food":
			rc = Color(0.8, 0.7, 0.2, 1.0)
		_minimap_canvas.draw_rect(Rect2(rpx - Vector2(1, 1), Vector2(2, 2)), rc)
	# 绘制村庄
	for v in GameManager.villages:
		if not is_instance_valid(v):
			continue
		var vgp: Vector2i = GameManager.grid.world_to_grid(v.global_position)
		var vpx: Vector2 = Vector2(float(vgp.x) * scale.x, float(vgp.y) * scale.y)
		var vc: Color = Color(0.8, 0.8, 0.8, 1.0) if v.village_owner == "" else _get_faction_color(v.village_owner)
		_minimap_canvas.draw_rect(Rect2(vpx - Vector2(2, 2), Vector2(4, 4)), vc)
		_minimap_canvas.draw_rect(Rect2(vpx - Vector2(3, 3), Vector2(6, 6)), Color(vc.r, vc.g, vc.b, 0.4))
	# 绘制野马
	for h in GameManager.wild_horses:
		if not is_instance_valid(h):
			continue
		var hgp: Vector2i = GameManager.grid.world_to_grid(h.global_position)
		var hpx: Vector2 = Vector2(float(hgp.x) * scale.x, float(hgp.y) * scale.y)
		var hc: Color = Color(0.9, 0.9, 0.9, 1.0)
		match h.horse_type:
			"red": hc = Color(0.8, 0.2, 0.1, 1.0)
			"chitu": hc = Color(1.0, 0.1, 0.0, 1.0)
			"dilu": hc = Color(0.1, 0.1, 0.1, 1.0)
		_minimap_canvas.draw_circle(hpx, 2.0, hc)
	# 绘制建筑
	for b in GameManager.all_buildings:
		if not is_instance_valid(b):
			continue
		var bgp: Vector2i = GameManager.grid.world_to_grid(b.global_position)
		var bpx: Vector2 = Vector2(float(bgp.x) * scale.x, float(bgp.y) * scale.y)
		var bfc: Color = _get_faction_color(b.faction)
		# 建筑：外圈半透明光晕 + 实心方块，缩略图上更醒目
		_minimap_canvas.draw_rect(Rect2(bpx - Vector2(3, 3), Vector2(6, 6)), Color(bfc.r, bfc.g, bfc.b, 0.28))
		_minimap_canvas.draw_rect(Rect2(bpx - Vector2(2, 2), Vector2(4, 4)), bfc)
	# 绘制单位
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		var ugp: Vector2i = GameManager.grid.world_to_grid(u.global_position)
		var upx: Vector2 = Vector2(float(ugp.x) * scale.x, float(ugp.y) * scale.y)
		var ufc: Color = _get_faction_color(u.faction)
		_minimap_canvas.draw_circle(upx, 3.2, Color(ufc.r, ufc.g, ufc.b, 0.30))
		_minimap_canvas.draw_circle(upx, 1.5, ufc)
	# 绘制相机视口框（AoE4 风格：淡金填充 + 亮边，一眼看出当前视野）
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
		var vp_rect: Rect2 = Rect2(tl_px, br_px - tl_px)
		_minimap_canvas.draw_rect(vp_rect, Color(1.0, 0.92, 0.68, 0.10), true)
		_minimap_canvas.draw_rect(vp_rect, Color(1.0, 0.93, 0.72, 0.85), false, 1.5)

func _get_faction_color(faction_id: String) -> Color:
	match faction_id:
		"wei": return Color(0.73, 0.23, 0.23, 1.0)
		"shu": return Color(0.31, 0.68, 0.31, 1.0)
		"wu": return Color(0.29, 0.50, 0.81, 1.0)
		_: return Color(0.73, 0.63, 0.45, 1.0)

func get_build_menu() -> PanelContainer:
	return null

# ==================== 🏪 服务建筑弹窗（市场 / 寺庙 / 客栈） ====================
const RES_CN: Dictionary = {
	"food": "谷", "wood": "木", "iron": "铁", "gold": "金", "bun": "包子",
	"wine": "酒", "fish": "鱼", "meat": "肉", "horse": "马"
}
const TRADE_RES: Array = ["food", "wood", "iron", "gold", "bun", "wine", "fish", "meat", "horse"]

var _svc_popup: PopupPanel = null
var _svc_vbox: VBoxContainer = null
var _svc_building: Node = null
var _svc_kind: String = ""
var _svc_timer: float = 1.0

func _open_service_popup(kind: String, building: Node) -> void:
	_close_service_popup()
	_svc_kind = kind
	_svc_building = building
	_svc_popup = PopupPanel.new()
	_svc_popup.title = {"market": "🏪 市场交易", "temple": "🛕 寺庙祭祀", "inn": "🏮 客栈招募"}.get(kind, "服务")
	get_tree().root.add_child(_svc_popup)
	_svc_vbox = VBoxContainer.new()
	_svc_vbox.add_theme_constant_override("separation", 6)
	_svc_popup.add_child(_svc_vbox)
	_refresh_service()
	# 客栈是三张武将卡片横排，需要更宽的弹窗
	_svc_popup.popup_centered(Vector2i(740 if kind == "inn" else 660, 520 if kind == "inn" else 480))

func _close_service_popup() -> void:
	if _svc_popup != null and is_instance_valid(_svc_popup):
		_svc_popup.queue_free()
	_svc_popup = null
	_svc_vbox = null

func _refresh_service() -> void:
	if _svc_vbox == null or not is_instance_valid(_svc_vbox) or not is_instance_valid(_svc_building):
		return
	for c in _svc_vbox.get_children():
		c.queue_free()
	match _svc_kind:
		"market": _fill_market(_svc_building)
		"temple": _fill_temple(_svc_building)
		"inn": _fill_inn(_svc_building)

func _mk_label(txt: String) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _faction_cn(fid: String) -> String:
	match fid:
		"wei": return "曹魏"
		"shu": return "蜀汉"
		"wu": return "东吴"
		_: return "群雄"

func _fill_market(b: Node) -> void:
	_svc_vbox.add_child(_mk_label("💰 金 %.0f　｜　卖出价 ×0.8（东吴通商 +25%，通商官叠加）　买入价 ×1.25"
		% GameManager.get_resource(b.faction, "gold")))
	var head: HBoxContainer = HBoxContainer.new()
	for t in ["资源", "持有", "买价", "卖价", "数量", "操作"]:
		var h: Label = Label.new()
		h.text = t
		h.custom_minimum_size = Vector2(72 if t != "操作" else 130, 0)
		head.add_child(h)
	_svc_vbox.add_child(head)
	for res in TRADE_RES:
		var row: HBoxContainer = HBoxContainer.new()
		var nm: Label = Label.new()
		nm.text = str(RES_CN.get(res, res))
		nm.custom_minimum_size = Vector2(72, 0)
		var have: Label = Label.new()
		have.text = "%.0f" % GameManager.get_resource(b.faction, res)
		have.custom_minimum_size = Vector2(72, 0)
		var bp: Label = Label.new()
		bp.text = "%.2f" % b.get_trade_unit_price(res, true)
		bp.custom_minimum_size = Vector2(72, 0)
		var sp: Label = Label.new()
		sp.text = "%.2f" % b.get_trade_unit_price(res, false)
		sp.custom_minimum_size = Vector2(72, 0)
		var spin: SpinBox = SpinBox.new()
		spin.min_value = 10
		spin.max_value = 500
		spin.step = 50
		spin.value = 50
		spin.custom_minimum_size = Vector2(96, 0)
		var buy: Button = Button.new()
		buy.text = "买入"
		buy.pressed.connect(_on_market_trade.bind(b, res, spin, true))
		var sell: Button = Button.new()
		sell.text = "卖出"
		sell.pressed.connect(_on_market_trade.bind(b, res, spin, false))
		row.add_child(nm)
		row.add_child(have)
		row.add_child(bp)
		row.add_child(sp)
		row.add_child(spin)
		row.add_child(buy)
		row.add_child(sell)
		_svc_vbox.add_child(row)

func _on_market_trade(b: Node, res: String, spin: SpinBox, is_buy: bool) -> void:
	var amt: float = float(spin.value)
	if is_buy:
		b.market_buy(res, amt)
	else:
		b.market_sell(res, amt)
	_refresh_service()

func _fill_temple(b: Node) -> void:
	var keys: Array = ["disaster_reduction", "tree_growth", "farm_output", "gather_speed"]
	var names: Dictionary = {
		"disaster_reduction": "灾害减免", "tree_growth": "树木生长",
		"farm_output": "农业产出", "gather_speed": "采集速度"
	}
	var txt: String = "🙏 当前祈福："
	var any: bool = false
	for k in keys:
		var v: float = GameManager.get_buff_value(b.faction, k)
		if v > 0.0:
			any = true
			txt += "%s +%.0f%%（%.0fs）　" % [names[k], v * 100.0, GameManager.get_buff_remain(b.faction, k)]
	_svc_vbox.add_child(_mk_label(txt if any else "🙏 当前祈福：无"))
	var cd: float = b.get_sacrifice_cooldown_left()
	var sbtn: Button = Button.new()
	if cd > 0.0:
		sbtn.text = "祈福冷却中 %.0fs" % cd
		sbtn.disabled = true
	else:
		sbtn.text = "祈福：100金+30酒 → 120秒 灾害-60% 农业/采集+20% 树木+50% 全军士气+15"
		sbtn.pressed.connect(func() -> void:
			b.temple_sacrifice()
			_refresh_service())
	_svc_vbox.add_child(sbtn)
	_svc_vbox.add_child(_mk_label("💀 待复活武将：%d 名（5 分钟内可救；超时变成在野，需去客栈重新招募）"
		% GameManager.dead_generals.size()))
	for g in GameManager.dead_generals:
		if not is_instance_valid(g):
			continue
		var glv: int = int(g.level)
		var row: HBoxContainer = HBoxContainer.new()
		var gl: Label = Label.new()
		gl.text = "%s　Lv%d　剩余 %.0fs　" % [str(g.name), glv, maxf(0.0, float(g.get("grace_period_seconds")))]
		gl.custom_minimum_size = Vector2(300, 0)
		var rb: Button = Button.new()
		rb.text = "复活（%d金+50酒）" % int(300 + 60 * maxi(0, glv - 1))
		rb.pressed.connect(func() -> void:
			b.temple_revive_general()
			_refresh_service())
		row.add_child(gl)
		row.add_child(rb)
		_svc_vbox.add_child(row)

func _fill_inn(b: Node) -> void:
	var lv_r: Vector2i = GameManager.get_recruit_level_range(b.def)
	var rc: Dictionary = b.def.get("recruit", {})
	_svc_vbox.add_child(_mk_label("🕒 本客栈在野 %d/%d 名　｜　下次换批 %.0fs（每月 1 次 · 约 %.0f%% 概率有人应募 · 不可手动刷新）"
		% [b.inn_roster.size(), int(rc.get("candidates", 3)), b.inn_refresh_left(),
		float(rc.get("spawn_chance", 0.6)) * 100.0]))
	_svc_vbox.add_child(_mk_label("📜 可招 Lv%d~Lv%d　｜　同势力 -20%%　敌对在野名将 +10%%　占村声望 -%.0f%%　｜　在野池剩余 %d 名"
		% [lv_r.x, lv_r.y, GameManager.get_recruit_renown_discount(rc, GameManager.player_faction) * 100.0,
		GameManager.generals_pool.size()]))
	var cands: Array = b.inn_get_candidates()
	if cands.is_empty():
		if b.inn_roster_missed():
			_svc_vbox.add_child(_mk_label("🌙 本月无人应募（换批未命中），下个月再来看；多建客栈可提高同时在野的机会"))
		else:
			_svc_vbox.add_child(_mk_label("🌙 本客栈暂时无在野武将（在野池已空或都被别的客栈挂着）"))
		return
	var cards: HBoxContainer = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	_svc_vbox.add_child(cards)
	for c in cands:
		cards.add_child(_mk_general_card(b, c))

## 在野武将卡片：头像（势力色 + 姓氏大字 + 等级角标）+ 三围/四维 + 技能 + 招募按钮
func _mk_general_card(b: Node, c: Dictionary) -> Control:
	var fc: Color = _get_faction_color(str(c.get("faction", "qunxiong")))
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(206, 0)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.05, 0.96)
	sb.border_color = fc
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	card.add_theme_stylebox_override("panel", sb)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	# —— 头像行：方形头像 + 右侧姓名/类型 ——
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)
	var av: Panel = Panel.new()
	av.custom_minimum_size = Vector2(64, 64)
	var asb: StyleBoxFlat = StyleBoxFlat.new()
	asb.bg_color = fc.darkened(0.55)
	asb.border_color = fc
	asb.border_width_left = 2
	asb.border_width_right = 2
	asb.border_width_top = 2
	asb.border_width_bottom = 2
	asb.corner_radius_top_left = 32
	asb.corner_radius_top_right = 32
	asb.corner_radius_bottom_left = 32
	asb.corner_radius_bottom_right = 32
	av.add_theme_stylebox_override("panel", asb)
	top.add_child(av)
	var glyph: Label = Label.new()
	glyph.text = str(c.get("name", "?")).substr(0, 1)
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 34)
	glyph.add_theme_color_override("font_color", Color(0.98, 0.93, 0.80))
	glyph.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	glyph.add_theme_constant_override("outline_size", 4)
	av.add_child(glyph)
	# 等级角标
	var lv_badge: Label = Label.new()
	lv_badge.text = "Lv%d" % int(c.get("level", 1))
	lv_badge.position = Vector2(2, 46)
	lv_badge.add_theme_font_size_override("font_size", 12)
	lv_badge.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45))
	lv_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lv_badge.add_theme_constant_override("outline_size", 4)
	av.add_child(lv_badge)

	var info: VBoxContainer = VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var nm: Label = Label.new()
	nm.text = str(c.get("name", ""))
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", fc.lightened(0.35))
	info.add_child(nm)
	var sub: Label = Label.new()
	sub.text = "%s · %s" % [_faction_cn(str(c.get("faction", ""))), str(c.get("class_name", ""))]
	sub.add_theme_font_size_override("font_size", 12)
	info.add_child(sub)
	var rel: String = ""
	var pf: Dictionary = c.get("price", {})
	if float(pf.get("same_faction_discount", 0.0)) > 0.0:
		rel = "  · 同族 -20%"
	elif float(pf.get("enemy_premium", 0.0)) > 0.0:
		rel = "  · 敌将 +10%"
	if rel != "":
		var rl: Label = Label.new()
		rl.text = rel.strip_edges()
		rl.add_theme_font_size_override("font_size", 11)
		rl.add_theme_color_override("font_color", Color(0.92, 0.72, 0.35))
		info.add_child(rl)

	# —— 四维 ——
	var st: Label = Label.new()
	st.text = "⚔武 %d　📖智 %d　🎋统 %d　📜政 %d" % [
		int(c.get("might", 70)), int(c.get("intelligence", 70)),
		int(c.get("command", 70)), int(c.get("politics", 55))]
	st.add_theme_font_size_override("font_size", 12)
	vb.add_child(st)

	# —— 技能 / 被动 ——
	var sk: Array = c.get("skills", [])
	var ps: Array = c.get("passives", [])
	var skl: Label = Label.new()
	skl.text = "✨ 技能：%s" % ("无" if sk.is_empty() else " · ".join(PackedStringArray(sk)))
	skl.add_theme_font_size_override("font_size", 12)
	skl.add_theme_color_override("font_color", Color(0.86, 0.80, 0.62))
	skl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(skl)
	var psl: Label = Label.new()
	psl.text = "🎖 被动：%s" % ("无" if ps.is_empty() else " · ".join(PackedStringArray(ps)))
	psl.add_theme_font_size_override("font_size", 12)
	psl.add_theme_color_override("font_color", Color(0.72, 0.80, 0.72))
	psl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(psl)

	# —— 招募 ——
	var cb: Button = Button.new()
	cb.text = "招募 %.0f 金" % float(c.get("cost", 500))
	cb.tooltip_text = "Lv%d 基础 %.0f 金\n三围 %d ×%.2f\n同族 -%.0f%%　声望 -%.0f%%　敌将 +%.0f%%\n实付 %.0f 金" % [
		int(c.get("level", 1)), float(pf.get("level_price", 500)),
		int(pf.get("stat_sum", 210)), float(pf.get("stat_mult", 1.0)),
		float(pf.get("same_faction_discount", 0.0)) * 100.0,
		float(pf.get("renown_discount", 0.0)) * 100.0,
		float(pf.get("enemy_premium", 0.0)) * 100.0,
		float(c.get("cost", 500))]
	cb.pressed.connect(_on_inn_recruit.bind(b, str(c.get("id", "")), int(c.get("level", 1))))
	vb.add_child(cb)
	return card

func _on_inn_recruit(b: Node, gid: String, lv: int) -> void:
	b.inn_recruit(gid, lv)
	_refresh_service()
