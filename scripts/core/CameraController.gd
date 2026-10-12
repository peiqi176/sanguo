extends Node3D
## CameraController — RTS 相机控制
## 支持 WASD 平移、Q/E 旋转、滚轮缩放、右键拖动、边缘滚动

@export var move_speed: float = 20.0
@export var rotate_speed: float = 1.5
@export var zoom_speed: float = 15.0
@export var min_height: float = 5.0
@export var max_height: float = 50.0
@export var edge_scroll: bool = true
@export var edge_margin: float = 20.0

var _camera: Camera3D
var _rotation_y: float = 0.0
var _pitch: float = 0.785  # 45度俯角
var _distance: float = 18.0
var _target: Vector3 = Vector3(20, 0, 20)
var _is_dragging: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	_camera = $Camera3D
	_camera.current = true
	_update_camera()

func _process(delta: float) -> void:
	var move_dir: Vector3 = Vector3.ZERO
	
	# WASD 平移
	if Input.is_action_pressed("camera_up"):
		move_dir.z -= 1
	if Input.is_action_pressed("camera_down"):
		move_dir.z += 1
	if Input.is_action_pressed("camera_left"):
		move_dir.x -= 1
	if Input.is_action_pressed("camera_right"):
		move_dir.x += 1
	
	# 边缘滚动
	if edge_scroll and not _is_dragging:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		if mouse_pos.x < edge_margin:
			move_dir.x -= 1
		elif mouse_pos.x > viewport_size.x - edge_margin:
			move_dir.x += 1
		if mouse_pos.y < edge_margin:
			move_dir.z -= 1
		elif mouse_pos.y > viewport_size.y - edge_margin:
			move_dir.z += 1
	
	if move_dir.length() > 0:
		move_dir = move_dir.normalized()
		# 根据相机旋转调整方向
		var forward: Vector3 = Vector3(-sin(_rotation_y), 0, -cos(_rotation_y))
		var right: Vector3 = Vector3(cos(_rotation_y), 0, -sin(_rotation_y))
		var world_move: Vector3 = (forward * move_dir.z + right * move_dir.x) * move_speed * delta
		_target += world_move
	
	# 旋转
	if Input.is_action_pressed("camera_rotate_left"):
		_rotation_y += rotate_speed * delta
	if Input.is_action_pressed("camera_rotate_right"):
		_rotation_y -= rotate_speed * delta
	
	_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	# 滚轮缩放
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_distance = clampf(_distance - zoom_speed * event.factor, min_height, max_height)
		_update_camera()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_distance = clampf(_distance + zoom_speed * event.factor, min_height, max_height)
		_update_camera()
	
	# 右键拖动旋转
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_is_dragging = event.pressed
		_last_mouse_pos = event.position
	elif event is InputEventMouseMotion and _is_dragging:
		var delta: Vector2 = event.position - _last_mouse_pos
		_rotation_y -= delta.x * 0.005
		_pitch = clampf(_pitch - delta.y * 0.005, 0.2, 1.4)
		_last_mouse_pos = event.position
		_update_camera()

func _update_camera() -> void:
	var offset: Vector3 = Vector3(
		sin(_rotation_y) * cos(_pitch),
		sin(_pitch),
		cos(_rotation_y) * cos(_pitch)
	) * _distance
	_camera.global_position = _target + offset
	_camera.look_at(_target, Vector3.UP)

func focus_on(pos: Vector3) -> void:
	_target = pos
	_update_camera()

