extends Node
## FogOfWar — 双层战争迷雾（P1-11）
##   ① 记忆层 explored：一旦探索过永久保留 → 地形/建筑/村庄可见（学 AoE4 的"地图记忆"）
##   ② 视野层 visible：每 0.35s 由本方单位/建筑的视野重算 → 只有这一层能看到敌军行动
##   树木内的敌军即使在本方视野内也隐形（树林伏兵，见 Unit.gd 伏兵逻辑）
## 渲染：地形 shader 采样 fog_mask（R=探索 G=视野），未探索接近全黑、探索过压暗

const RES: int = 160            # 迷雾贴图分辨率（160×160，覆盖整个地图）
const CELL_CHECK: float = 0.35  # 重算间隔（秒）

var enabled: bool = true

var _ws: float = 200.0          # 地图边长（米），由 Terrain.WORLD_SIZE 同步
var _explored: PackedByteArray = PackedByteArray()
var _visible: PackedByteArray = PackedByteArray()
var _img: Image = null
var _tex: ImageTexture = null
var _bytes: PackedByteArray = PackedByteArray()
var _timer: float = 0.0
var _terrain_mat: ShaderMaterial = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Terrain != null:
		_ws = float(Terrain.WORLD_SIZE)
	_reset()

func _reset() -> void:
	var n: int = RES * RES
	_explored = PackedByteArray()
	_explored.resize(n)
	_visible = PackedByteArray()
	_visible.resize(n)
	_explored.fill(0)
	_visible.fill(0)
	_bytes = PackedByteArray()
	_bytes.resize(n * 4)
	_bytes.fill(0)  # R=0 G=0 → 未探索（shader 侧全黑）
	_img = Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, _bytes)
	_tex = ImageTexture.create_from_image(_img)
	# 完全未探索时 alpha 也要写 255，否则 shader 采样可能拿到全 0 → 但 R/G 已足够
	for i in n:
		_bytes[i * 4 + 3] = 255
	_img = Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, _bytes)
	_tex.update(_img)

## 由 Main 在创建地形材质后调用，把迷雾贴图挂到 shader
func register_terrain_material(mat: ShaderMaterial) -> void:
	_terrain_mat = mat
	if _terrain_mat != null:
		_terrain_mat.set_shader_parameter("fog_mask", _tex)

func get_mask_texture() -> ImageTexture:
	return _tex

# ============================ 存档 ============================

## 导出探索进度（base64 压缩成字符串，贴在存档 JSON 里）
func export_state() -> Dictionary:
	return {
		"res": RES,
		"ws": _ws,
		"explored": Marshalls.raw_to_base64(_explored)
	}

