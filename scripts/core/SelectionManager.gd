extends Node
class_name SelectionManager
## SelectionManager — 单位选择与框选
## 左键点选/框选，右键下达指令

var selected_units: Array = []
var selected_building: Node = null
var _is_box_selecting: bool = false
var _box_start: Vector2 = Vector2.ZERO
var _box_end: Vector2 = Vector2.ZERO
var _selection_box: ColorRect = null
var control_groups: Array = []  # 10个编队 (0-9)
var _last_group_key: int = -1
var _last_group_time: float = 0.0
# 🖱 双击选同屏同类
var _last_click_time: float = 0.0
var _last_click_pos: Vector2 = Vector2.ZERO
var _last_click_unit: Node = null

func _ready() -> void:
	_create_selection_box()
	for i in range(10):
		control_groups.append([])

func _create_selection_box() -> void:
	_selection_box = ColorRect.new()
	_selection_box.color = Color(0.2, 0.8, 0.2, 0.15)
	_selection_box.visible = false
	get_tree().root.add_child.call_deferred(_selection_box)

func _unhandled_input(event: InputEvent) -> void:
	# 左键按下开始框选（_unhandled_input 自动过滤 UI 点击）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_box_start = event.position
		_box_end = event.position
		_is_box_selecting = true
		_selection_box.visible = true
		_update_selection_box()
	
	# 左键拖动更新框选框
	elif event is InputEventMouseMotion and _is_box_selecting:
		_box_end = event.position
		_update_selection_box()
	
	# 左键释放完成选择
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _is_box_selecting:
		_is_box_selecting = false
		_selection_box.visible = false
		var box_size: Vector2 = (_box_end - _box_start).abs()
		if box_size.x < 5 and box_size.y < 5:
			# 单击选择
			_click_select(_box_start)
		else:
			# 框选
			_box_select(_box_start, _box_end)

func _update_selection_box() -> void:
	var pos: Vector2 = Vector2(min(_box_start.x, _box_end.x), min(_box_start.y, _box_end.y))
	var size: Vector2 = (_box_end - _box_start).abs()
	_selection_box.position = pos
	_selection_box.size = size

func _click_select(screen_pos: Vector2) -> void:
	var world_pos: Vector3 = _screen_to_world(screen_pos)
	if world_pos == Vector3.INF:
		clear_selection()
		return
	# 查找最近的可选中实体
	var best: Node = null
	var best_dist: float = 2.0
	for unit in GameManager.all_units:
		if not is_instance_valid(unit):
			continue
		# 船只载员视觉隐藏，不应被点选（建筑驻军仍可见，保留点选以便放出）
		if unit.get("on_board") == true:
			continue
		var dist: float = unit.global_position.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best = unit
	if best:
		# 🖱 双击同一兵种 → 选中屏幕内全部同类（帝国时代式）
		var now: float = Time.get_ticks_msec() / 1000.0
		# 辎重车（SupplyCart）没有 unit_id 字段，不参与"同类双击"
		var is_double: bool = _last_click_unit != null and is_instance_valid(_last_click_unit) \
			and ("unit_id" in best) and ("unit_id" in _last_click_unit) \
			and best.unit_id == _last_click_unit.unit_id \
			and (now - _last_click_time) < 0.35 \
			and screen_pos.distance_to(_last_click_pos) < 12.0
		if is_double:
			_last_click_unit = null
			_select_same_type_on_screen(best)
			return
		_last_click_time = now
		_last_click_pos = screen_pos
		_last_click_unit = best
		select_unit(best)
	else:
		# 检查建筑
		for b in GameManager.all_buildings:
			if b.global_position.distance_to(world_pos) < 2.0:
				select_building(b)
				return
		clear_selection()

