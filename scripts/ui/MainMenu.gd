extends Control
class_name MainMenu

# =====================================================
# MainMenu — 单页自定义界面 v2（全部显式类型）
# =====================================================

const FACTION_INFO := {
	"wei":   { "name": "曹魏",   "color": Color(0.73, 0.23, 0.23), "desc": "挟天子令诸侯，坐拥中原。虎豹骑天下无双。" },
	"shu":   { "name": "蜀汉",   "color": Color(0.31, 0.68, 0.31), "desc": "仁德感召天下，据守荆益。白毦兵善山地。" },
	"wu":    { "name": "孙吴",   "color": Color(0.29, 0.50, 0.81), "desc": "坐断东南，水军冠绝天下。丹阳锐兵山地平原皆强。" },
	"other": { "name": "其他",   "color": Color(0.5, 0.5, 0.5), "desc": "（敬请期待）" },
}
const COLOR_NAMES  := ["red", "blue", "yellow", "purple", "orange", "green", "cyan", "brown", "black"]
const COLOR_LABELS := ["红", "蓝", "黄", "紫", "橙", "绿", "青", "褐", "黑"]

const DIFFICULTY_PRESETS := {
	"easy":        { "name": "简单",        "desc": "操作慢 3.0s / 资源×0.8 / 农夫2" },
	"normal":      { "name": "一般",        "desc": "操作慢 2.0s / 资源×1.2 / 农夫3" },
	"hard":        { "name": "困难",        "desc": "操作慢 1.0s / 资源×1.5 / 农夫4" },
	"custom":      { "name": "自定义",      "desc": "手动调整所有参数" },
	"random_quick":{ "name": "🎲随机快速",  "desc": "一键：随机势力+颜色+地图+难度" },
}

const AI_INTENSITY_DATA := {
	"easy":   { "name": "简单",   "res_mult": 0.8, "base_soldiers": {"sword":2,"spear":2,"archer":2,"civil":1}, "extra": {} },
	"normal": { "name": "普通",   "res_mult": 1.0, "base_soldiers": {"sword":2,"spear":2,"archer":2,"civil":1}, "extra": {} },
	"hard":   { "name": "困难",   "res_mult": 1.5, "base_soldiers": {"sword":2,"spear":2,"archer":2,"civil":1}, "extra": {"spear":1,"sword":1} },
	"cruel":  { "name": "最困难", "res_mult": 2.0, "base_soldiers": {"sword":2,"spear":2,"archer":2,"civil":1}, "extra": {"spear":2,"sword":2,"archer":1} },
}
const AI_INTENSITY_ORDER := ["easy", "normal", "hard", "cruel"]

const INITIAL_RESOURCES := {
	"scarce":    { "name": "匮乏 (0.8×)",  "mult": 0.8 },
	"normal":    { "name": "一般 (1.0×)",  "mult": 1.0 },
	"smallrich": { "name": "小富 (1.5×)",  "mult": 1.5 },
	"wealthy":   { "name": "富裕 (2.0×)",  "mult": 2.0 },
}
const RESOURCES_ORDER := ["scarce", "normal", "smallrich", "wealthy"]

const MAP_RICHNESS := {
	"rich":   { "name": "富饶", "trees": "大片+生长快",  "mines_in": 3, "fish_in": 3 },
	"normal": { "name": "一般", "trees": "大片+中等",   "mines_in": 2, "fish_in": 1 },
	"poor":   { "name": "贫瘠", "trees": "中片+低速",   "mines_in": 2, "fish_in": 1 },
}
const RICHNESS_ORDER := ["rich", "normal", "poor"]

const VICTORY_CONDITIONS := {
	"eliminate": { "name": "消灭所有敌对势力" },
	"score_30":  { "name": "时间限制 30 分钟" },
	"score_45":  { "name": "时间限制 45 分钟" },
	"score_60":  { "name": "时间限制 60 分钟" },
}
const VICTORY_ORDER := ["eliminate", "score_30", "score_45", "score_60"]

const INITIAL_GENERALS := {
	"none":  { "name": "无初始武将" },
	"one":   { "name": "1 个随机 (+文臣)" },
	"three": { "name": "3 个随机 (+文臣)" },
	"five":  { "name": "5 个随机 (+文臣)" },
}
const GENERALS_ORDER := ["none", "one", "three", "five"]

const ON_OFF_LABEL := ["❌ 无", "✅ 有"]

# ===== 状态 =====
var selected_faction: String = "shu"
var selected_color_key: String = "red"
var _color_index: int = 0
var selected_difficulty: String = "normal"
var player_name: String = "主公"
var selected_portrait: String = "liubei"
var _portrait_index: int = 0
var selected_map_id: String = "jiangshan_yitong"
var selected_map_mode: String = "preset"
var selected_seed: int = 0
var selected_save_name: String = ""
var selected_size_key: String = "large"
var selected_richness: String = "normal"
var selected_ai_enemy: int = 1
var selected_ai_ally: int = 0
var selected_ai_intensity: String = "normal"
var selected_fog: bool = true
var selected_disaster: bool = true
var selected_neutral_forces: bool = true
var selected_initial_resources: String = "normal"
var selected_victory: String = "eliminate"
var selected_initial_generals: String = "one"
var portrait_pool: Array = []

