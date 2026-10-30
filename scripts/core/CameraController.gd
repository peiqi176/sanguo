extends Node3D
## CameraController — RTS 相机控制
## 支持 WASD 平移、Q/E 旋转、滚轮缩放、右键拖动、边缘滚动

@export var move_speed: float = 20.0
@export var rotate_speed: float = 1.5
@export var zoom_speed: float = 6.0
## 相机距离档位：近 18m（看清一个兵）~ 远 110m（看全战场）
@export var min_height: float = 18.0
@export var max_height: float = 110.0
@export var edge_scroll: bool = true
@export var edge_margin: float = 20.0

## === 2.5D 标准视角（★ 全项目唯一约定，改这里就全改）===
## 建筑是 BILLBOARD_DISABLED 的单方向平面图，相机一转就看到"纸片侧棱"；
## 单位是 BILLBOARD_ENABLED 但贴图也是按固定俯角画的，俯角一变透视关系就错。
## 所以默认：俯角锁 45°、偏航锁 45°、窄 FOV（≈长焦，接近正交，边缘不拉伸）。
## 美术出图必须按「俯角 45°/偏航 45°」这一套锚点画，见 docs/美术锚点规范_v1.md。
const DEFAULT_PITCH_DEG: float = 45.0
const DEFAULT_YAW_DEG: float = 45.0

@export var yaw_locked: bool = true
@export var yaw_lock_deg: float = DEFAULT_YAW_DEG
## 锁定档位间隔；360 = 只有一档（单方向素材），90 = 四方向素材
@export var yaw_lock_step: float = 360.0
@export var pitch_locked: bool = true
@export var pitch_lock_deg: float = DEFAULT_PITCH_DEG
## 相机 FOV。50 太广会让屏幕边缘的纸片人"变形拉宽"，32 接近长焦
@export var camera_fov: float = 32.0

var _camera: Camera3D
var _rotation_y: float = deg_to_rad(45.0)
var _pitch: float = deg_to_rad(45.0)
var _distance: float = 32.0
var _target: Vector3 = Vector3(20, 0, 20)
var _is_dragging: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("camera_controller")
	_camera = $Camera3D
	_camera.current = true
	_camera.fov = camera_fov
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

	# 朝向锁：把自由旋转吸附到允许的档位
	if yaw_locked:
		_rotation_y = _snap_yaw(_rotation_y)
	if pitch_locked:
		_pitch = deg_to_rad(pitch_lock_deg)

	_update_camera()

## 把 yaw 吸附到 [yaw_lock_deg, +step, +2step...] 的最近档位
func _snap_yaw(yaw: float) -> float:
	var base: float = deg_to_rad(yaw_lock_deg)
	if yaw_lock_step >= 359.9:
		return base
	var step: float = deg_to_rad(yaw_lock_step)
	var k: float = round((yaw - base) / step)
	return base + k * step

## 外部开关（编辑器/剧情过场用）
func set_yaw_lock(enabled: bool, angle_deg: float = 0.0, step_deg: float = 360.0) -> void:
	yaw_locked = enabled
	yaw_lock_deg = angle_deg
	yaw_lock_step = step_deg
	_rotation_y = _snap_yaw(_rotation_y)
	_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	# 滚轮缩放（鼠标悬在 UI 面板上时不缩放——滚轮留给列表滚动）
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP \
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var vp: Viewport = get_viewport()
		var hovered: Control = vp.gui_get_hovered_control() if vp.has_method("gui_get_hovered_control") else null
		if hovered != null:
			return
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
		if not yaw_locked:
			_rotation_y -= delta.x * 0.005
		if not pitch_locked:
			_pitch = clampf(_pitch - delta.y * 0.005, 0.2, 1.4)
		_last_mouse_pos = event.position
		_update_camera()

func _update_camera() -> void:
	if _camera == null:
		return
	if not is_equal_approx(_camera.fov, camera_fov):
		_camera.fov = camera_fov
	# 焦点跟随地形高度：拉近时镜头不会钻进山里，拉远时也不会悬得太高
	if Terrain.heightmap_img != null:
		_target.y = lerpf(_target.y, Terrain.get_height(_target.x, _target.z), 0.25)
	var offset: Vector3 = Vector3(
		sin(_rotation_y) * cos(_pitch),
		sin(_pitch),
		cos(_rotation_y) * cos(_pitch)
	) * _distance
	var pos: Vector3 = _target + offset
	# 相机不能钻进山里：固定 45° 俯角 + 站在山坡上时，镜头终点很容易落到地面以下，
	# 画面就会变成"从地下往上看"，整屏只剩一片土色（这个坑实际踩到过）。
	if Terrain.heightmap_img != null:
		var floor_y: float = Terrain.get_height(pos.x, pos.z) + 3.0
		if pos.y < floor_y:
			pos.y = floor_y
	_camera.global_position = pos
	_camera.look_at(_target, Vector3.UP)

func focus_on(pos: Vector3) -> void:
	_target = pos
	_update_camera()

