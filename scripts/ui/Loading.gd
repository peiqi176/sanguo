extends Control
## Loading — 游戏加载页面
## 半透明黑底 + 渐变进度条 + 三国典故提示

var _progress: float = 0.0
var _progress_bar: ProgressBar = null
var _tip_label: Label = null
var _title_label: Label = null
var _hints: Array = [
	"曹操：宁教我负天下人，休教天下人负我。",
	"诸葛亮：鞠躬尽瘁，死而后已。",
	"关羽：玉可碎而不可改其白，竹可焚而不可毁其节。",
	"刘备：勿以恶小而为之，勿以善小而不为。",
	"孙权：生子当如孙仲谋！",
	"周瑜：既生瑜，何生亮？",
	"司马懿：鹰视狼顾，隐忍待机。",
	"张飞：俺也去！",
	"赵云：吾乃常山赵子龙！",
	"诸葛亮：攻心为上，攻城为下。",
]

func _ready() -> void:
	_build_ui()
	var tween := create_tween()
	tween.tween_interval(0.15)
	tween.tween_property(self, "_progress", 1.0, 2.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_on_load_done)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	
	_title_label = Label.new()
	_title_label.text = "⚔ 三分天下·再起 ⚔"
	_title_label.anchor_top = 0.28
	_title_label.anchor_right = 1.0
	_title_label.anchor_bottom = 0.28
	_title_label.add_theme_font_size_override("font_size", 56)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.85, 0.55))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_label)
	
	var sub := Label.new()
	sub.text = "TRIPARTITE: RISE OF THE HEROES"
	sub.anchor_top = 0.28
	sub.offset_top = 60.0
	sub.anchor_right = 1.0
	sub.anchor_bottom = 0.28
	sub.offset_bottom = 90.0
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.55, 0.50, 0.40))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	
	var bar_bg := Panel.new()
	bar_bg.anchor_left = 0.25
	bar_bg.anchor_right = 0.75
	bar_bg.anchor_top = 0.55
	bar_bg.anchor_bottom = 0.55
	bar_bg.offset_bottom = 24.0
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.13, 0.10)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	bar_bg.add_theme_stylebox_override("panel", bg_style)
	add_child(bar_bg)
	
	_progress_bar = ProgressBar.new()
	_progress_bar.anchor_left = 0.25
	_progress_bar.anchor_right = 0.75
	_progress_bar.anchor_top = 0.55
	_progress_bar.anchor_bottom = 0.55
	_progress_bar.offset_bottom = 24.0
	_progress_bar.show_percentage = false
	_progress_bar.max_value = 1.0
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.85, 0.70, 0.25)
	bar_style.corner_radius_top_left = 4
	bar_style.corner_radius_top_right = 4
	bar_style.corner_radius_bottom_left = 4
	bar_style.corner_radius_bottom_right = 4
	_progress_bar.add_theme_stylebox_override("fill", bar_style)
	add_child(_progress_bar)
	
	_tip_label = Label.new()
	var tip_idx: int = randi() % _hints.size()
	_tip_label.text = "💡 %s" % _hints[tip_idx]
	_tip_label.anchor_top = 0.63
	_tip_label.anchor_right = 1.0
	_tip_label.anchor_bottom = 0.63
	_tip_label.add_theme_font_size_override("font_size", 18)
	_tip_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.60))
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_tip_label)
	
	var load_txt := Label.new()
	load_txt.text = "LOADING..."
	load_txt.anchor_top = 0.63
	load_txt.offset_top = 25.0
	load_txt.anchor_right = 1.0
	load_txt.anchor_bottom = 0.63
	load_txt.offset_bottom = 50.0
	load_txt.add_theme_font_size_override("font_size", 14)
	load_txt.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	load_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(load_txt)
	
	var footer := Label.new()
	footer.text = "RTS Demo · 三国题材 · 傲世三国风格"
	footer.anchor_top = 0.92
	footer.anchor_right = 1.0
	footer.anchor_bottom = 0.92
	footer.offset_bottom = 20.0
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", Color(0.4, 0.38, 0.32))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer)

func _process(delta: float) -> void:
	if _progress_bar:
		_progress_bar.value = _progress

func _on_load_done() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
