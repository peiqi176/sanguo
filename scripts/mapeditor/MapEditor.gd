extends Node3D
const MapDoc = preload("res://scripts/mapformat/MapDoc.gd")
const MapIO = preload("res://scripts/mapformat/MapIO.gd")
const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")
const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")
const UndoStack = preload("res://scripts/mapeditor/UndoStack.gd")
const EditorUI = preload("res://scripts/mapeditor/EditorUI.gd")
const EditorScene = preload("res://scripts/mapeditor/EditorScene.gd")
const TerrainPicker = preload("res://scripts/mapeditor/TerrainPicker.gd")
const ObjectLayer = preload("res://scripts/mapeditor/ObjectLayer.gd")
const PalettePanel = preload("res://scripts/mapeditor/PalettePanel.gd")
const InspectorPanel = preload("res://scripts/mapeditor/InspectorPanel.gd")
const AssetImportDialog = preload("res://scripts/mapeditor/AssetImportDialog.gd")
const EntityImportDialog = preload("res://scripts/mapeditor/EntityImportDialog.gd")
const GridManager = preload("res://scripts/core/GridManager.gd")

## MapEditor —— 地图工坊主控（生命周期 / 状态 / 输入路由 / 射线拾取）
##
## 职责边界（拆过一次，别再把东西塞回来）：
##   本文件        = 场景搭建 + 输入分发 + 地形拾取 + 状态持有
##   TerrainBrush  = 笔刷算子（纯函数，可 headless 自测）
##   UndoStack     = 撤销栈（按脏矩形存差量）
##   EditorUI      = 控件与文案
##   MapDoc/MapIO  = 数据模型与磁盘格式
##
## 设计要点（和 docs/地图编辑器_方案_v1.md 一致）：
##   1. 地形渲染**完全复用游戏**的 TerrainMaterial + Terrain 高度图，
##      所以「编辑器里看到的 = 游戏里跑出来的」，不存在第二套预览代码。
##   2. 地形高度是 shader 顶点位移，不是真网格顶点 —— 改一个像素只要
##      `heightmap_tex.update()` 就立刻可见，不需要重建 ArrayMesh。
##   3. 鼠标拾取不用物理碰撞体，直接沿射线步进采样 Terrain.get_height()。
##      好处：与实体贴地用的是同一个函数，绝不会出现"碰撞体和视觉不一致"。
##
## 数据归属（很重要，别搞混）：
##   · 地形**图**活在 Terrain autoload 里（笔刷直接改 Terrain.heightmap_img）
##   · 对象/玩家/区域活在 `doc`（MapDoc）里
##   · 存盘时两者合流到 MapIO，磁盘上才是一份完整地图
##
## 操作：
##   左键拖动 = 用地形笔刷   1/2/3/4 = 抬升/下压/平滑/平台
##   WASD 平移 · Q/E 旋转 · 滚轮缩放 · 中键拖动 = 转视角
##   Ctrl+Z 撤销 · Ctrl+Y 重做 · Ctrl+S 保存 · F5 保存并试玩

const UNDO_MAX: int = 32        # 差量存储后可以给更多步（原来整图快照只敢 16）

## 工具模式：同一颗左键在不同模式下干不同的事
##   TERRAIN 刷地形（默认）  PLACE 落对象  SELECT 选对象
enum Tool { TERRAIN, PLACE, SELECT }

var tool_mode: int = Tool.TERRAIN
## 放建筑/单位时写进 doc.objects[].owner 的阵营
var paint_owner: String = "shu"

var brush_radius: float = 12.0      # 世界单位（米）
var brush_strength: float = 0.55    # 每秒世界高度变化（米/秒）
## mode = -1 表示"还没选笔刷"。⚠️ 进编辑器什么都不按、直接拖鼠标是**什么都不做**的——
## 必须先按 1~4（抬升/下压/平滑/平台）或 5~8（贴图层）选中一个算子，左键才有作用。
## 这是用户明确要求的手感：不许"一进来鼠标划过就把地面顶起来"。
const MODE_NONE: int = -1
var mode: int = MODE_NONE
## 当前笔刷作用层：-1 = 地形高度（抬升/下压/平滑/平台），0~3 = 拼图层（沙/土/岩/林）
## 高度和拼图是两张不同的图，但共用同一颗左键、同一个笔刷圈、同一套撤销——
## 只有"落在哪张图上"不同，所以用这一个字段区分就够了，不引入第四种工具模式。
var paint_layer: int = -1
## 当前笔刷的变种选择（2026-10-29）：-1 = 自动噪声分带，0~4 = 手选草种/石板种。
## 作用随 paint_layer 走：层=石板路时是石板种（splat2.A），层=草地时是草种（splat2.B）。
var paint_variant: int = -1