## 读档恢复探索进度：只恢复记忆层，视野层由 update_visibility() 重新算
func import_state(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	var b64: String = str(d.get("explored", ""))
	if b64 == "":
		return
	var raw: PackedByteArray = Marshalls.base64_to_raw(b64)
	if raw.size() != RES * RES:
		print("[Fog] ⚠ 存档迷雾尺寸不匹配 (%d != %d)，忽略" % [raw.size(), RES * RES])
		return
	if absf(float(d.get("ws", _ws)) - _ws) > 1.0:
		print("[Fog] ⚠ 存档地图尺寸不同，放弃恢复迷雾")
		return
	_explored = raw
	_refresh_texture()
	update_visibility()

# ============================ 坐标换算 ============================

func _to_cell(x: float, z: float) -> Vector2i:
	# ⚠ 必须与地形 shader 的采样一致：u = x/ws, v = 1 - z/ws
	# （地形图像第 0 行对应 z = ws 一侧，写反会导致迷雾上下颠倒）
	var u: float = clampf(x / _ws, 0.0, 1.0)
	var v: float = clampf(1.0 - z / _ws, 0.0, 1.0)
	return Vector2i(
		clampi(int(u * float(RES)), 0, RES - 1),
		clampi(int(v * float(RES)), 0, RES - 1)
	)

# ============================ 查询 ============================

func is_visible(pos: Vector3) -> bool:
	if not enabled:
		return true
	var c: Vector2i = _to_cell(pos.x, pos.z)
	return _visible[c.y * RES + c.x] != 0

func is_explored(pos: Vector3) -> bool:
	if not enabled:
		return true
	var c: Vector2i = _to_cell(pos.x, pos.z)
	return _explored[c.y * RES + c.x] != 0

# ============================ 揭示 ============================

## 永久揭示一块区域（武将技能"探明黑雾村庄"等）
func reveal(pos: Vector3, radius: float) -> void:
	_stamp(pos, radius, true, false)
	_refresh_texture()

## 兼容 General.gd 的探明村庄技能
func reveal_fog_village(_faction: String, pos: Vector3, radius: float) -> void:
	reveal(pos, radius)

func _stamp(pos: Vector3, radius: float, explored: bool, visible: bool) -> void:
	var cell_m: float = _ws / float(RES)
	var c: Vector2i = _to_cell(pos.x, pos.z)
	var r: int = int(ceil(radius / cell_m))
	var r2: int = r * r
	for dy in range(-r, r + 1):
		var cy: int = c.y + dy
		if cy < 0 or cy >= RES:
			continue
		for dx in range(-r, r + 1):
			var cx: int = c.x + dx
			if cx < 0 or cx >= RES:
				continue
			if dx * dx + dy * dy > r2:
				continue
			var idx: int = cy * RES + cx
			if explored:
				_explored[idx] = 1
			if visible:
				_visible[idx] = 1

# ============================ 每帧更新 ============================

func _process(delta: float) -> void:
	# 主菜单/编辑器等没有对局的状态下不刷
	if GameManager == null or GameManager.game_over:
		return
	# 开关同步：设置里关掉迷雾时恢复所有实体可见
	var want: bool = bool(GameManager.fog_of_war_enabled)
	if want != enabled:
		enabled = want
		if _terrain_mat != null:
			_terrain_mat.set_shader_parameter("fog_enabled", 1.0 if enabled else 0.0)
		if not enabled:
			for u in GameManager.all_units:
				if is_instance_valid(u):
					u.visible = true
			for b in GameManager.all_buildings:
				if is_instance_valid(b):
					b.visible = true
			for v in GameManager.villages:
				if is_instance_valid(v):
					v.visible = true
	if not enabled:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CELL_CHECK
	update_visibility()

func update_visibility() -> void:
	var pf: String = GameManager.player_faction
	_visible.fill(0)
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u.get_faction() != pf:
			continue
		if "hp" in u and float(u.hp) <= 0.0:
			continue
		var r: float = 10.0
		if u.has_method("get_vision_range"):
			r = u.get_vision_range()
		_stamp(u.global_position, r, true, true)
	for b in GameManager.all_buildings:
		if not is_instance_valid(b):
			continue
		if b.faction != pf:
			continue
		_stamp(b.global_position, float(b.def.get("vision_range", 8.0)), true, true)
	for v in GameManager.villages:
		if not is_instance_valid(v):
			continue
		if v.village_owner != pf:
			continue
		_stamp(v.global_position, 9.0, true, true)
	_refresh_texture()
	_apply_entity_visibility(pf)

func _refresh_texture() -> void:
	var n: int = RES * RES
	for i in n:
		var base: int = i * 4
		_bytes[base] = 255 if _explored[i] != 0 else 0
		_bytes[base + 1] = 255 if _visible[i] != 0 else 0
		_bytes[base + 2] = 0
		_bytes[base + 3] = 255
	_img = Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, _bytes)
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)
	if _terrain_mat != null:
		_terrain_mat.set_shader_parameter("fog_mask", _tex)

## 敌军单位：只在"当前视野内 且 不在树林内"时可见
## 中立/敌方建筑与村庄：探索过就永久可见（地图记忆）
func _apply_entity_visibility(pf: String) -> void:
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u.get_faction() == pf:
			continue
		var seen: bool = is_visible(u.global_position)
		if seen and u.has_method("is_hidden_in_forest") and u.is_hidden_in_forest():
			seen = false
		u.visible = seen
	for b in GameManager.all_buildings:
		if not is_instance_valid(b):
			continue
		if b.faction == pf:
			continue
		b.visible = is_explored(b.global_position)
	for v in GameManager.villages:
		if not is_instance_valid(v):
			continue
		if v.village_owner == pf:
			continue
		v.visible = is_explored(v.global_position)
	# 野外资源点（矿洞/树木/野马）：探索过才显示
	for r in GameManager.resource_nodes:
		if not is_instance_valid(r):
			continue
		r.visible = is_explored(r.global_position)