## 选中屏幕内与 ref 同兵种的全部本方单位
func _select_same_type_on_screen(ref) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(ref):
		select_unit(ref)
		return
	if ref.get_faction() != GameManager.player_faction:
		select_unit(ref)
		return
	var vp: Rect2 = get_viewport().get_visible_rect()
	clear_selection()
	for u in GameManager.all_units:
		if not is_instance_valid(u):
			continue
		if u.get_faction() != GameManager.player_faction:
			continue
		if u.get("on_board") == true:
			continue
		if u.unit_id != ref.unit_id:
			continue
		if camera.is_position_behind(u.global_position):
			continue
		if not vp.has_point(camera.unproject_position(u.global_position)):
			continue
		selected_units.append(u)
		u.set_selected(true)
	if selected_units.is_empty():
		selected_units.append(ref)
		ref.set_selected(true)
	EventBus.units_selected.emit(selected_units)

func _box_select(start: Vector2, end: Vector2) -> void:
	var min_x: float = min(start.x, end.x)
	var max_x: float = max(start.x, end.x)
	var min_y: float = min(start.y, end.y)
	var max_y: float = max(start.y, end.y)
	
	clear_selection()
	var camera: Camera3D = get_viewport().get_camera_3d()
	for unit in GameManager.all_units:
		if unit.get("on_board") == true:
			continue
		var screen: Vector2 = camera.unproject_position(unit.global_position)
		if screen.x >= min_x and screen.x <= max_x and screen.y >= min_y and screen.y <= max_y:
			if unit.get_faction() == GameManager.player_faction:
				selected_units.append(unit)
				unit.set_selected(true)
	EventBus.units_selected.emit(selected_units)

func select_unit(unit) -> void:
	clear_selection()
	selected_units.append(unit)
	unit.set_selected(true)
	EventBus.unit_selected.emit(unit)

func select_building(building) -> void:
	clear_selection()
	selected_building = building
	building.set_selected(true)
	EventBus.building_selected.emit(building)

func clear_selection() -> void:
	for u in selected_units:
		if is_instance_valid(u):
			u.set_selected(false)
	selected_units.clear()
	if selected_building and is_instance_valid(selected_building):
		selected_building.set_selected(false)
	selected_building = null
	EventBus.building_deselected.emit()
	EventBus.unit_deselected.emit()

const TerrainPicker = preload("res://scripts/mapeditor/TerrainPicker.gd")

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	# ★ 必须打到**地形表面**，不能打 Y=0 平面。
	# 打 Y=0 时，点在 6 米高的山坡上，射线会在更远处才降到 0，
	# 于是单位跑到鼠标点击位置外侧十几米的地方 —— 这就是"点哪儿都不去对地方"的根源。
	var hit = TerrainPicker.world_from_screen(get_viewport(), screen_pos)
	if hit != null:
		return hit
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.INF
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.001:
		return Vector3.INF
	var t: float = -from.y / dir.y
	if t < 0:
		return Vector3.INF
	return from + dir * t

func issue_command(target_pos: Vector3, target_entity = null, queue: bool = false) -> void:
	if selected_units.size() == 0:
		return
	# 🧩 多单位移动 → 按阵型排位（重骑兵/武将站前排，弓兵后排）
	if target_entity == null and selected_units.size() > 1:
		var fid: String = ""
		for u in selected_units:
			if "current_formation" in u and str(u.current_formation) != "":
				fid = str(u.current_formation)
				break
		if fid == "":
			fid = "square"
		var slots: Array = compute_formation_slots(selected_units, target_pos, fid)
		for i in selected_units.size():
			selected_units[i].command_move(slots[i], queue)
		return
	for unit in selected_units:
		if target_entity:
			# 村庄等中立实体：get_faction 返回 ""（中立）视为可攻击
			if target_entity.has_method("get_faction") and target_entity.get_faction() != GameManager.player_faction:
				unit.command_attack(target_entity, queue)
			else:
				unit.command_move(target_pos, queue)
		else:
			unit.command_move(target_pos, queue)

const FORMATION_SPACING: float = 2.2