## 当前地图文档（对象层/玩家层/区域层都存这里；地形图不在这里，在 Terrain）
var doc = null
var _dirty: bool = false

var cam_ctrl: Node3D = null
var terrain_mesh: MeshInstance3D = null
var brush_ring: MeshInstance3D = null
var grid_root: MeshInstance3D = null

var undo_stack = null
## 拼图层有**自己独立**的撤销栈。
## 为什么不能和高度共用一个：UndoStack.undo(img) 会把记录里的像素块贴进传进来的
## 那张图。高度图是 FORMAT_RF、拼图是 RGBA8，字节布局完全不同 —— 混用一条栈，
## Ctrl+Z 可能把高度图像素贴进拼图里，画面直接花掉且无报错。
var splat_undo = null
## 道路层（splat2：石板路/土路）的撤销栈，与 splat_undo 同规格
var splat2_undo = null
## 统一的操作顺序日志：记录每条撤销记录属于哪张图。
## Ctrl+Z 要撤"最近一次操作"，而最近一次可能是高度也可能是拼图，
## 只看 undo_stack 是否为空会撤错张。
var _undo_kind: Array = []
var _redo_kind: Array = []
const KIND_HEIGHT: String = "height"
const KIND_SPLAT: String = "splat"
const KIND_SPLAT2: String = "splat2"   # 道路层（石板路/土路）
const KIND_ROAD: String = "road"       # 道路笔画 = 路芯(splat2) + 泥土路肩(splat1)，双栈撤销
var _ui = null
var obj_layer = null
var palette = null
var inspector = null
var import_dialog = null
var entity_dialog = null
## 编辑器自己的网格（**不复用 Main 的**，否则会污染 GameManager.grid）
var grid = null

var _painting: bool = false
var _flatten_target: float = 0.0
var _last_hit: Variant = null

# ---------------------------------------------------------------- 启动

func _ready() -> void:
	# 🗺 编辑器里摆的是**真实**实体（不是占位盒），必须让它们停摆：
	# 否则放 20 个建筑，建造进度、资源产出、训练队列会自己跑起来。
	# Main._ready() 第一件事会把它复位为 false。
	GameManager.editor_mode = true

	# 🗺 编辑器 = AoE4 式"白纸"：进场永远生成一张全平地图（平地+纯草+无河无海）。
	# 旧逻辑只在 heightmap 为空时生成，导致上一局程序生成的起伏地形被沿用，
	# 用户要"地面平整"得自己拿 FLATTEN 笔刷慢慢压——现在直接从平地开始。
	# autoload Terrain 在 _ready 已生成过默认图，这里无条件覆盖成平地。
	var flat_p := Terrain.default_params()
	flat_p.flat_ground = true
	Terrain.generate(flat_p)

	undo_stack = UndoStack.new()
	undo_stack.max_steps = UNDO_MAX
	splat_undo = UndoStack.new()
	splat_undo.max_steps = UNDO_MAX
	splat2_undo = UndoStack.new()
	splat2_undo.max_steps = UNDO_MAX

	# 拼图层：编辑器里一定存在（笔刷要就地改它）
	Terrain.ensure_splat()

	_new_doc()

	# 编辑器自己的网格：占位判断（能不能放建筑）靠它。
	# 尺寸必须和 doc 一致，否则放下去的位置和存盘里的 grid 对不上。
	grid = GridManager.new()
	grid.name = "EditorGrid"
	add_child(grid)
	grid.map_size = Vector2i(doc.grid_n, doc.grid_n)
	grid.cell_size = doc.cell_size
	grid._init_grid()

	# 3D 画布：环境 / 地形 / 格子线 / 笔刷圈 一次性搭好（细节都在 EditorScene）
	var hms: int = Terrain.heightmap_img.get_width()
	EditorScene.build_environment(self)
	terrain_mesh = EditorScene.build_terrain(self, Terrain.params.world_size, hms)
	EditorScene.build_water(self)   # 编辑器也要有水面：压低地形立刻见水（所见即所得）
	grid_root = EditorScene.build_grid(self, Terrain.params.world_size, doc.cell_size)
	brush_ring = EditorScene.build_brush_ring(self)

	# 对象层要在 UI 之前建好：ghost 是场景里的一堆节点
	obj_layer = ObjectLayer.new()
	obj_layer.setup(self, grid)

	_build_ui()

	cam_ctrl = get_node_or_null("CameraController")
	if cam_ctrl != null:
		cam_ctrl.edge_scroll = false          # 编辑器有面板，边缘滚动会打架
		var ws: float = Terrain.params.world_size
		cam_ctrl.focus_on(Vector3(ws * 0.5, Terrain.get_height(ws * 0.5, ws * 0.5), ws * 0.5))
		if cam_ctrl.has_method("set_yaw_lock"):
			cam_ctrl.pitch_lock_deg = 45.0

	_refresh_doc_label()

	# 把 PNG 直接拖进窗口 = 打开导入窗口（M3-1 的"三步内可摆"主入口）
	var w: Window = get_window()
	if w != null and not w.files_dropped.is_connected(_on_files_dropped):
		w.files_dropped.connect(_on_files_dropped)

	print("[MapEditor] 就绪：高度图 %d²，世界 %s m" % [
		Terrain.heightmap_img.get_width(), Terrain.params.world_size])

