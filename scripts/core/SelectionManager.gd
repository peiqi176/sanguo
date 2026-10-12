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

func _ready() -> void:
	_create_selection_box()

func _create_selection_box() -> void:
	_selection_box = ColorRect.new()
	_selection_box.color = Color(0.2, 0.8, 0.2, 0.15)
	_selection_box.visible = false
	get_tree().root.add_child.call_deferred(_selection_box)

func _unhandled_input(event: InputEvent) -> void:
	# 左键按下开始框选
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _is_click_on_ui(event.position):
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
		var dist: float = unit.global_position.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best = unit
	if best:
		select_unit(best)
	else:
		# 检查建筑
		for b in GameManager.all_buildings:
			if b.global_position.distance_to(world_pos) < 2.0:
				select_building(b)
				return
		clear_selection()

func _box_select(start: Vector2, end: Vector2) -> void:
	var min_x: float = min(start.x, end.x)
	var max_x: float = max(start.x, end.x)
	var min_y: float = min(start.y, end.y)
	var max_y: float = max(start.y, end.y)
	
	clear_selection()
	var camera: Camera3D = get_viewport().get_camera_3d()
	for unit in GameManager.all_units:
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

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.INF
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	# 与 Y=0 平面相交
	if abs(dir.y) < 0.001:
		return Vector3.INF
	var t: float = -from.y / dir.y
	if t < 0:
		return Vector3.INF
	return from + dir * t

func _is_click_on_ui(screen_pos: Vector2) -> bool:
	# 简化：检查点击是否在 Control 节点上
	var control: Control = get_tree().root.gui_get_control_at(screen_pos)
	return control != null and control.is_inside_tree()

func issue_command(target_pos: Vector3, target_entity = null) -> void:
	if selected_units.size() == 0:
		return
	for unit in selected_units:
		if target_entity:
			if target_entity.get_faction() != GameManager.player_faction:
				unit.command_attack(target_entity)
			else:
				unit.command_move(target_pos)
		else:
			unit.command_move(target_pos)

func get_selected_units() -> Array:
	return selected_units