# ===== UI 引用 =====
var portrait_display: Label = null
var portrait_name_lbl: Label = null
var color_display_rect: ColorRect = null
var color_display_lbl: Label = null
var faction_desc_label: Label = null
var player_name_edit: LineEdit = null
var ai_intensity_lbl: Label = null
var richness_lbl: Label = null
var fog_lbl: Label = null
var disaster_lbl: Label = null
var neutral_lbl: Label = null
var resources_lbl: Label = null
var victory_lbl: Label = null
var generals_lbl: Label = null
var map_option: OptionButton = null
var enemy_count_spin: SpinBox = null
var ally_count_spin: SpinBox = null
var map_mode_group: ButtonGroup = null
var size_group: ButtonGroup = null
var _mode_buttons: Dictionary = {}
var _size_buttons: Dictionary = {}
var _saved_option: OptionButton = null
var _seed_display: Label = null

# ===== 生命周期 =====
func _ready() -> void:
	_load_defaults()
	_build_ui()
	_refresh_all()

func _load_defaults() -> void:
	var d: Dictionary = DataLoader.game_settings.get("default_settings", {})
	selected_faction          = str(d.get("player_faction", "shu"))
	selected_color_key        = str(d.get("player_color", "red"))
	selected_difficulty       = str(d.get("difficulty", "normal"))
	selected_map_id           = str(d.get("map_id", "jiangshan_yitong"))
	selected_map_mode         = str(d.get("map_mode", "preset"))
	selected_seed             = int(d.get("map_seed", 0))
	selected_save_name        = str(d.get("map_saved_name", ""))
	selected_size_key         = str(d.get("map_size_key", "large"))
	selected_richness         = str(d.get("map_richness", "normal"))
	selected_ai_enemy         = int(d.get("ai_enemy_count", 1))
	selected_ai_ally          = int(d.get("ai_ally_count", 0))
	selected_ai_intensity     = str(d.get("ai_intensity", "normal"))
	selected_fog              = bool(d.get("fog_of_war", true))
	selected_disaster         = bool(d.get("disasters", true))
	selected_neutral_forces   = bool(d.get("neutral_forces", true))
	selected_initial_resources= str(d.get("initial_resources", "normal"))
	selected_victory          = str(d.get("victory_condition", "eliminate"))
	selected_initial_generals = str(d.get("initial_generals_count", "one"))
	player_name               = str(d.get("player_name", "主公"))
	# 🎯 ConfigFile 可能把 int 存成 float → str(1.0)="1.0" 不在合法 key 里
	if not GENERALS_ORDER.has(selected_initial_generals): selected_initial_generals = "one"
	if not VICTORY_ORDER.has(selected_victory): selected_victory = "eliminate"
	if not RESOURCES_ORDER.has(selected_initial_resources): selected_initial_resources = "normal"
	if not AI_INTENSITY_ORDER.has(selected_ai_intensity): selected_ai_intensity = "normal"
	if not RICHNESS_ORDER.has(selected_richness): selected_richness = "normal"
	if not ["small","medium","large"].has(selected_size_key): selected_size_key = "large"
	if not DIFFICULTY_PRESETS.keys().has(selected_difficulty): selected_difficulty = "normal"
	if not COLOR_NAMES.has(selected_color_key): selected_color_key = "red"
	if not FACTION_INFO.has(selected_faction): selected_faction = "shu"
	portrait_pool = DataLoader.game_settings.get("portrait_pool", [])
	if portrait_pool.is_empty():
		portrait_pool = [
			{"id":"liubei","name":"刘备","emoji":"🦁"}, {"id":"guanyu","name":"关羽","emoji":"⚔"},
			{"id":"zhangfei","name":"张飞","emoji":"🐯"}, {"id":"zhaoyun","name":"赵云","emoji":"🐎"},
			{"id":"zhugeliang","name":"诸葛亮","emoji":"羽"}, {"id":"caocao","name":"曹操","emoji":"👑"},
			{"id":"simayi","name":"司马懿","emoji":"🦊"}, {"id":"xuchu","name":"许褚","emoji":"🛡"},
			{"id":"sunquan","name":"孙权","emoji":"🌊"}, {"id":"zhouyu","name":"周瑜","emoji":"🔥"},
			{"id":"lvmeng","name":"吕蒙","emoji":"🎯"}, {"id":"luxun","name":"陆逊","emoji":"📜"},
			{"id":"diaochan","name":"貂蝉","emoji":"🌸"}, {"id":"lvbu","name":"吕布","emoji":"🐎"},
		]
	for i in range(portrait_pool.size()):
		if str(portrait_pool[i].get("id","")) == selected_portrait: _portrait_index = i
	for i2 in range(COLOR_NAMES.size()):
		if COLOR_NAMES[i2] == selected_color_key: _color_index = i2