## 从系统拖文件进来：只认 PNG，多张时只取第一张（批量导入走 tools/ 脚本）
func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		if f.to_lower().ends_with(".png"):
			open_import_dialog(f)
			return
	_toast("只支持 PNG 拖入（收到 %d 个文件）" % files.size())

## 打开导入窗口。path 可以是系统绝对路径，也可以是 res:// 下的未注册图。
func open_import_dialog(path: String) -> void:
	if path == "":
		return
	# 导入窗口是"编辑资产"的操作，先把放置 ghost 收起来，免得两个交互打架
	if tool_mode == Tool.PLACE:
		cancel_placement()
	import_dialog.open(path)

## 打开「导入建筑 / 兵种」窗口。kind_hint = "building" / "unit"，空则按当前调色板分类推断。
func open_entity_dialog(path: String, kind_hint: String = "") -> void:
	if path == "":
		return
	if tool_mode == Tool.PLACE:
		cancel_placement()
	entity_dialog.open(path, kind_hint)

# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _is_mouse_over_ui():
					return
				_on_left_press()
			else:
				_on_left_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_on_right_press()
	elif event is InputEventMouseMotion:
		_update_hover()
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)

func _on_left_press() -> void:
	var mp: Vector2 = get_viewport().get_mouse_position()
	match tool_mode:
		Tool.PLACE:
			if not obj_layer.place_at(mp):
				_toast("这里放不下（越界 / 压到已有对象 / 在水里）")
		Tool.SELECT:
			obj_layer.select_at(mp)
		_:
			_begin_stroke()

func _on_left_release() -> void:
	if tool_mode == Tool.TERRAIN:
		_end_stroke()

func _on_right_press() -> void:
	if tool_mode == Tool.PLACE:
		cancel_placement()
	elif tool_mode == Tool.SELECT:
		clear_selection()

func _on_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_1:
			set_tool_mode(Tool.TERRAIN)
			_set_mode(TerrainBrush.Mode.RAISE)
		KEY_2:
			set_tool_mode(Tool.TERRAIN)
			_set_mode(TerrainBrush.Mode.LOWER)
		KEY_3:
			set_tool_mode(Tool.TERRAIN)
			_set_mode(TerrainBrush.Mode.SMOOTH)
		KEY_4:
			set_tool_mode(Tool.TERRAIN)
			_set_paint_layer(-1)
			_set_mode(TerrainBrush.Mode.FLATTEN)
		KEY_5:
			set_tool_mode(Tool.TERRAIN)
			_set_paint_layer(SplatBrush.Layer.SAND)
		KEY_6:
			set_tool_mode(Tool.TERRAIN)
			_set_paint_layer(SplatBrush.Layer.DIRT)
		KEY_7:
			set_tool_mode(Tool.TERRAIN)
			_set_paint_layer(SplatBrush.Layer.ROCK)
		KEY_8:
			set_tool_mode(Tool.TERRAIN)
			_set_paint_layer(SplatBrush.Layer.FOREST)
		KEY_9:
			set_tool_mode(Tool.TERRAIN)
			_set_paint_layer(SplatBrush.Layer.PAVED)   # 石板路
		KEY_0:
			set_tool_mode(Tool.TERRAIN)
			_set_paint_layer(SplatBrush.Layer.ROAD)    # 土路
		KEY_G:
			set_tool_mode(Tool.TERRAIN)
			_set_paint_layer(SplatBrush.LAYER_GRASS)   # 草地（变种可选）
		KEY_V:
			set_tool_mode(Tool.SELECT)
		KEY_ESCAPE:
			cancel_placement()
			clear_selection()
			set_tool_mode(Tool.TERRAIN)
			# Esc = 退回"空手"状态：不算子、不涂贴图，防误刷
			_set_mode(MODE_NONE)
			_set_paint_layer(-1)
		KEY_DELETE:
			delete_selected()
		KEY_Z:
			if event.ctrl_pressed:
				_undo()
		KEY_Y:
			if event.ctrl_pressed:
				_redo()
		KEY_S:
			if event.ctrl_pressed:
				_save_map("")
		KEY_F5:
			_save_and_play()

