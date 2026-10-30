extends RefCounted
## TerrainPicker —— 鼠标 → 地形表面交点
##
## 为什么不用物理碰撞体（HeightMapShape3D + intersect_ray）：
##   ① 高度是 shader 顶点位移出来的，碰撞体得手动同步每一个像素，永远慢一拍；
##   ② 一旦不同步，就会出现"笔刷贴在旧地形上、建筑浮在新地形上"这种玄学 Bug。
##   改用沿射线步进采样 Terrain.get_height()：和实体贴地用的是同一个函数，天生一致。
##
## 精度：先以 step 粗步进找到第一个穿地点，再在 [t-step, t] 区间二分 14 次。
## 14 次二分把 1.2m 的步长收敛到 1.2/2^14 ≈ 0.00007m，视觉上完全够。

## 粗步进长度。太小浪费 CPU，太大会漏掉薄山脊。
const STEP: float = 1.2
const BISECT_ITERS: int = 14

## 返回 Vector3（交点，y 已贴到地表）或 null（射线没打到地图）
static func ray_to_terrain(viewport: Viewport) -> Variant:
	if viewport == null:
		return null
	var cam: Camera3D = viewport.get_camera_3d()
	if cam == null:
		return null
	var mp: Vector2 = viewport.get_mouse_position()
	return from_ray(cam.project_ray_origin(mp), cam.project_ray_normal(mp))

## 从任意屏幕坐标发射（框选、右键菜单定位等用得到）
static func world_from_screen(viewport: Viewport, screen_pos: Vector2) -> Variant:
	if viewport == null:
		return null
	var cam: Camera3D = viewport.get_camera_3d()
	if cam == null:
		return null
	return from_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))

static func from_ray(origin: Vector3, dir: Vector3) -> Variant:
	var ws: float = Terrain.params.world_size

	# 相机钻到地表以下：直接投到脚下，否则射线从地下往上看永远不穿地
	if origin.y < Terrain.get_height(origin.x, origin.z):
		return Vector3(origin.x, Terrain.get_height(origin.x, origin.z), origin.z)

	var t: float = 0.0
	var max_t: float = 1200.0
	while t < max_t:
		t += STEP
		var p: Vector3 = origin + dir * t
		# 跑出地图范围太远就放弃（留 50m 余量，避免刚好贴边时误判）
		if t > 400.0 and (p.x < -50.0 or p.x > ws + 50.0 or p.z < -50.0 or p.z > ws + 50.0):
			return null
		if p.y <= Terrain.get_height(p.x, p.z):
			var lo: float = maxf(t - STEP, 0.0)
			for i in range(BISECT_ITERS):
				var mid: float = (lo + t) * 0.5
				var pm: Vector3 = origin + dir * mid
				if pm.y <= Terrain.get_height(pm.x, pm.z):
					t = mid
				else:
					lo = mid
			var hit: Vector3 = origin + dir * t
			hit.y = Terrain.get_height(hit.x, hit.z)
			return hit
	return null

## 世界坐标是否在地图范围内
static func in_bounds(pos: Vector3) -> bool:
	var ws: float = Terrain.params.world_size
	return pos.x >= 0.0 and pos.x <= ws and pos.z >= 0.0 and pos.z <= ws