# ===== UI 构建 =====
func _build_ui() -> void:
	var bg := ColorRect.new(); bg.color = Color(0.08,0.06,0.04); bg.anchor_right=1.0; bg.anchor_bottom=1.0; add_child(bg)
	var gr := ColorRect.new(); gr.color = Color(0.18,0.11,0.05,0.5); gr.anchor_right=1.0; gr.anchor_bottom=1.0; add_child(gr)
	
	var outer := VBoxContainer.new()
	outer.anchor_right=1.0; outer.anchor_bottom=1.0; outer.offset_left=60; outer.offset_right=-60
	outer.offset_top=12; outer.offset_bottom=-12
	outer.add_theme_constant_override("separation", 4); add_child(outer)
	
	var t := Label.new(); t.text = "⚔ 三分天下 · 再起 ⚔"; t.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 36); t.add_theme_color_override("font_color", Color(1.0,0.88,0.62)); outer.add_child(t)
	var s := Label.new(); s.text="傲世三国之三分天下 · 自定义征战"; s.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_font_size_override("font_size", 13); s.add_theme_color_override("font_color", Color(0.75,0.65,0.45)); outer.add_child(s)
	
	var sc := ScrollContainer.new(); sc.size_flags_vertical=Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; outer.add_child(sc)
	var vb := VBoxContainer.new(); vb.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 14); vb.add_theme_constant_override("margin_left", 20)
	vb.add_theme_constant_override("margin_right", 20); sc.add_child(vb)
	
	vb.add_child(_mk_section("选择难度（顶部快捷）"))
	_build_difficulty(vb)
	
	vb.add_child(_mk_section("👤 玩家设置"))
	_build_player(vb)
	
	vb.add_child(_mk_section("🗺 地图"))
	_build_map(vb)
	
	vb.add_child(_mk_section("🤖 AI 设置"))
	_build_ai(vb)
	
	vb.add_child(_mk_section("🎮 特色 / 灾祸 / 胜利"))
	_build_features(vb)
	
	var sp := HSeparator.new(); outer.add_child(sp)
	var bot := HBoxContainer.new(); bot.alignment=BoxContainer.ALIGNMENT_CENTER; bot.add_theme_constant_override("separation", 20); outer.add_child(bot)
	var sb := Button.new(); sb.text="⚔ 开始游戏"; sb.custom_minimum_size=Vector2(220,54)
	sb.add_theme_font_size_override("font_size", 20); sb.pressed.connect(_on_start_pressed); bot.add_child(sb)
	# 地图工坊（地图编辑器）入口 —— 独立工具场景，不经过开局流程
	var mb := Button.new(); mb.text="🗺 地图工坊"; mb.custom_minimum_size=Vector2(160,54)
	mb.add_theme_font_size_override("font_size", 18)
	mb.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MapEditor.tscn"))
	bot.add_child(mb)
	var qb := Button.new(); qb.text="✕ 退出"; qb.custom_minimum_size=Vector2(110,44)
	qb.add_theme_font_size_override("font_size", 14); qb.pressed.connect(func(): get_tree().quit()); bot.add_child(qb)

# ---------- 难度 ----------
func _build_difficulty(parent: VBoxContainer) -> void:
	var r: HBoxContainer = HBoxContainer.new(); r.add_theme_constant_override("separation", 8)
	var keys: Array = DIFFICULTY_PRESETS.keys()
	for i in range(keys.size()):
		var did: String = str(keys[i])
		var d: Dictionary = DIFFICULTY_PRESETS[did]
		var b := Button.new(); b.text="%s\n%s" % [d["name"], d["desc"]]
		b.custom_minimum_size=Vector2(195,68); b.add_theme_font_size_override("font_size",13)
		b.toggle_mode=true; b.name="diff_"+did; b.pressed.connect(_on_difficulty.bind(did)); r.add_child(b)
	parent.add_child(r)

