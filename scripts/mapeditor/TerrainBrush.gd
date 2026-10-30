extends RefCounted
## TerrainBrush —— 地形笔刷算子（纯函数：不碰节点、不碰 autoload、不起场景）
##
## 为什么单独抽出来：
##   ① MapEditor.gd 原来把渲染 / 输入 / 笔刷 / 撤销 / 存档 / UI 全塞在 532 行里，
##      再加对象层和生成向导会失控。
##   ② 算子要能被自测脚本直接调用（headless 里不需要 3D 场景就能验算）。
##
## 脏矩形契约（很重要）：
##   apply() 返回被改写像素的 Rect2i，撤销栈只存这一小块的前后快照。
##   如果每次存整图，512² 一张就是 1MB，32 步撤销 = 32MB，拖笔刷时会明显卡。
##   → 实测 100×100 的笔刷区约 40KB，同样的步数只占 1/25 内存。

## 原始高度域的取值范围（乘 max_height 得到世界高度，单位米）
const H_MIN: float = -1.10
const H_MAX: float = 1.40

enum Mode { RAISE, LOWER, SMOOTH, FLATTEN }
const MODE_NAMES: PackedStringArray = ["抬升", "下压", "平滑", "平台"]

## 世界坐标 → 高度图像素坐标。
##
## ⚠️ 这个映射必须和 TerrainMaterial 的 shader 采样方式一致，否则会出现
##    "笔刷圈在光标处、刷出来的坑在别处"。对应关系：
##      u = x / world_size
##      v = 0.5 - (z / world_size - 0.5) = (world_size/2 - z)/world_size + 0.5
##    v 反向是因为图像第 0 行对应地图靠 z 大的一侧。
static func world_to_pixel(world: Vector3, world_size: float, img_size: int) -> Vector2:
	var u: float = world.x / world_size
	var v: float = (world_size * 0.5 - world.z) / world_size + 0.5
	var last: float = float(img_size - 1)
	return Vector2(u * last, v * last)

## 世界半径（米）→ 像素半径。最小 1，否则半径过小时整支笔刷静默失效。
static func world_radius_to_pixel(r: float, world_size: float, img_size: int) -> float:
	return maxf(r * float(img_size - 1) / world_size, 1.0)

## 执行一次笔刷。
##   img          高度图（FORMAT_RF），就地修改
##   center_px    笔刷中心（像素坐标，可为小数）
##   radius_px    笔刷半径（像素）
##   dh           原始高度域的增量（= 世界米增量 / max_height）
##   mode         Mode 枚举
##   flatten_target  平台笔刷的目标高度（原始域，不是世界高度）
##
## 返回被（可能）改写的像素矩形；空矩形表示什么都没碰到。
static func apply(img: Image, center_px: Vector2, radius_px: float,
		dh: float, mode: int, flatten_target: float) -> Rect2i:
	if img == null:
		return Rect2i()

	var sz: int = img.get_width()
	var cx: float = center_px.x
	var cy: float = center_px.y
	var pr: float = maxf(radius_px, 1.0)

	var x0: int = clampi(int(cx - pr), 0, sz - 1)
	var x1: int = clampi(int(cx + pr) + 1, 0, sz - 1)
	var y0: int = clampi(int(cy - pr), 0, sz - 1)
	var y1: int = clampi(int(cy + pr) + 1, 0, sz - 1)
	if x1 < x0 or y1 < y0:
		return Rect2i()

	# 平滑/平台的收敛速度。
	# ⚠️ 原来两个共用 dh*6：dh=强度·dt/max_height ≈ 0.00055/帧 → 速率 0.3%/帧，
	# 按住 5 秒才收敛 30% —— 用户实测"平整没有作用"。平台要的是"按住半秒内压平"，
	# 给它单独一个大得多的系数；平滑保持温和，太猛会把坡直接洗成台阶。
	var rate_smooth: float = clampf(dh * 12.0, 0.0, 1.0)
	var rate_flat: float = clampf(dh * 110.0, 0.0, 1.0)

	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var dx: float = float(px) - cx
			var dy: float = float(py) - cy
			var d: float = sqrt(dx * dx + dy * dy)
			if d > pr:
				continue
			# 中心 1、边缘 0 的平滑衰减（smoothstep），避免刷出硬邦邦的圆柱
			var t: float = clampf(d / pr, 0.0, 1.0)
			var w: float = 1.0 - t * t * (3.0 - 2.0 * t)
			var h: float = img.get_pixel(px, py).r
			match mode:
				Mode.RAISE:
					h += dh * w
				Mode.LOWER:
					h -= dh * w
				Mode.SMOOTH:
					h = lerpf(h, _neighbor_avg(img, px, py), clampf(rate_smooth * w, 0.0, 1.0))
				Mode.FLATTEN:
					h = lerpf(h, flatten_target, clampf(rate_flat * w, 0.0, 1.0))
			h = clampf(h, H_MIN, H_MAX)
			img.set_pixel(px, py, Color(h, 0.0, 0.0, 1.0))

	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

## 3×3 邻域均值（边缘用 clamp 取最近有效像素）
static func _neighbor_avg(img: Image, px: int, py: int) -> float:
	var sz: int = img.get_width()
	var sum: float = 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			sum += img.get_pixel(clampi(px + ox, 0, sz - 1), clampi(py + oy, 0, sz - 1)).r
	return sum / 9.0

## 一次性生成平台笔刷的目标高度（起笔点的高度，原始域）
static func flatten_target_at(img: Image, center_px: Vector2) -> float:
	if img == null:
		return 0.0
	var sz: int = img.get_width()
	var px: int = clampi(int(center_px.x), 0, sz - 1)
	var py: int = clampi(int(center_px.y), 0, sz - 1)
	return img.get_pixel(px, py).r
