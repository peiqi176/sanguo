extends Control
## MapGenerator — 地图生成器（可视化调参面板 / 工具场景）
## 滑块调参 + 种子 + 实时顶视预览；可保存/载入/删除地图，也可直接「用此地图开始游戏」。
## 运行方式：编辑器内打开此场景，或主菜单「地图编辑器」入口。autoload（Terrain/MapSave）需已注册。

var params = null  # MapParams
var _preview: TextureRect = null
var _seed_edit: LineEdit = null
var _save_name: LineEdit = null
var _map_list: OptionButton = null
var _status: Label = null

# 滑块规格：[参数名, 显示标签, 最小值, 最大值, 步长, 是否整数]
const SLIDERS: Array = [
	["height_scale", "地形起伏", 0.30, 1.50, 0.01, false],
	["island_radius", "岛屿半径", 60.0, 160.0, 1.0, false],
	["river_count", "河流数量", 0, 6, 1, true],
	["river_width", "河流宽度", 2.0, 15.0, 0.5, false],
	["river_depth", "河流深度", 0.3, 1.0, 0.05, false],
	["lake_count", "湖泊数量", 0, 6, 1, true],
	["lake_radius", "湖泊半径", 8.0, 40.0, 1.0, false],
	["forest_density", "森林密度", 0.30, 2.50, 0.05, false],
	["dirt_density", "土地密度", 0.30, 2.50, 0.05, false],
	["stone_density", "石板密度", 0.30, 2.50, 0.05, false],
	["water_level", "水面高度", -10.0, 0.0, 0.5, false],
]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var MP := preload("res://scripts/core/MapParams.gd")
	params = Terrain.params.duplicate() if Terrain.params != null else MP.new()
	_build_ui()
	_regenerate()

func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.13, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 16)
	hb.position = Vector2(16, 16)
	hb.size = get_viewport_rect().size - Vector2(32, 32)
	add_child(hb)

	# 左：预览
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 10)
	hb.add_child(left)
	var ptitle := Label.new(); ptitle.text = "顶视预览（高度+群系）"; ptitle.add_theme_color_override("font_color", Color(0.9,0.85,0.6)); left.add_child(ptitle)
	_preview = TextureRect.new()
	_preview.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_preview.custom_minimum_size = Vector2(360, 360)
	_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	left.add_child(_preview)
	_status = Label.new(); _status.text = ""; _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; left.add_child(_status)

	# 右：调参 + 操作
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	var title := Label.new(); title.text = "⚔ 地图生成器"; title.add_theme_font_size_override("font_size", 28); title.add_theme_color_override("font_color", Color(0.95,0.88,0.55)); right.add_child(title)

	# 种子行
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	var sl := Label.new(); sl.text = "种子"; seed_row.add_child(sl)
	_seed_edit = LineEdit.new(); _seed_edit.custom_minimum_size = Vector2(140, 0); _seed_edit.text = str(params.seed); seed_row.add_child(_seed_edit)
	var rnd := Button.new(); rnd.text = "🎲 随机"; rnd.pressed.connect(_on_random_seed); seed_row.add_child(rnd)
	var gen := Button.new(); gen.text = "🔄 生成"; gen.pressed.connect(_on_generate); seed_row.add_child(gen)
	right.add_child(seed_row)

	# 滑块（可滚动）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var sbox := VBoxContainer.new(); sbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sbox.add_theme_constant_override("separation", 4); scroll.add_child(sbox)
	for spec in SLIDERS:
		_add_slider(sbox, spec[0], spec[1], spec[2], spec[3], spec[4], spec[5])

	# 存档行
	var save_row := HBoxContainer.new(); save_row.add_theme_constant_override("separation", 8)
	var snl := Label.new(); snl.text = "存档名"; save_row.add_child(snl)
	_save_name = LineEdit.new(); _save_name.custom_minimum_size = Vector2(150, 0); _save_name.text = "我的地图"; save_row.add_child(_save_name)
	var save_btn := Button.new(); save_btn.text = "💾 保存"; save_btn.pressed.connect(_on_save); save_row.add_child(save_btn)
	var load_btn := Button.new(); load_btn.text = "📂 载入"; load_btn.pressed.connect(_on_load_selected); save_btn.add_theme_color_override("font_color", Color(1,1,1)); save_row.add_child(load_btn)
	var del_btn := Button.new(); del_btn.text = "🗑 删除"; del_btn.pressed.connect(_on_delete_selected); save_row.add_child(del_btn)
	right.add_child(save_row)

	# 地图下拉
	_map_list = OptionButton.new(); _map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; right.add_child(_map_list)
	_refresh_map_list()

	# 开始游戏
	var start := Button.new(); start.text = "▶ 用此地图开始游戏"; start.custom_minimum_size = Vector2(0, 44); start.add_theme_font_size_override("font_size", 20)
	start.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	start.pressed.connect(_on_start_game)
	right.add_child(start)