# ---------- 玩家 ----------
func _build_player(parent: VBoxContainer) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24); row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	
	# 左
	var L: VBoxContainer = VBoxContainer.new()
	L.add_theme_constant_override("separation", 10); L.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	L.add_child(_mk_label("选择势力", 14, Color(1.0,0.88,0.62)))
	var fh: HBoxContainer = HBoxContainer.new(); fh.add_theme_constant_override("separation", 8)
	var fids: Array = ["wei","shu","wu","other"]
	for i in range(fids.size()):
		var fid: String = str(fids[i])
		var b := Button.new(); b.text=FACTION_INFO[fid]["name"]
		b.custom_minimum_size=Vector2(110,46); b.add_theme_font_size_override("font_size",16)
		b.add_theme_color_override("font_color", FACTION_INFO[fid]["color"]); b.toggle_mode=true; b.name="f_"+fid
		b.pressed.connect(_on_faction.bind(fid)); b.disabled = (fid=="other")
		fh.add_child(b)
	L.add_child(fh)
	faction_desc_label = Label.new(); faction_desc_label.add_theme_font_size_override("font_size",12)
	faction_desc_label.add_theme_color_override("font_color", Color(0.75,0.7,0.55))
	faction_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	faction_desc_label.custom_minimum_size = Vector2(0,32); L.add_child(faction_desc_label)
	var nh: HBoxContainer = HBoxContainer.new(); nh.add_theme_constant_override("separation",8)
	nh.add_child(_mk_label("主公名号:",14,Color(0.85,0.8,0.7)))
	player_name_edit = LineEdit.new(); player_name_edit.text=player_name
	player_name_edit.custom_minimum_size=Vector2(180,34); player_name_edit.max_length=8
	player_name_edit.text_changed.connect(func(t: String): player_name=t); nh.add_child(player_name_edit)
	L.add_child(nh); row.add_child(L)
	
	# 中：头像
	var C: VBoxContainer = VBoxContainer.new()
	C.alignment=BoxContainer.ALIGNMENT_CENTER; C.add_theme_constant_override("separation",4)
	var t1 := _mk_label("头像选择",14,Color(1.0,0.88,0.62)); t1.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; C.add_child(t1)
	var pr: HBoxContainer = HBoxContainer.new(); pr.add_theme_constant_override("separation",6); pr.alignment=BoxContainer.ALIGNMENT_CENTER
	var la := Button.new(); la.text="◀"; la.custom_minimum_size=Vector2(36,76); la.add_theme_font_size_override("font_size",20)
	la.pressed.connect(func(): _cycle_portrait(-1)); pr.add_child(la)
	var pf := PanelContainer.new(); var pbs := _mk_panel(Color(0.18,0.14,0.09), Color(1.0,0.88,0.62), 2, 10)
	pf.add_theme_stylebox_override("panel", pbs); pf.custom_minimum_size=Vector2(100,100)
	portrait_display = Label.new(); portrait_display.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	portrait_display.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; portrait_display.custom_minimum_size=Vector2(90,90)
	portrait_display.add_theme_font_size_override("font_size",38); pf.add_child(portrait_display); pr.add_child(pf)
	var ra := Button.new(); ra.text="▶"; ra.custom_minimum_size=Vector2(36,76); ra.add_theme_font_size_override("font_size",20)
	ra.pressed.connect(func(): _cycle_portrait(1)); pr.add_child(ra); C.add_child(pr)
	portrait_name_lbl = Label.new(); portrait_name_lbl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	portrait_name_lbl.add_theme_font_size_override("font_size",13); portrait_name_lbl.add_theme_color_override("font_color", Color(0.85,0.8,0.7))
	C.add_child(portrait_name_lbl); row.add_child(C)
	
	# 右：颜色
	var R_col: VBoxContainer = VBoxContainer.new()
	R_col.alignment=BoxContainer.ALIGNMENT_CENTER; R_col.add_theme_constant_override("separation",4)
	var t2 := _mk_label("阵营颜色",14,Color(1.0,0.88,0.62)); t2.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; R_col.add_child(t2)
	var cr: HBoxContainer = HBoxContainer.new(); cr.add_theme_constant_override("separation",6); cr.alignment=BoxContainer.ALIGNMENT_CENTER
	var lb2 := Button.new(); lb2.text="◀"; lb2.custom_minimum_size=Vector2(36,56); lb2.add_theme_font_size_override("font_size",20)
	lb2.pressed.connect(func(): _cycle_color(-1)); cr.add_child(lb2)
	var cf := PanelContainer.new(); var cfs := _mk_panel(Color(0.18,0.14,0.09), Color(1.0,0.88,0.62), 2, 28)
	cf.add_theme_stylebox_override("panel", cfs); cf.custom_minimum_size=Vector2(76,76)
	color_display_rect = ColorRect.new(); color_display_rect.color = Color.RED; cf.add_child(color_display_rect); cr.add_child(cf)
	var rb2 := Button.new(); rb2.text="▶"; rb2.custom_minimum_size=Vector2(36,56); rb2.add_theme_font_size_override("font_size",20)
	rb2.pressed.connect(func(): _cycle_color(1)); cr.add_child(rb2); R_col.add_child(cr)
	color_display_lbl = Label.new(); color_display_lbl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	color_display_lbl.add_theme_font_size_override("font_size",15); R_col.add_child(color_display_lbl); row.add_child(R_col)
	parent.add_child(row)