func _process(delta: float) -> void:
	if _ui != null:
		_ui.tick(delta)

	if tool_mode == Tool.TERRAIN and _painting and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_apply_brush(delta)
	else:
		_painting = false

func _is_mouse_over_ui() -> bool:
	var vp: Viewport = get_viewport()
	var ctl: Control = vp.gui_get_hovered_control() if vp.has_method("gui_get_hovered_control") else null
	return ctl != null

## 鼠标 → 地形交点（实现见 TerrainPicker：沿射线步进 + 二分，和实体贴地同源）
func _ray_to_terrain() -> Variant:
	return TerrainPicker.ray_to_terrain(get_viewport())

func _update_hover() -> void:
	# 放置模式：ghost 跟手，地形笔刷圈收起（两个圈叠一起看不清）
	if tool_mode == Tool.PLACE:
		obj_layer.update_hover(get_viewport().get_mouse_position())
		EditorScene.rebuild_brush_ring(brush_ring, Vector3.INF, brush_radius)
		if _ui != null:
			_ui.set_pos_text("放置模式：左键落位 · 右键取消")
		return

	var hit: Variant = _ray_to_terrain()
	_last_hit = hit
	if hit == null:
		EditorScene.rebuild_brush_ring(brush_ring, Vector3.INF, brush_radius)
		if _ui != null:
			_ui.set_pos_text("光标：不在图上")
		return

	var v: Vector3 = hit
	if tool_mode == Tool.SELECT:
		EditorScene.rebuild_brush_ring(brush_ring, Vector3.INF, brush_radius)
		if _ui != null:
			_ui.set_pos_text("选择模式：x %.1f  z %.1f   高度 %.2f m" % [v.x, v.z, v.y])
		return

	EditorScene.rebuild_brush_ring(brush_ring, v, brush_radius)
	if _ui != null:
		_ui.set_pos_text("光标：x %.1f  z %.1f   高度 %.2f m" % [v.x, v.z, v.y])

# ---------------------------------------------------------------- 笔刷

func _begin_stroke() -> void:
	# 没选算子（mode=-1 且没选贴图层）时左键是"空手"：只显示提示，不动地形。
	if mode == MODE_NONE and paint_layer < 0:
		_toast("先按 1~4 选高度笔刷（1抬升 2下压 3平滑 4平台），5~8 刷地表，9/0 刷道路，G 刷草地")
		return
	var hit: Variant = _ray_to_terrain()
	if hit == null:
		return
	var c: Vector3 = hit
	# 平台笔刷的目标高度取起笔点 —— 与 get_height() 同源，不用另算
	_flatten_target = Terrain.get_height(c.x, c.z) / maxf(Terrain.params.max_height, 0.001)
	# ⚠️ 作用层在起笔那一刻锁定：拖动途中按 5~8 切层会让同一次笔画
	#    前半截刷高度、后半截刷拼图，撤销记录就没法对应了。
	_stroke_layer = paint_layer
	# 变种同样在起笔时锁定（只有石板路/草地两类层吃变种）
	if _stroke_layer == SplatBrush.Layer.PAVED or _stroke_layer == SplatBrush.LAYER_GRASS:
		_stroke_variant = paint_variant
	else:
		_stroke_variant = -1
	# 每笔换随机种子 → 有机边缘/路肩斑块每笔形状都不同（0 = 确定性，自测用）
	SplatBrush.stroke_seed = randi()
	if _is_road_layer(_stroke_layer) or _stroke_layer == SplatBrush.LAYER_GRASS:
		# 道路/草地笔画同时改两张图（splat2 + splat1）→ 两个栈都要记
		Terrain.ensure_splat2()
		splat2_undo.begin(Terrain.splat2_img)
		splat_undo.begin(Terrain.splat_img)
	elif _stroke_layer >= SplatBrush.LAYER_SPLAT2_START:
		Terrain.ensure_splat2()
		splat2_undo.begin(Terrain.splat2_img)
	elif _stroke_layer >= 0:
		splat_undo.begin(Terrain.splat_img)
	else:
		undo_stack.begin(Terrain.heightmap_img)
	_painting = true
	_apply_brush(0.016)