func _add_slider(parent: Control, pname: String, label: String, mn: float, mx: float, st: float, is_int: bool) -> void:
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 8)
	var lab := Label.new(); lab.text = label; lab.custom_minimum_size = Vector2(96, 0); hb.add_child(lab)
	var sl := HSlider.new(); sl.min_value = mn; sl.max_value = mx; sl.step = st; sl.value = float(params.get(pname)); sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := Label.new(); val.custom_minimum_size = Vector2(56, 0); val.text = _fmt(params.get(pname), is_int)
	sl.connect("value_changed", func(v: float) -> void:
		params.set(pname, int(v) if is_int else v)
		val.text = _fmt(v, is_int)
	)
	sl.connect("drag_ended", func(_b: bool) -> void: _regenerate())
	hb.add_child(sl); hb.add_child(val)
	parent.add_child(hb)

func _fmt(v: float, is_int: bool) -> String:
	return (str(int(v)) if is_int else "%.2f" % v)

func _regenerate() -> void:
	Terrain.generate(params)
	_refresh_preview()
	_status.text = "种子 %d · 水面 %.1f · 河×%d 湖×%d · 森/土/石 %.2f/%.2f/%.2f" % [
		params.seed, params.water_level, params.river_count, params.lake_count,
		params.forest_density, params.dirt_density, params.stone_density]

## 顶视预览：高度明暗 + 群系配色 + 水域
func _refresh_preview() -> void:
	var hi: Image = Terrain.heightmap_img
	var bi: Image = Terrain.biome_img
	if hi == null or bi == null:
		return
	var W: int = hi.get_width(); var H: int = hi.get_height()
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var grass := Color(0.38, 0.50, 0.24)
	var forest := Color(0.18, 0.36, 0.16)
	var dirt := Color(0.46, 0.37, 0.25)
	var stone := Color(0.55, 0.55, 0.58)
	var water := Color(0.20, 0.42, 0.62)
	var snow := Color(0.92, 0.94, 0.97)
	for y in H:
		for x in W:
			var h: float = hi.get_pixel(x, y).r * params.max_height
			var bw: Color = bi.get_pixel(x, y)
			var col: Color = grass
			col = col.lerp(forest, clamp(bw.r, 0.0, 1.0))
			col = col.lerp(dirt, clamp(bw.g, 0.0, 1.0))
			col = col.lerp(stone, clamp(bw.b, 0.0, 1.0))
			if h < params.water_level:
				col = water
			else:
				var sh: float = clamp((h - params.water_level) / params.max_height, 0.0, 1.0)
				col = col * (0.45 + 0.55 * sh)
				if sh > 0.80:   # 雪线
					col = col.lerp(snow, clamp((sh - 0.80) / 0.20, 0.0, 1.0))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))
	_preview.texture = ImageTexture.create_from_image(img)

func _on_random_seed() -> void:
	params.seed = randi()
	_seed_edit.text = str(params.seed)
	_regenerate()

func _on_generate() -> void:
	var s: int = params.seed
	if _seed_edit.text.is_valid_int():
		s = _seed_edit.text.to_int()
	params.seed = s
	_seed_edit.text = str(s)
	_regenerate()

func _on_save() -> void:
	var name: String = _save_name.text.strip_edges()
	if name == "":
		_status.text = "⚠ 存档名不能为空"
		return
	if MapSave.save_current_map(name):
		_status.text = "✅ 已保存：%s" % name
		_refresh_map_list()
	else:
		_status.text = "❌ 保存失败"

func _refresh_map_list() -> void:
	if _map_list == null:
		return
	_map_list.clear()
	for m in MapSave.list_maps():
		_map_list.add_item(m)

func _on_load_selected() -> void:
	var idx: int = _map_list.get_selected_id() if _map_list.get_selected_id() != -1 else -1
	var txt: String = _map_list.text
	if txt == "":
		_status.text = "⚠ 请先在下拉选择一个地图"
		return
	var p = MapSave.load_map(txt)  # MapParams
	if p != null:
		params = p
		_seed_edit.text = str(params.seed)
		_status.text = "✅ 已载入：%s（拖动滑块即可继续微调）" % txt
		_refresh_preview()

func _on_delete_selected() -> void:
	var txt: String = _map_list.text
	if txt == "":
		return
	MapSave.delete_map(txt)
	_status.text = "🗑 已删除：%s" % txt
	_refresh_map_list()

func _on_start_game() -> void:
	Terrain.generate(params)   # 确保当前参数已应用
	# 告知 Main：地形已由本编辑器生成，直接使用（不再重生成），并按当前 world_size 缩放网格
	GameManager.game_settings_override["map_mode"] = "live"
	GameManager.game_settings_override["map_size_key"] = "large"
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