# ---------- 地图 ----------
func _build_map(parent: VBoxContainer) -> void:
	var modes: Array = [["preset","📜 预设"],["random","🎲 随机"],["seed","🔢 指定种子"],["saved","💾 读档"]]
	var mr: HBoxContainer = HBoxContainer.new(); mr.add_theme_constant_override("separation", 8)
	map_mode_group = ButtonGroup.new()
	for i in range(modes.size()):
		var m: Array = modes[i]
		var b := Button.new(); b.text=str(m[1]); b.toggle_mode=true; b.button_group=map_mode_group
		b.custom_minimum_size=Vector2(100,36); b.add_theme_font_size_override("font_size",13)
		b.pressed.connect(_on_map_mode.bind(str(m[0]))); mr.add_child(b); _mode_buttons[str(m[0])]=b
	parent.add_child(mr)
	
	var mrow: HBoxContainer = HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 20); mrow.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	
	var Lm: VBoxContainer = VBoxContainer.new()
	Lm.add_theme_constant_override("separation", 8); Lm.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	map_option = OptionButton.new(); map_option.custom_minimum_size=Vector2(260,34); Lm.add_child(map_option)
	map_option.item_selected.connect(_on_map_selected_dropdown)
	_refresh_map_dropdown()
	
	var sr: HBoxContainer = HBoxContainer.new(); sr.add_theme_constant_override("separation", 8)
	sr.add_child(_mk_label("尺寸:",13,Color(0.75,0.7,0.55)))
	size_group = ButtonGroup.new()
	var sizes: Array = [["small","60×60"],["medium","72×72"],["large","84×84"]]
	for i in range(sizes.size()):
		var s: Array = sizes[i]
		var b := Button.new(); b.text=str(s[1]); b.toggle_mode=true; b.button_group=size_group
		b.custom_minimum_size=Vector2(90,34); b.add_theme_font_size_override("font_size",13)
		b.pressed.connect(_on_size.bind(str(s[0]))); sr.add_child(b); _size_buttons[str(s[0])]=b
	Lm.add_child(sr)
	
	var seed_row: HBoxContainer = HBoxContainer.new(); seed_row.add_theme_constant_override("separation",8)
	_seed_display = Label.new(); _seed_display.add_theme_font_size_override("font_size",13)
	_seed_display.add_theme_color_override("font_color", Color(1.0,0.88,0.62)); seed_row.add_child(_seed_display)
	var roll_btn := Button.new(); roll_btn.text="🎲 换"; roll_btn.custom_minimum_size=Vector2(50,32)
	roll_btn.pressed.connect(_on_roll); seed_row.add_child(roll_btn); Lm.add_child(seed_row)
	
	var saved_row: HBoxContainer = HBoxContainer.new(); saved_row.add_theme_constant_override("separation",8)
	_saved_option = OptionButton.new(); _saved_option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_saved_option.custom_minimum_size=Vector2(200,32); saved_row.add_child(_saved_option)
	var del_btn := Button.new(); del_btn.text="🗑 删除"; del_btn.custom_minimum_size=Vector2(70,32)
	del_btn.pressed.connect(_on_saved_delete); saved_row.add_child(del_btn)
	_saved_option.item_selected.connect(_on_saved_selected); _refresh_saved_list(); Lm.add_child(saved_row)
	mrow.add_child(Lm)
	
	var Rm: VBoxContainer = VBoxContainer.new(); Rm.alignment=BoxContainer.ALIGNMENT_CENTER
	Rm.add_child(_mk_label("缩略图（城池红/村镇绿/矿山黄/树林绿点）", 11, Color(0.75,0.7,0.55)))
	var th := PanelContainer.new(); var ths := _mk_panel(Color(0.06,0.1,0.06), Color(1.0,0.88,0.62), 1, 6)
	th.add_theme_stylebox_override("panel", ths); th.custom_minimum_size=Vector2(180,180)
	var tc := ColorRect.new(); tc.color = Color(0.12,0.2,0.12); th.add_child(tc); Rm.add_child(th); mrow.add_child(Rm)
	parent.add_child(mrow)
	
	var rr: HBoxContainer = HBoxContainer.new(); rr.add_theme_constant_override("separation", 8); rr.alignment=BoxContainer.ALIGNMENT_CENTER
	rr.add_child(_mk_label("资源富饶度:",13,Color(0.85,0.8,0.7)))
	rr.add_child(_mk_cycle_btn(func(): _cycle_richness(-1), "◀"))
	richness_lbl = Label.new(); richness_lbl.add_theme_font_size_override("font_size",14); rr.add_child(richness_lbl)
	rr.add_child(_mk_cycle_btn(func(): _cycle_richness(1), "▶")); parent.add_child(rr)

# ---------- AI ----------
func _build_ai(parent: VBoxContainer) -> void:
	var r1: HBoxContainer = HBoxContainer.new(); r1.add_theme_constant_override("separation", 20)
	r1.add_child(_mk_label("敌对 AI:",14,Color(0.85,0.8,0.7)))
	enemy_count_spin = SpinBox.new(); enemy_count_spin.min_value=1; enemy_count_spin.max_value=7; enemy_count_spin.step=1
	enemy_count_spin.value=selected_ai_enemy; enemy_count_spin.custom_minimum_size=Vector2(70,32)
	enemy_count_spin.value_changed.connect(func(v: float): selected_ai_enemy=int(v)); r1.add_child(enemy_count_spin)
	r1.add_child(_mk_label("同盟 AI:",14,Color(0.85,0.8,0.7)))
	ally_count_spin = SpinBox.new(); ally_count_spin.min_value=0; ally_count_spin.max_value=7; ally_count_spin.step=1
	ally_count_spin.value=selected_ai_ally; ally_count_spin.custom_minimum_size=Vector2(70,32)
	ally_count_spin.value_changed.connect(func(v: float): selected_ai_ally=int(v)); r1.add_child(ally_count_spin)
	parent.add_child(r1)
	
	var r2: HBoxContainer = HBoxContainer.new(); r2.add_theme_constant_override("separation",10); r2.alignment=BoxContainer.ALIGNMENT_CENTER
	r2.add_child(_mk_label("AI 强度:",14,Color(0.85,0.8,0.7)))
	r2.add_child(_mk_cycle_btn(func(): _cycle_ai_intensity(-1), "◀"))
	ai_intensity_lbl = Label.new(); ai_intensity_lbl.add_theme_font_size_override("font_size",16); r2.add_child(ai_intensity_lbl)
	r2.add_child(_mk_cycle_btn(func(): _cycle_ai_intensity(1), "▶")); parent.add_child(r2)