func _end_stroke() -> void:
	_painting = false
	var pushed: bool = false
	if _is_road_layer(_stroke_layer) or _stroke_layer == SplatBrush.LAYER_GRASS:
		var p1: bool = splat_undo.end(Terrain.splat_img)
		var p2: bool = splat2_undo.end(Terrain.splat2_img)
		pushed = p1 or p2
		if pushed:
			Terrain.refresh_splat_texture()
			Terrain.refresh_splat2_texture()
			_commit_kind(KIND_ROAD)
	elif _stroke_layer >= SplatBrush.LAYER_SPLAT2_START:
		pushed = splat2_undo.end(Terrain.splat2_img)
		if pushed:
			Terrain.refresh_splat2_texture()
			_commit_kind(KIND_SPLAT2)
	elif _stroke_layer >= 0:
		pushed = splat_undo.end(Terrain.splat_img)
		if pushed:
			Terrain.refresh_splat_texture()
			_commit_kind(KIND_SPLAT)
	else:
		pushed = undo_stack.end(Terrain.heightmap_img)
		if pushed:
			# 地形变了，建筑得重新贴地（单位自己会贴，建筑是 StaticBody 不会）
			if obj_layer != null:
				obj_layer.resnap()
			_commit_kind(KIND_HEIGHT)
	_dirty = _dirty or pushed
	if pushed:
		_refresh_neighbors()
	_update_undo_ui()

func _apply_brush(delta: float) -> void:
	var hit: Variant = _ray_to_terrain()
	if hit == null:
		return
	var c: Vector3 = hit
	_last_hit = c

	var ws: float = Terrain.params.world_size
	EditorScene.rebuild_brush_ring(brush_ring, c, brush_radius)

	if _stroke_layer >= 0:
		# ---- 拼图笔刷（5~8 = 沙/土/岩/林，9/0 = 石板路/土路）----
		# 层 4/5 住第二张拼图（splat2），层 0~3 住 splat
		var ssz: int = Terrain.splat_img.get_width()
		var s_center: Vector2 = TerrainBrush.world_to_pixel(c, ws, ssz)
		var s_radius: float = TerrainBrush.world_radius_to_pixel(brush_radius, ws, ssz)
		# 强度语义：覆盖度 0~1，默认滑杆(0.55)下按住约 0.8 秒刷满一层
		var amount: float = 2.2 * brush_strength * delta
		# 按住 Shift = 擦除（把已刷的层减回去，恢复成程序群系）
		if Input.is_key_pressed(KEY_SHIFT):
			amount = -amount
		if _stroke_layer == SplatBrush.LAYER_GRASS:
			# 草地笔刷：写 splat2.B 变种覆盖 + 清掉压着草的层（splat1 全部 + splat2 路面）
			var grect: Rect2i = SplatBrush.paint_grass_variant(Terrain.splat_img, Terrain.splat2_img,
					s_center, s_radius, _stroke_variant, amount)
			if grect.size.x > 0:
				splat_undo.mark(grect)
				splat2_undo.mark(grect)
				Terrain.splat_tex.update(Terrain.splat_img)
				Terrain.splat2_tex.update(Terrain.splat2_img)
				_dirty = true
			return
		if _is_road_layer(_stroke_layer):
			# 道路笔刷：路芯（splat2）+ 自动泥土路肩（splat1），一笔出三段式过渡；
			# 石板路带手选变种时顺带把 splat2.A 编码进去（土路没有变种）
			var rrect: Rect2i = SplatBrush.paint_road(Terrain.splat_img, Terrain.splat2_img,
					s_center, s_radius, _stroke_layer, amount, _stroke_variant)
			if rrect.size.x > 0:
				splat_undo.mark(rrect)
				splat2_undo.mark(rrect)
				Terrain.splat_tex.update(Terrain.splat_img)
				Terrain.splat2_tex.update(Terrain.splat2_img)
				_dirty = true
			return
		var on_road: bool = _stroke_layer >= SplatBrush.LAYER_SPLAT2_START
		Terrain.ensure_splat2()
		var simg: Image = Terrain.splat2_img if on_road else Terrain.splat_img
		var srect: Rect2i = SplatBrush.apply(simg, s_center, s_radius, _stroke_layer, amount, Terrain.splat2_img)
		if srect.size.x > 0:
			if on_road:
				splat2_undo.mark(srect)
				Terrain.splat2_tex.update(simg)
			else:
				splat_undo.mark(srect)
				Terrain.splat_tex.update(simg)
			_dirty = true
		return

	# ---- 高度笔刷（抬升/下压/平滑/平台）----
	var img: Image = Terrain.heightmap_img
	var sz: int = img.get_width()
	var mh: float = maxf(Terrain.params.max_height, 0.001)

	var center_px: Vector2 = TerrainBrush.world_to_pixel(c, ws, sz)
	var radius_px: float = TerrainBrush.world_radius_to_pixel(brush_radius, ws, sz)
	var dh: float = brush_strength * delta / mh   # 世界米/秒 → 原始域

	var rect: Rect2i = TerrainBrush.apply(img, center_px, radius_px, dh, mode, _flatten_target)
	if rect.size.x > 0:
		undo_stack.mark(rect)
		Terrain.heightmap_tex.update(img)
		_dirty = true

