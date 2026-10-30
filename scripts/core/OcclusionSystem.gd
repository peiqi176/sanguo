extends Node
## OcclusionSystem —— 帝国时代4 式「Obscured Unit Alpha」（P1-12）
## 本方单位走到建筑后面时，建筑保持不透明，但在建筑上方叠一个半透明势力色剪影，
## 让玩家始终知道自己的兵被挡住了、站在哪。
## 实现：每 0.12s 把所有可见建筑的屏幕包围盒算一遍，再判断本方单位的屏幕点是否
##       落在某个"比它更靠近镜头"的建筑盒子里。
## 注意：只处理玩家自己的单位（敌方单位本来就该被建筑和迷雾藏住）。

const INTERVAL: float = 0.12

var enabled: bool = true
var _timer: float = 0.0
var _debug_boxes: Array = []   # 探针/调试用：[Rect2, 相机距离]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	refresh()

func refresh() -> void:
	if GameManager == null or GameManager.game_over:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var pf: String = GameManager.player_faction
	# 1) 预计算所有已完成建筑的屏幕盒 + 到镜头距离
	var boxes: Array = []
	for b in GameManager.all_buildings:
		if not is_instance_valid(b) or not b.visible:
			continue
		if float(b.get("build_progress")) < 0.5:
			continue
		var rect: Rect2 = building_screen_rect(cam, b)
		if rect.size.x < 2.0 or rect.size.y < 2.0:
			continue
		boxes.append([rect, cam.global_position.distance_to(b.global_position)])
	_debug_boxes = boxes
	# 2) 判断每个本方单位是否被建筑挡住
	for u in GameManager.all_units:
		if not is_instance_valid(u) or not u.has_method("set_obscured"):
			continue
		if u.get_faction() != pf:
			continue
		var obscured: bool = false
		if u.visible and not cam.is_position_behind(u.global_position):
			var sp: Vector2 = cam.unproject_position(u.global_position + Vector3(0, 0.9, 0))
			var ud: float = cam.global_position.distance_to(u.global_position)
			for box in boxes:
				var rect2: Rect2 = box[0]
				if float(box[1]) < ud - 0.5 and rect2.has_point(sp):
					obscured = true
					break
		u.set_obscured(obscured)

## 建筑在屏幕上的包围盒（用立绘的世界宽高 + 相机右向量精确投影）
func building_screen_rect(cam: Camera3D, b: Node) -> Rect2:
	var w: float = 4.0
	var h: float = 4.0
	var anchor: float = 0.0
	var sp = b.get("_sprite")
	if sp != null and is_instance_valid(sp) and sp.visible and sp.texture != null:
		w = float(sp.texture.get_width()) * sp.pixel_size * absf(sp.scale.x)
		h = float(sp.texture.get_height()) * sp.pixel_size * absf(sp.scale.y)
		anchor = sp.position.y
	else:
		var cs: float = float(GameManager.cell_size)
		var sz: Vector2i = b.get("size")
		w = maxf(float(sz.x), float(sz.y)) * cs
		h = w * 1.5
	var base: Vector3 = b.global_position + Vector3(0.0, anchor, 0.0)
	var right: Vector3 = cam.global_transform.basis.x
	var pl: Vector3 = base - right * w * 0.5
	var pr: Vector3 = base + right * w * 0.5
	var pt: Vector3 = base + Vector3(0.0, h, 0.0)
	if cam.is_position_behind(pl) or cam.is_position_behind(pr) or cam.is_position_behind(base) or cam.is_position_behind(pt):
		return Rect2()
	var sl: Vector2 = cam.unproject_position(pl)
	var sr: Vector2 = cam.unproject_position(pr)
	var sb: Vector2 = cam.unproject_position(base)
	var st: Vector2 = cam.unproject_position(pt)
	var x0: float = minf(sl.x, sr.x)
	var x1: float = maxf(sl.x, sr.x)
	var y0: float = minf(st.y, sb.y)
	var y1: float = maxf(st.y, sb.y)
	return Rect2(Vector2(x0, y0), Vector2(x1 - x0, y1 - y0))