# ---------- 特色 ----------
func _build_features(parent: VBoxContainer) -> void:
	var r1: HBoxContainer = HBoxContainer.new()
	r1.add_theme_constant_override("separation",22); r1.alignment=BoxContainer.ALIGNMENT_CENTER
	r1.add_child(_mk_label("黑雾:",14,Color(0.85,0.8,0.7)))
	r1.add_child(_mk_cycle_btn(func(): selected_fog=not selected_fog; _refresh_labels(), "◀"))
	fog_lbl = Label.new(); fog_lbl.add_theme_font_size_override("font_size",14); r1.add_child(fog_lbl)
	r1.add_child(_mk_cycle_btn(func(): selected_fog=not selected_fog; _refresh_labels(), "▶"))
	r1.add_child(_mk_label("灾祸:",14,Color(0.85,0.8,0.7)))
	r1.add_child(_mk_cycle_btn(func(): selected_disaster=not selected_disaster; _refresh_labels(), "◀"))
	disaster_lbl = Label.new(); disaster_lbl.add_theme_font_size_override("font_size",14); r1.add_child(disaster_lbl)
	r1.add_child(_mk_cycle_btn(func(): selected_disaster=not selected_disaster; _refresh_labels(), "▶"))
	r1.add_child(_mk_label("中立势力:",14,Color(0.85,0.8,0.7)))
	r1.add_child(_mk_cycle_btn(func(): selected_neutral_forces=not selected_neutral_forces; _refresh_labels(), "◀"))
	neutral_lbl = Label.new(); neutral_lbl.add_theme_font_size_override("font_size",14); r1.add_child(neutral_lbl)
	r1.add_child(_mk_cycle_btn(func(): selected_neutral_forces=not selected_neutral_forces; _refresh_labels(), "▶"))
	parent.add_child(r1)
	
	var t := Label.new()
	t.text = "灾祸开启后：每月 8% 几率随机出现「旱涝/瘟疫/地震/蝗灾」之一（不同时出现）。旱涝→官府花金赈灾。瘟疫→缓慢掉血一月。地震→建筑 HP 损。蝗灾→本月农业 -30%。"
	t.add_theme_font_size_override("font_size",11); t.add_theme_color_override("font_color", Color(0.65,0.6,0.5))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(t)
	
	var r2: HBoxContainer = HBoxContainer.new()
	r2.add_theme_constant_override("separation",22); r2.alignment=BoxContainer.ALIGNMENT_CENTER
	r2.add_child(_mk_label("初始资源:",14,Color(0.85,0.8,0.7)))
	r2.add_child(_mk_cycle_btn(func(): _cycle_resources(-1), "◀"))
	resources_lbl = Label.new(); resources_lbl.add_theme_font_size_override("font_size",14); r2.add_child(resources_lbl)
	r2.add_child(_mk_cycle_btn(func(): _cycle_resources(1), "▶"))
	r2.add_child(_mk_label("胜利条件:",14,Color(0.85,0.8,0.7)))
	r2.add_child(_mk_cycle_btn(func(): _cycle_victory(-1), "◀"))
	victory_lbl = Label.new(); victory_lbl.add_theme_font_size_override("font_size",14); r2.add_child(victory_lbl)
	r2.add_child(_mk_cycle_btn(func(): _cycle_victory(1), "▶"))
	r2.add_child(_mk_label("初始名将:",14,Color(0.85,0.8,0.7)))
	r2.add_child(_mk_cycle_btn(func(): _cycle_generals(-1), "◀"))
	generals_lbl = Label.new(); generals_lbl.add_theme_font_size_override("font_size",14); r2.add_child(generals_lbl)
	r2.add_child(_mk_cycle_btn(func(): _cycle_generals(1), "▶")); parent.add_child(r2)

# ===== 辅助构建 =====
func _mk_label(t: String, size: int, color: Color) -> Label:
	var l := Label.new(); l.text=t; l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color); return l

func _mk_section(t: String) -> HBoxContainer:
	var r := HBoxContainer.new(); r.add_theme_constant_override("separation",10)
	var l := Label.new(); l.text=t; l.add_theme_font_size_override("font_size",15)
	l.add_theme_color_override("font_color", Color(1.0,0.88,0.62)); r.add_child(l)
	var sep := HSeparator.new(); sep.size_flags_horizontal=Control.SIZE_EXPAND_FILL; r.add_child(sep); return r

func _mk_cycle_btn(cb: Callable, text: String) -> Button:
	var b := Button.new(); b.text=text; b.custom_minimum_size=Vector2(32,32)
	b.add_theme_font_size_override("font_size",16); b.pressed.connect(cb); return b