## 笔刷这一次笔画作用在哪张图上（起笔时锁定，见 _begin_stroke）
var _stroke_layer: int = -1
## 这一次笔画用的变种（起笔时锁定；-1 = 自动；只有石板路/草地两类层非 -1）
var _stroke_variant: int = -1

## 道路层（石板/土路）：笔画会同时写 splat2 路芯与 splat1 泥土路肩
func _is_road_layer(l: int) -> bool:
	return l == SplatBrush.Layer.PAVED or l == SplatBrush.Layer.ROAD

## 一条撤销记录入栈后统一记账：刷新操作顺序日志 + 作废所有重做
func _commit_kind(kind: String) -> void:
	_undo_kind.append(kind)
	_redo_kind.clear()
	# 两个栈的重做链都要清：UndoStack.end() 只清自己的，
	# 另一张图的重做记录留着会出现"Ctrl+Y 把很久以前的拼图改动翻出来"。
	undo_stack.clear_redo()
	splat_undo.clear_redo()
	splat2_undo.clear_redo()

## 群系图（biome）依赖高度，改完地形要让群系跟着重算，否则林线/岸边还是旧的
func _refresh_neighbors() -> void:
	Terrain._refresh_biome_from_height()

# ---------------------------------------------------------------- 撤销 / 重做

func _undo() -> void:
	if _undo_kind.is_empty():
		_toast("没有可撤销的操作")
		return
	var kind: String = str(_undo_kind.pop_back())
	var ok: bool = false
	if kind == KIND_ROAD:
		# 道路笔画 = 两张图各一条记录，成对撤销/重做（哪边没改 end() 就没入栈，返回 false 无妨）
		var ok1: bool = splat2_undo.undo(Terrain.splat2_img)
		var ok2: bool = splat_undo.undo(Terrain.splat_img)
		ok = ok1 or ok2
		if ok:
			Terrain.refresh_splat_texture()
			Terrain.refresh_splat2_texture()
	elif kind == KIND_SPLAT2:
		ok = splat2_undo.undo(Terrain.splat2_img)
		if ok:
			Terrain.refresh_splat2_texture()
	elif kind == KIND_SPLAT:
		ok = splat_undo.undo(Terrain.splat_img)
		if ok:
			Terrain.refresh_splat_texture()
	else:
		ok = undo_stack.undo(Terrain.heightmap_img)
		if ok:
			Terrain.heightmap_tex.update(Terrain.heightmap_img)
			Terrain._refresh_biome_from_height()
	if not ok:
		_toast("撤销失败")
		return
	_redo_kind.append(kind)
	_dirty = true
	_update_undo_ui()
	_toast("已撤销%s（剩 %d 步）" % [_kind_label(kind), _total_undo()])