## 计算阵型落点：返回与 units 顺序一一对应的位置数组
## 排列规则（从前往后）：武将 → 重骑兵 → 轻骑兵 → 步兵 → 远程 → 器械 → 后勤
## 这样重骑兵带着轻骑兵冲枪兵时，重骑先吃第一排长枪
func compute_formation_slots(units: Array, center: Vector3, fid: String) -> Array:
	var n: int = units.size()
	var slots: Array = []
	slots.resize(n)
	# 按阵型rank排序（同 rank 保持选中顺序），得到"谁站前排"
	var order: Array = []
	for i in n:
		order.append(i)
	order.sort_custom(func(a, b):
		var ra: int = units[a].get_formation_rank() if units[a].has_method("get_formation_rank") else 5
		var rb: int = units[b].get_formation_rank() if units[b].has_method("get_formation_rank") else 5
		if ra == rb:
			return a < b
		return ra < rb)
	# 朝向：从队伍重心指向目标
	var centroid: Vector3 = Vector3.ZERO
	for u in units:
		centroid += u.global_position
	centroid /= float(n)
	var fwd: Vector3 = center - centroid
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, 1)
	fwd = fwd.normalized()
	var right: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	var sp: float = FORMATION_SPACING
	var cols: int = int(ceil(sqrt(float(n))))
	for k in n:
		var idx: int = order[k]
		var pos: Vector3 = center
		match fid:
			"line":
				# 横阵：一字排开，正面接敌
				pos = center + right * (float(k) - float(n - 1) * 0.5) * sp
			"circle":
				# 圆阵：外周环形，前后排按 rank 分布
				var radius: float = max(3.0, sp * float(n) / (2.0 * PI))
				var ang: float = TAU * float(k) / float(max(1, n))
				pos = center + right * sin(ang) * radius - fwd * cos(ang) * radius
			"echelon":
				# 雁行：斜线梯队
				var kk: float = float(k) - float(n - 1) * 0.5
				pos = center + right * kk * sp - fwd * kk * sp * 0.6
			"wedge":
				# 锋矢：第一人顶在箭尖，后面两人一组向后展开（重骑/武将占箭尖）
				var row: int = 0
				if k > 0:
					row = int(ceil(float(k) / 2.0))
				var side: float = 1.0 if k % 2 == 1 else -1.0
				var lateral: float = 0.0 if k == 0 else side * float(row) * sp * 0.75
				pos = center - fwd * float(row) * sp + right * lateral
			_:
				# square（方阵）：前排靠目标，后排依次后撤
				var col: int = k % cols
				var row2: int = int(k / cols)
				pos = center - fwd * float(row2) * sp + right * (float(col) - float(cols - 1) * 0.5) * sp
		slots[idx] = pos
	return slots

func get_selected_units() -> Array:
	return selected_units

func save_group(index: int, append: bool = false) -> void:
	"""保存当前选中单位到指定编队；append=true 时为追加（Shift+数字）"""
	if index < 0 or index > 9:
		return
	if append:
		for u in selected_units:
			if is_instance_valid(u) and not control_groups[index].has(u):
				control_groups[index].append(u)
		if selected_units.size() > 0:
			EventBus.float_text.emit("编队 " + str(index + 1) + " 追加（共 " + str(control_groups[index].size()) + "）",
				selected_units[0].global_position + Vector3(0, 3, 0), Color.CYAN)
		return
	control_groups[index] = selected_units.duplicate()
	if selected_units.size() > 0:
		EventBus.float_text.emit("编队 " + str(index + 1), selected_units[0].global_position + Vector3(0, 3, 0), Color.CYAN)

func select_group(index: int, double_tap: bool = false) -> void:
	"""选择指定编队，双击则居中视角"""
	if index < 0 or index > 9:
		return
	var group: Array = control_groups[index]
	if group.size() == 0:
		return
	var valid: Array = []
	for u in group:
		if is_instance_valid(u):
			valid.append(u)
	control_groups[index] = valid
	if valid.size() == 0:
		return
	clear_selection()
	selected_units = valid
	for u in valid:
		if is_instance_valid(u):
			u.set_selected(true)
	EventBus.units_selected.emit(selected_units)
	if double_tap and valid.size() > 0:
		var center: Vector3 = Vector3.ZERO
		for u in valid:
			center += u.global_position
		center /= valid.size()
		var cam: Node3D = get_tree().get_first_node_in_group("camera_controller")
		if cam and cam.has_method("focus_on"):
			cam.focus_on(center)