func _mk_panel(bg: Color, bd: Color, bw: int, cr: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color=bg; s.border_color=bd
	s.border_width_left=bw; s.border_width_right=bw; s.border_width_top=bw; s.border_width_bottom=bw
	s.corner_radius_top_left=cr; s.corner_radius_top_right=cr
	s.corner_radius_bottom_left=cr; s.corner_radius_bottom_right=cr; return s

# ===== 循环切换 =====
func _cycle_portrait(dir: int) -> void:
	if portrait_pool.is_empty(): return
	_portrait_index = (_portrait_index+dir+portrait_pool.size()) % portrait_pool.size()
	selected_portrait = str(portrait_pool[_portrait_index].get("id","")); _refresh_portrait()

func _cycle_color(dir: int) -> void:
	_color_index = (_color_index+dir+COLOR_NAMES.size()) % COLOR_NAMES.size()
	selected_color_key = COLOR_NAMES[_color_index]; _refresh_color()

func _cycle_richness(dir: int) -> void:
	var i: int = RICHNESS_ORDER.find(selected_richness)
	if i<0: i=0
	selected_richness = RICHNESS_ORDER[(i+dir+RICHNESS_ORDER.size()) % RICHNESS_ORDER.size()]

func _cycle_ai_intensity(dir: int) -> void:
	var i: int = AI_INTENSITY_ORDER.find(selected_ai_intensity)
	if i<0: i=1
	selected_ai_intensity = AI_INTENSITY_ORDER[(i+dir+AI_INTENSITY_ORDER.size()) % AI_INTENSITY_ORDER.size()]

func _cycle_resources(dir: int) -> void:
	var i: int = RESOURCES_ORDER.find(selected_initial_resources)
	if i<0: i=1
	selected_initial_resources = RESOURCES_ORDER[(i+dir+RESOURCES_ORDER.size()) % RESOURCES_ORDER.size()]

func _cycle_victory(dir: int) -> void:
	var i: int = VICTORY_ORDER.find(selected_victory)
	if i<0: i=0
	selected_victory = VICTORY_ORDER[(i+dir+VICTORY_ORDER.size()) % VICTORY_ORDER.size()]

func _cycle_generals(dir: int) -> void:
	var i: int = GENERALS_ORDER.find(selected_initial_generals)
	if i<0: i=1
	selected_initial_generals = GENERALS_ORDER[(i+dir+GENERALS_ORDER.size()) % GENERALS_ORDER.size()]

# ===== 选择回调 =====
func _on_faction(fid: String) -> void:
	if fid=="other": return
	selected_faction = fid

func _on_difficulty(did: String) -> void:
	selected_difficulty = did
	if did=="random_quick":
		var fa: Array = ["wei","shu","wu"]
		selected_faction = str(fa[randi()%fa.size()])
		_color_index = randi()%COLOR_NAMES.size(); selected_color_key = COLOR_NAMES[_color_index]
		selected_map_mode = "random"; selected_seed = randi()
		selected_ai_enemy = 1 + (randi()%3); selected_ai_ally = 0
		selected_ai_intensity = AI_INTENSITY_ORDER[randi()%AI_INTENSITY_ORDER.size()]

func _on_map_mode(m: String) -> void:
	selected_map_mode = m

func _on_map_selected_dropdown(_id: int) -> void:
	if map_option==null or map_option.item_count==0: return
	selected_map_id = map_option.get_item_text(_id)

func _on_size(k: String) -> void:
	selected_size_key = k

func _on_roll() -> void:
	selected_seed = randi(); if _seed_display: _seed_display.text = "种子: %d" % selected_seed

func _refresh_map_dropdown() -> void:
	if map_option==null: return
	map_option.clear()
	var maps: Dictionary = DataLoader.maps.get("maps",{})
	for mid in maps.keys():
		var m: Dictionary = maps[mid]
		var cities: Array = m.get("cities", [])
		map_option.add_item("%s  |  %d城 / 尺寸%d×%d" % [m.get("name",str(mid)), cities.size(), m.get("size",0), m.get("size",0)])

func _refresh_saved_list() -> void:
	if _saved_option==null: return
	_saved_option.clear()
	for n in MapSave.list_maps(): _saved_option.add_item(n)

func _on_saved_selected(id: int) -> void:
	if id<0 or _saved_option.item_count==0: return
	selected_save_name = _saved_option.text

func _on_saved_delete() -> void:
	if _saved_option==null or _saved_option.text=="": return
	MapSave.delete_map(_saved_option.text); _refresh_saved_list()

# ===== 刷新 =====
func _refresh_all() -> void:
	_refresh_style()
	_refresh_labels()
	_refresh_portrait()
	_refresh_color()
	_refresh_map_btns()
	_refresh_size_btns()
	if _seed_display: _seed_display.text = "种子: %d" % selected_seed
	if player_name_edit: player_name_edit.text = player_name

func _refresh_style() -> void:
	var btns: Array = _collect_btns()
	for i in range(btns.size()):
		var b: Button = btns[i]
		var n: String = b.name
		if n.begins_with("f_"):
			var fid: String = n.substr(2); if fid=="other": continue
			_set_btn(b, fid==selected_faction, FACTION_INFO[fid]["color"])
		elif n.begins_with("diff_"):
			_set_btn(b, n==("diff_"+selected_difficulty), Color(0.4,0.3,0.1))

func _refresh_labels() -> void:
	if faction_desc_label: faction_desc_label.text = FACTION_INFO[selected_faction]["desc"] if FACTION_INFO.has(selected_faction) else ""
	if richness_lbl:
		var r: Dictionary = MAP_RICHNESS[selected_richness]
		richness_lbl.text = "%s（%s · 城内矿%d · 鱼%d）" % [r["name"], r["trees"], r["mines_in"], r["fish_in"]]
	if ai_intensity_lbl:
		var d: Dictionary = AI_INTENSITY_DATA[selected_ai_intensity]
		ai_intensity_lbl.text = "%s（资源×%.1f · %s士兵）" % [d["name"], d["res_mult"], "标准" if (d.get("extra",{}) as Dictionary).is_empty() else "增强"]
	if fog_lbl: fog_lbl.text = ON_OFF_LABEL[0 if not selected_fog else 1]
	if disaster_lbl: disaster_lbl.text = ON_OFF_LABEL[0 if not selected_disaster else 1]
	if neutral_lbl: neutral_lbl.text = ON_OFF_LABEL[0 if not selected_neutral_forces else 1]
	if resources_lbl: resources_lbl.text = INITIAL_RESOURCES[selected_initial_resources]["name"]
	if victory_lbl:
		var vkey: String = selected_victory
		if not VICTORY_CONDITIONS.has(vkey): vkey = "eliminate"
		victory_lbl.text = VICTORY_CONDITIONS[vkey]["name"]
	if generals_lbl: generals_lbl.text = INITIAL_GENERALS[selected_initial_generals]["name"]

func _refresh_portrait() -> void:
	if portrait_display==null or portrait_pool.is_empty(): return
	var p: Dictionary = portrait_pool[_portrait_index]
	portrait_display.text = str(p.get("emoji","👤"))
	if portrait_name_lbl: portrait_name_lbl.text = str(p.get("name",""))

func _refresh_color() -> void:
	if color_display_rect==null: return
	color_display_rect.color = GameManager.FACTION_COLORS.get(selected_color_key, Color.RED)
	if color_display_lbl: color_display_lbl.text = COLOR_LABELS[_color_index]

func _refresh_map_btns() -> void:
	for k in _mode_buttons.keys(): _set_btn(_mode_buttons[k], str(k)==selected_map_mode, Color(0.4,0.3,0.1))
func _refresh_size_btns() -> void:
	for k in _size_buttons.keys(): _set_btn(_size_buttons[k], str(k)==selected_size_key, Color(0.4,0.3,0.1))

func _set_btn(b: Button, sel: bool, col: Color) -> void:
	b.button_pressed = sel
	var s := StyleBoxFlat.new()
	s.bg_color = col if sel else Color(0.18,0.14,0.09)
	s.border_color = Color(1.0,0.88,0.62) if sel else Color(0.35,0.28,0.20)
	s.border_width_left=3 if sel else 1; s.border_width_right=3 if sel else 1
	s.border_width_top=3 if sel else 1; s.border_width_bottom=3 if sel else 1
	s.corner_radius_top_left=6; s.corner_radius_top_right=6
	s.corner_radius_bottom_left=6; s.corner_radius_bottom_right=6
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_color_override("font_color", Color.WHITE if sel else Color(0.85,0.8,0.7))

func _collect_btns() -> Array:
	var r: Array = []; _walk_btns(self, r); return r
func _walk_btns(n: Node, r: Array) -> void:
	var children: Array = n.get_children()
	for i in range(children.size()):
		var c: Node = children[i]
		if c is Button: r.append(c)
		_walk_btns(c, r)

# ===== 开始 =====
func _on_start_pressed() -> void:
	var ai_data: Dictionary = AI_INTENSITY_DATA[selected_ai_intensity]
	var res_data: Dictionary = INITIAL_RESOURCES[selected_initial_resources]
	var base: Dictionary = ai_data["base_soldiers"]
	var extra: Dictionary = ai_data["extra"]
	var soldiers: Dictionary = base.duplicate()
	var extra_keys: Array = extra.keys()
	for i in range(extra_keys.size()):
		var k: String = str(extra_keys[i])
		soldiers[k] = int(soldiers.get(k, 0)) + int(extra[k])
	var civils_initial: int = int(soldiers.get("civil", 1))
	
	var cfg: Dictionary = {}
	cfg["player_faction"]         = selected_faction
	cfg["player_color"]           = GameManager.FACTION_COLORS.get(selected_color_key, Color.RED).to_html()
	cfg["player_color_key"]       = selected_color_key
	cfg["player_portrait"]        = selected_portrait
	cfg["player_name"]            = player_name
	cfg["difficulty"]             = selected_difficulty
	cfg["ai_intensity"]           = selected_ai_intensity
	cfg["ai_res_mult"]            = ai_data["res_mult"]
	cfg["initial_resources_mult"] = res_data["mult"]
	cfg["map_id"]                 = selected_map_id
	cfg["map_mode"]               = selected_map_mode
	cfg["map_seed"]               = selected_seed
	cfg["map_saved_name"]         = selected_save_name
	cfg["map_size_key"]           = selected_size_key
	cfg["map_richness"]           = selected_richness
	cfg["ai_enemy_count"]         = selected_ai_enemy
	cfg["ai_ally_count"]          = selected_ai_ally
	cfg["fog_of_war"]             = selected_fog
	cfg["disasters"]              = selected_disaster
	cfg["neutral_forces"]         = selected_neutral_forces
	cfg["victory_condition"]      = selected_victory
	cfg["initial_peasants"]       = 5
	cfg["initial_soldiers"]       = soldiers
	cfg["initial_generals_count"] = selected_initial_generals
	cfg["initial_civils"]         = civils_initial
	
	GameManager.game_settings_override = cfg
	var c := ConfigFile.new()
	var keys: Array = cfg.keys()
	for i in range(keys.size()): c.set_value("game", str(keys[i]), cfg[keys[i]])
	c.save("user://game_settings.cfg")
	print("[MainMenu] === 开始游戏 ===")
	for i in range(keys.size()): print("  %s = %s" % [str(keys[i]), cfg[keys[i]]])
	get_tree().change_scene_to_file("res://scenes/Loading.tscn")
