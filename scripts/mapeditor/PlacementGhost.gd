extends Node3D
## PlacementGhost —— 放置预览（半透明体块 + footprint 逐格染色 + 贴图虚影）
##
## 要求：必须和最终落地的东西**在同一个位置、同一个占地范围**。
## 判断依据只认 GridManager 的占位表 —— 不做"看起来没压着"这种目测逻辑，
## 否则会出现"预览是绿的、点下去放不下"。
##
## 为什么 footprint 要逐格画而不是一个大方块：
##   3×3 的官府压住一格石头时，整块变红没法知道是哪一格有问题。
##   逐格画能一眼看出冲突在哪。

const OK_FILL: Color = Color(0.30, 1.00, 0.45, 0.28)
const SpriteProjector = preload("res://scripts/core/SpriteProjector.gd")
const OK_EDGE: Color = Color(0.30, 1.00, 0.45, 0.95)
const BAD_FILL: Color = Color(1.00, 0.30, 0.25, 0.34)
const BAD_EDGE: Color = Color(1.00, 0.30, 0.25, 0.95)

var footprint: Vector2i = Vector2i(1, 1)
var cell_size: float = 2.0
var valid: bool = true

var _cells: MeshInstance3D = null      # footprint 格面
var _edges: MeshInstance3D = null      # footprint 格线
var _body: MeshInstance3D = null       # 体块（表示高度感）
var _sprite: Sprite3D = null           # 贴图虚影

var _last_cell: Vector2i = Vector2i(-99999, -99999)
var _last_valid: bool = true
var _drawn: bool = false

# ---------------------------------------------------------------- 构建

func setup(id: String, kind: String, cs: float) -> void:
	cell_size = maxf(cs, 0.1)
	footprint = Vector2i(1, 1)

	if kind == "building":
		var bdef: Dictionary = DataLoader.get_building_def(id)
		if not bdef.is_empty():
			var s = bdef.get("size", [2, 2])
			if typeof(s) == TYPE_ARRAY and (s as Array).size() >= 2:
				footprint = Vector2i(maxi(int(s[0]), 1), maxi(int(s[1]), 1))

	_ensure_nodes()
	_rebuild_body()
	_load_sprite(id, kind)
	_drawn = false
	_last_cell = Vector2i(-99999, -99999)

func _ensure_nodes() -> void:
	if _cells == null:
		_cells = MeshInstance3D.new()
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = false
		_cells.material_override = m
		_cells.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_cells)

	if _edges == null:
		_edges = MeshInstance3D.new()
		var m2: StandardMaterial3D = StandardMaterial3D.new()
		m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m2.vertex_color_use_as_albedo = true
		m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_edges.material_override = m2
		_edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_edges)

	if _body == null:
		_body = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		_body.mesh = bm
		var m3: StandardMaterial3D = StandardMaterial3D.new()
		m3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m3.albedo_color = Color(0.4, 0.9, 1.0, 0.12)
		_body.material_override = m3
		_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_body)

func _rebuild_body() -> void:
	if _body == null:
		return
	var bm: BoxMesh = _body.mesh
	var w: float = float(footprint.x) * cell_size
	var d: float = float(footprint.y) * cell_size
	# 高度给一个跟占地挂钩的视觉值，只为了"看着像那么高的东西"
	var h: float = clampf(maxf(w, d) * 0.6, 1.5, 6.0)
	bm.size = Vector3(w * 0.94, h, d * 0.94)
	# 体块要落在 footprint 的几何中心，所以相对 origin 偏移半格(占地-1)
	_body.position = Vector3(
		float(footprint.x - 1) * cell_size * 0.5,
		h * 0.5,
		float(footprint.y - 1) * cell_size * 0.5)