func _redo() -> void:
	if _redo_kind.is_empty():
		_toast("没有可重做的操作")
		return
	var kind: String = str(_redo_kind.pop_back())
	var ok: bool = false
	if kind == KIND_ROAD:
		var ok1: bool = splat2_undo.redo(Terrain.splat2_img)
		var ok2: bool = splat_undo.redo(Terrain.splat_img)
		ok = ok1 or ok2
		if ok:
			Terrain.refresh_splat_texture()
			Terrain.refresh_splat2_texture()
	elif kind == KIND_SPLAT2:
		ok = splat2_undo.redo(Terrain.splat2_img)
		if ok:
			Terrain.refresh_splat2_texture()
	elif kind == KIND_SPLAT:
		ok = splat_undo.redo(Terrain.splat_img)
		if ok:
			Terrain.refresh_splat_texture()
	else:
		ok = undo_stack.redo(Terrain.heightmap_img)
		if ok:
			Terrain.heightmap_tex.update(Terrain.heightmap_img)
			Terrain._refresh_biome_from_height()
	if not ok:
		_toast("重做失败")
		return
	_undo_kind.append(kind)
	_dirty = true
	_update_undo_ui()
	_toast("已重做%s（剩 %d 步）" % [_kind_label(kind), _total_redo()])

## 撤销/重做提示里对操作类型的称呼
func _kind_label(kind: String) -> String:
	match kind:
		KIND_SPLAT: return "拼图"
		KIND_SPLAT2: return "道路"
		KIND_ROAD: return "道路（含路肩）"
		_: return "地形"

func _total_undo() -> int:
	return _undo_kind.size()

func _total_redo() -> int:
	return _redo_kind.size()

func _update_undo_ui() -> void:
	if _ui != null:
		_ui.set_undo_state(_total_undo() > 0, _total_redo() > 0, _total_undo())

# ---------------------------------------------------------------- 文档

## 新建一份空文档（地形图沿用 Terrain 里现有的那张）
func _new_doc() -> void:
	doc = MapDoc.new()
	doc.map_name = "自定义地图"
	doc.created = Time.get_datetime_string_from_system(false, true)
	_sync_doc_from_terrain()
	_dirty = false

## 把 Terrain 的当前状态（图尺寸 + 28 个地形参数 + 网格尺寸）同步进 doc。
## 存盘前必调 —— 否则地形改了、doc 里还是旧参数，读档时高度和水面对不上。
func _sync_doc_from_terrain() -> void:
	if doc == null or Terrain.params == null:
		return
	doc.capture_terrain_from(Terrain.params)
	if doc.cell_size > 0.0:
		doc.grid_n = int(round(Terrain.params.world_size / doc.cell_size))
	if Terrain.heightmap_img != null:
		doc.heightmap_size = Terrain.heightmap_img.get_width()
	if Terrain.biome_img != null:
		doc.biome_size = Terrain.biome_img.get_width()

func _refresh_doc_label() -> void:
	if _ui == null or doc == null:
		return
	_ui.set_doc_text("%d×%d 格 · %.0f m · %d 个对象%s" % [
		doc.grid_n, doc.grid_n, doc.world_size(), doc.objects.size(),
		"  ●未保存" if _dirty else ""])

# ---------------------------------------------------------------- 存盘 / 试玩

func _save_map(map_name: String) -> void:
	if doc == null:
		_new_doc()

	var nm: String = map_name.strip_edges()
	if nm == "" and _ui != null and _ui.name_edit != null:
		nm = _ui.name_edit.text.strip_edges()
	if nm == "":
		nm = "未命名地图"

	_sync_doc_from_terrain()
	doc.map_name = MapIO.sanitize_name(nm)

	# 图和元数据一起交给 MapIO —— 磁盘格式的全部知识都收在那一个文件里，
	# 编辑器不再自己拼 height.raw / map.json，避免两处各写一份、慢慢走样。
	var ok: bool = MapIO.save(doc, Terrain.heightmap_img, Terrain.biome_img, Terrain.splat_img, Terrain.splat2_img)
	if not ok:
		_toast("保存失败：无法写入 user://maps/%s/" % doc.map_name)
		return

	_dirty = false
	GameManager.set_meta("last_edited_map", doc.map_name)
	var extra: String = ""
	if doc.objects.size() > 0:
		extra = "，%d 个对象" % doc.objects.size()
	_toast("已保存 → user://maps/%s/%s" % [doc.map_name, extra])
	_refresh_doc_label()
	print("[MapEditor] 保存完成: ", ProjectSettings.globalize_path(MapIO.MAP_ROOT + doc.map_name + "/"))