func _load_sprite(id: String, kind: String) -> void:
	if _sprite != null:
		_sprite.queue_free()
		_sprite = null
	var cat: String = ""
	match kind:
		"building": cat = "buildings"
		"unit": cat = "units"
		"resource": cat = "resources"
		"village": cat = "villages"
		"horse": cat = "horses"
		_: return
	if cat == "":
		return
	var tex: Texture2D = DataLoader.get_sprite_texture(cat, id)
	if tex == null:
		return
	_sprite = Sprite3D.new()
	_sprite.texture = tex
	# 虚影必须与真实落位同一套投影（垂直于相机视线 + 底边补偿），
	# 否则"预览时觉得位置合适、落下后房子歪了"——所见即所得是编辑器的底线。
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.pixel_size = DataLoader.get_sprite_pixel_size(cat, tex)
	_sprite.modulate = Color(1, 1, 1, 0.55)
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var base: Vector3 = Vector3(
		float(footprint.x - 1) * cell_size * 0.5,
		0.0,
		float(footprint.y - 1) * cell_size * 0.5)
	var s_scale: float = 1.0
	var adef: Dictionary = DataLoader.get_asset_def(cat, id)
	if not adef.is_empty():
		s_scale = float(adef.get("scale", 1.0))
	# 尺寸也要跟真实落位一致：原来虚影固定 scale=1，建筑实际是 1.5~2.0，
	# 玩家看到的预览比落成后小一圈，摆放判断全靠脑补。
	_sprite.scale = Vector3(s_scale, s_scale, s_scale)
	var hb: float = DataLoader.get_sprite_anchor_y(cat, id, s_scale)
	SpriteProjector.align(_sprite, hb, base)
	add_child(_sprite)

# ---------------------------------------------------------------- 移动 / 状态

## gp 是 footprint 左上角的格坐标（和 doc.objects.grid 同一语义）
func move_to(gp: Vector2i, grid) -> void:
	if grid == null:
		return
	var wp: Vector3 = grid.grid_to_world(gp)
	global_position = Vector3(wp.x, wp.y, wp.z)
	if gp != _last_cell:
		_last_cell = gp
		_redraw()

func set_valid(ok: bool) -> void:
	valid = ok
	if ok != _last_valid or not _drawn:
		_last_valid = ok
		_redraw()

func show_ghost() -> void:
	visible = true
	for c in get_children():
		if c is Node3D:
			(c as Node3D).visible = true

func hide_ghost() -> void:
	visible = false
	_last_cell = Vector2i(-99999, -99999)

# ---------------------------------------------------------------- 绘制

func _redraw() -> void:
	_drawn = true
	var fill: Color = OK_FILL if valid else BAD_FILL
	var edge: Color = OK_EDGE if valid else BAD_EDGE
	var cs: float = cell_size
	var half: float = cs * 0.5

	# 面片：每格一个 quad，四角贴合地形高度
	var im: ImmediateMesh = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(fill)
	for dx in range(footprint.x):
		for dz in range(footprint.y):
			var x0: float = -half + float(dx) * cs
			var x1: float = x0 + cs
			var z0: float = -half + float(dz) * cs
			var z1: float = z0 + cs
			var y00: float = _h(x0, z0) - global_position.y + 0.08
			var y10: float = _h(x1, z0) - global_position.y + 0.08
			var y11: float = _h(x1, z1) - global_position.y + 0.08
			var y01: float = _h(x0, z1) - global_position.y + 0.08
			_quad(im, Vector3(x0, y00, z0), Vector3(x1, y10, z0),
					Vector3(x1, y11, z1), Vector3(x0, y01, z1))
	im.surface_end()
	_cells.mesh = im

	# 格线：只画外框，省顶点也够看
	var im2: ImmediateMesh = ImmediateMesh.new()
	im2.surface_begin(Mesh.PRIMITIVE_LINES)
	im2.surface_set_color(edge)
	var ex0: float = -half
	var ex1: float = -half + float(footprint.x) * cs
	var ez0: float = -half
	var ez1: float = -half + float(footprint.y) * cs
	_line(im2, ex0, ez0, ex1, ez0)
	_line(im2, ex1, ez0, ex1, ez1)
	_line(im2, ex1, ez1, ex0, ez1)
	_line(im2, ex0, ez1, ex0, ez0)
	im2.surface_end()
	_edges.mesh = im2

	if _body != null:
		var m: StandardMaterial3D = _body.material_override
		if m != null:
			m.albedo_color = Color(0.4, 0.9, 1.0, 0.12) if valid else Color(1.0, 0.3, 0.25, 0.14)

func _h(local_x: float, local_z: float) -> float:
	return Terrain.get_height(global_position.x + local_x, global_position.z + local_z)

func _quad(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_add_vertex(c)
	im.surface_add_vertex(a)
	im.surface_add_vertex(c)
	im.surface_add_vertex(d)

func _line(im: ImmediateMesh, x0: float, z0: float, x1: float, z1: float) -> void:
	var y0: float = _h(x0, z0) - global_position.y + 0.12
	var y1: float = _h(x1, z1) - global_position.y + 0.12
	im.surface_add_vertex(Vector3(x0, y0, z0))
	im.surface_add_vertex(Vector3(x1, y1, z1))