func _save_and_play() -> void:
	if doc == null:
		_new_doc()
	var nm: String = doc.map_name
	if _ui != null and _ui.name_edit != null and _ui.name_edit.text.strip_edges() != "":
		nm = _ui.name_edit.text.strip_edges()
	_save_map(nm)
	if not MapIO.exists(doc.map_name):
		_toast("试玩中止：地图没存成功")
		return
	GameManager.game_settings_override = {
		"map_mode": "custom",
		"map_saved_name": doc.map_name,
	}
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

# ---------------------------------------------------------------- UI 入口

func _build_ui() -> void:
	_ui = EditorUI.new(self)
	_ui.build(self)

	# 右侧栏：调色板（常驻）+ 检查器（有选中对象才出现）
	palette = PalettePanel.new(self)
	palette.build(_ui.right_host)

	inspector = InspectorPanel.new(self)
	inspector.build(_ui.right_host)

	# 导入窗口按需构建（第一次拖图进来才实例化，省一次启动开销）
	import_dialog = AssetImportDialog.new(self)
	entity_dialog = EntityImportDialog.new(self)

func _set_mode(m: int) -> void:
	mode = m
	if _ui != null:
		_ui.set_mode_text(m)

## 切换笔刷作用层（-1 = 高度，0~3 = 拼图层，4/5 = 道路，6 = 草地），UI 同步
func _set_paint_layer(layer: int) -> void:
	paint_layer = layer
	_stroke_layer = layer     # 防御：没在拖动时切层，笔画层也要跟上
	if _ui != null:
		_ui.set_paint_layer(layer)

## 切换变种（-1 = 自动噪声分带，0~4 = 手选草种/石板种），UI 同步
func _set_paint_variant(v: int) -> void:
	paint_variant = v
	if _ui != null:
		_ui.set_paint_variant(v)

## ---------------------------------------------------------------- 工具模式

## 切模式。离开放置模式时必须把 ghost 收起来，否则它会一直挂在地图上。
func set_tool_mode(m: int) -> void:
	if tool_mode == Tool.PLACE and m != Tool.PLACE and obj_layer != null:
		obj_layer.placing_kind = ""
		obj_layer.placing_id = ""
		if obj_layer.ghost != null:
			obj_layer.ghost.hide_ghost()
	tool_mode = m
	if palette != null:
		palette.sync_mode(m, Tool.SELECT)
	if m == Tool.TERRAIN and _ui != null:
		_ui.set_mode_text(mode)

# ---------------------------------------------------------------- 对象层对外接口
# ObjectLayer / PalettePanel / InspectorPanel 通过这些方法反过来找 MapEditor，
# 不让它们直接改 editor 内部状态，改起来才有迹可循。

func begin_placement(kind: String, id: String) -> void:
	if obj_layer != null:
		obj_layer.begin_placement(kind, id)

func cancel_placement() -> void:
	if obj_layer != null:
		obj_layer.cancel_placement()

func delete_selected() -> void:
	var idx: int = inspector.current_index() if inspector != null else -1
	if idx < 0:
		_toast("没有选中对象")
		return
	if obj_layer.delete(idx):
		clear_selection()
		_refresh_doc_label()
		_toast("已删除")

func change_selected_owner(fid: String) -> void:
	var idx: int = inspector.current_index() if inspector != null else -1
	if idx < 0:
		return
	obj_layer.change_owner(idx, fid)
	_refresh_doc_label()
	_toast("归属改为 %s" % fid)

func change_selected_amount(v: int) -> void:
	var idx: int = inspector.current_index() if inspector != null else -1
	if idx < 0:
		return
	obj_layer.change_amount(idx, v)
	_refresh_doc_label()

func set_selection(idx: int) -> void:
	var obj: Dictionary = doc.get_object(idx) if doc != null else {}
	if obj.is_empty():
		clear_selection()
		return
	if inspector != null:
		inspector.show_object(idx, obj)

func clear_selection() -> void:
	if inspector != null:
		inspector.clear()

func mark_dirty() -> void:
	_dirty = true
	_refresh_doc_label()

## 公开的提示接口（对象层拿不到私有的 _toast）
func toast(msg: String) -> void:
	_toast(msg)

func _toast(msg: String) -> void:
	if _ui != null:
		_ui.show_toast(msg)
	print("[MapEditor] ", msg)
