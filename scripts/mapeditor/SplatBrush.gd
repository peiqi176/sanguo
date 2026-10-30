extends RefCounted
## SplatBrush —— 地表拼图层笔刷算子（纯函数：不碰节点、不碰 autoload、不起场景）
##
## 为什么需要这一层：
##   高度笔刷只能改"地形起伏"，改不了"这块地看起来是什么"。程序生成的群系
##   （草 / 森林 / 土 / 石板）是按噪声算的，永远摆不出"一条从城门通向码头的土路"、
##   "河湾那片沙洲"、"矿坑口一圈裸岩"。RTS 地图的死活全靠这些手工痕迹。
##
## 数据形态：两张 RGBA8 图，共 6 个可叠加的地表图层
##   splat1: R = 沙地(sand)  G = 泥土(dirt)  B = 岩石(rock)  A = 森林地被(forest)
##   splat2: R = 石板路(paved)  G = 土路(road_dirt)   （B/A 留给以后的层）
##   值域 0~1 = 该层覆盖强度；全 0 = 完全用程序群系（默认状态，不占任何视觉）
##
## 与 TerrainBrush 的关系：共用 world_to_pixel / world_radius_to_pixel（投影必须一致），
##   但算子分开——高度是 RF 单通道、拼图是 RGBA8 选通道，混在一起只会更难读。
##
## ⚠️ 通道语义一旦定下就不能改：存档里的 splat.png / splat2.png 是按这个顺序解释的。

## 图层下标（与 shader 里的通道顺序严格对应；>=4 的层写 splat2）
enum Layer { SAND, DIRT, ROCK, FOREST, PAVED, ROAD }

const LAYER_NAMES: PackedStringArray = ["沙地", "泥土", "岩石", "森林地被", "石板路", "土路"]
const LAYER_COLORS: Array = [
	Color(0.90, 0.82, 0.55),   # 沙
	Color(0.62, 0.48, 0.32),   # 土
	Color(0.62, 0.62, 0.66),   # 岩
	Color(0.24, 0.44, 0.20),   # 林
	Color(0.58, 0.58, 0.62),   # 石板路
	Color(0.60, 0.47, 0.30),   # 土路
]

## >= LAYER_SPLAT2_START 的层住在第二张拼图（splat2）里
const LAYER_SPLAT2_START: int = 4

## 草地层（2026-10-29 新增）：草地是"程序群系"，没有自己的 splat 通道——
## 变种选择编码进 splat2.B（0 = 自动噪声分带，(idx+1)/255 = 第 idx 种）。
## 刷草地 = 写 B 覆盖 + 同时清掉 splat1 四通道与 splat2 路面通道（草要露出来）。
const LAYER_GRASS: int = 6

## 草种清单（下标 = splat2.B 编码 idx；名字与 shader 里的 gsel 落点一一对应）
const GRASS_VARIANTS: Array = [
	{"id": 0, "label": "丰茂草", "tip": "Grass005 · 湿润浓绿（河畔/花园）"},
	{"id": 1, "label": "常绿草", "tip": "Grass006 · 标准草皮（默认基底）"},
	{"id": 2, "label": "草坪", "tip": "Grass008 · 均匀细草（庭院/校场）"},
	{"id": 3, "label": "野草", "tip": "Grass007 · 绿褐粗草（荒地/田埂）"},
	{"id": 4, "label": "枯黄草", "tip": "Grass004 · 干草黄（秋草/旱地）"},
]

## 石板种清单（下标 = splat2.A 编码 idx；131 长苔石不用选——它按"路缘权重"自动长苔）
const PAVED_VARIANTS: Array = [
	{"id": 0, "label": "方石 070", "tip": "PavingStones070 · 细密灰方石（基底）"},
	{"id": 1, "label": "大板 138", "tip": "PavingStones138 · 大块石板（广场/主干道）"},
	{"id": 2, "label": "方石 109", "tip": "PavingStones109 · 规整灰方石"},
	{"id": 3, "label": "方石 111", "tip": "PavingStones111 · 灰蓝方石"},
	{"id": 4, "label": "人字 081", "tip": "PavingStones081 · 人字铺装（城镇街道）"},
]

## 变种 idx → splat2 通道编码值（0 = 自动；n/255 一格正好是 RGBA8 的最小步长）
static func encode_variant(idx: int) -> float:
	return clampf(float(idx + 1) / 255.0, 0.0, 1.0)

## 笔画随机种子：每次起笔换新 → 每一笔的有机边缘形状都不一样。
## 0 = 确定性（自测/探针用）；MapEditor._begin_stroke 里赋 randi()。
static var stroke_seed: int = 0

# ---------------------------------------------------------------- 噪声（有机边缘用）

## 确定性整数哈希 → [0,1)。GDScript int 是 64 位，溢出回绕正好当哈希用。
static func _hash2(px: int, py: int) -> float:
	var h: int = px * 374761393 + py * 668265263 + stroke_seed * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0

## 简单 value noise（格点取 _hash2，双线性 + smoothstep 插值）。
## freq 单位是"每像素一个周期"——splat 像素约 0.6m，0.2 ≈ 3m 一块斑块。
static func _vnoise(x: float, y: float, freq: float) -> float:
	var fx: float = x * freq
	var fy: float = y * freq
	var ix: int = int(floor(fx))
	var iy: int = int(floor(fy))
	var tx: float = fx - floor(fx)
	var ty: float = fy - floor(fy)
	var ux: float = tx * tx * (3.0 - 2.0 * tx)
	var uy: float = ty * ty * (3.0 - 2.0 * ty)
	var a := _hash2(ix, iy)
	var b := _hash2(ix + 1, iy)
	var c := _hash2(ix, iy + 1)
	var d := _hash2(ix + 1, iy + 1)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)

# ---------------------------------------------------------------- 索引

## 图层下标 → 该层在对应 Image 的 Color 里占哪个分量。
## 层 0~3 = splat1 的 r/g/b/a；层 4~5 = splat2 的 r/g。
## 用 match 而不是数组下标，是为了让"通道顺序"这件事在代码里显式出现一次，
## 以后有人改 shader 的通道顺序时会在这里被绊一下。
static func layer_component(layer: int) -> int:
	match layer:
		Layer.SAND: return 0    # splat1.r
		Layer.DIRT: return 1    # splat1.g
		Layer.ROCK: return 2    # splat1.b
		Layer.FOREST: return 3  # splat1.a
		Layer.PAVED: return 0   # splat2.r
		Layer.ROAD: return 1    # splat2.g
	return 0

## Color 按分量下标读写（Color[i] 是可写的，但显式写出来更好搜）
static func _get_comp(c: Color, comp: int) -> float:
	match comp:
		0: return c.r
		1: return c.g
		2: return c.b
		_: return c.a

static func _set_comp(c: Color, comp: int, v: float) -> Color:
	var out: Color = c
	match comp:
		0: out.r = v
		1: out.g = v
		2: out.b = v
		_: out.a = v
	return out

# ---------------------------------------------------------------- 笔刷

## 执行一次拼图笔刷。
##   img        拼图1（FORMAT_RGBA8，层 0~3），就地修改
##   center_px  笔刷中心（像素坐标，可为小数；用 TerrainBrush.world_to_pixel 算）
##   radius_px  笔刷半径（像素；用 TerrainBrush.world_radius_to_pixel 算）
##   layer      Layer 枚举，决定刷哪个通道；>=4 时写到 img2
##   amount     本次该通道的强度增量（正=覆盖，负=擦除），已按 delta 归一化
##   img2       拼图2（层 4~5：石板路/土路）；刷层 4/5 时必须给，否则静默忽略
##
## 返回被（可能）改写的像素矩形；空矩形表示什么都没碰到。
## 脏矩形契约与 TerrainBrush 一致：撤销栈只存这一小块。
static func apply(img: Image, center_px: Vector2, radius_px: float,
		layer: int, amount: float, img2: Image = null) -> Rect2i:
	if is_zero_approx(amount):
		return Rect2i()
	# 层 4/5 走第二张图
	if layer >= LAYER_SPLAT2_START:
		if img2 == null:
			return Rect2i()
		img = img2
		layer -= LAYER_SPLAT2_START
	if img == null:
		return Rect2i()

	var sz_x: int = img.get_width()
	var sz_y: int = img.get_height()
	var cx: float = center_px.x
	var cy: float = center_px.y
	var pr: float = maxf(radius_px, 0.5)

	var x0: int = clampi(int(floor(cx - pr)), 0, sz_x - 1)
	var x1: int = clampi(int(ceil(cx + pr)), 0, sz_x - 1)
	var y0: int = clampi(int(floor(cy - pr)), 0, sz_y - 1)
	var y1: int = clampi(int(ceil(cy + pr)), 0, sz_y - 1)
	if x1 < x0 or y1 < y0:
		return Rect2i()

	var comp: int = layer_component(layer)
	var changed: bool = false

	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var dx: float = float(px) - cx
			var dy: float = float(py) - cy
			var d: float = sqrt(dx * dx + dy * dy)
			if d > pr:
				continue
			# 中心 1 → 边缘 0 的 smoothstep 衰减。
			# ⚠️ 必须用 smoothstep 而不是线性：线性衰减的笔刷会在边界留下一圈
			#    肉眼可见的"台阶"，在 45° 俯视下尤其像一块贴上去的圆盘。
			var t: float = clampf(d / pr, 0.0, 1.0)
			var w: float = 1.0 - t * t * (3.0 - 2.0 * t)
			# ---- 有机边缘（2026-10-27 用户反馈：不要"把整个圆都擦出来"）----
			# 只调制外圈 50%：内芯权重保持 1（自测的精确值断言不受影响），
			# 边界位置按噪声在 0.55R~1.0R 之间逐像素波动 → 圆盘变成有机斑块边。
			# 两档频率：低频出大湾、高频出毛边；笔画种子让每一笔形状都不同。
			if t > 0.5:
				var n: float = _vnoise(float(px), float(py), 0.16) * 0.60 \
						+ _vnoise(float(px), float(py), 0.65) * 0.40
				var edge: float = 0.55 + 0.45 * n
				var w2: float = 1.0 - smoothstep(edge - 0.22, edge + 0.02, t)
				w = minf(w, w2)
			var c: Color = img.get_pixel(px, py)
			var before: float = _get_comp(c, comp)
			var after: float = clampf(before + amount * w, 0.0, 1.0)
			if is_equal_approx(before, after):
				continue
			img.set_pixel(px, py, _set_comp(c, comp, after))
			changed = true

	if not changed:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

## 画一笔"路"（2026-10-27 用户口径：中间是路，两边自动补上路边的过渡）。
## 参照 AoE4 实拍参考图的三段式结构：
##   路芯   0 ~ ~0.5R：路面层（PAVED=石板 / ROAD=土路），噪声波浪边
##   过渡带 ~0.5R ~ 1.25R：泥土层（splat1 的 DIRT，用用户的"磨损土"贴图），
##           斑块状淡出进草——草里带土斑、土里带草斑，绝不是一圈硬边
##   外缘   1.25R 以外：不碰（保持程序群系）
## amount 语义与 apply() 一致（正=画，负=Shift 擦除，路和路肩同步退回）。
## 返回两张图的并集脏矩形；调用方必须同时 mark 两个撤销栈。
## variant_idx >= 0 时同时把 splat2.A 编码成该石板种（负量擦除时把 A 清回自动）。
static func paint_road(img1: Image, img2: Image, center_px: Vector2, radius_px: float,
		layer: int, amount: float, variant_idx: int = -1) -> Rect2i:
	if is_zero_approx(amount) or img1 == null or img2 == null:
		return Rect2i()
	var road_comp: int = 0 if layer == Layer.PAVED else 1   # splat2 的 r/g
	var venc: float = encode_variant(variant_idx) if variant_idx >= 0 else 0.0
	var sz_x: int = mini(img1.get_width(), img2.get_width())
	var sz_y: int = mini(img1.get_height(), img2.get_height())
	var cx: float = center_px.x
	var cy: float = center_px.y
	var pr: float = maxf(radius_px, 0.5)
	var reach: float = pr * 1.25

	var x0: int = clampi(int(floor(cx - reach)), 0, sz_x - 1)
	var x1: int = clampi(int(ceil(cx + reach)), 0, sz_x - 1)
	var y0: int = clampi(int(floor(cy - reach)), 0, sz_y - 1)
	var y1: int = clampi(int(ceil(cy + reach)), 0, sz_y - 1)
	if x1 < x0 or y1 < y0:
		return Rect2i()

	var changed: bool = false
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var dx: float = float(px) - cx
			var dy: float = float(py) - cy
			var t: float = sqrt(dx * dx + dy * dy) / pr
			if t > 1.25:
				continue
			# 两套噪声（坐标直接用像素，splat 像素 ≈ 0.6m）：
			#   n1 中频 —— 路芯边界的波浪（3~6m 尺度的弯）
			#   n2 低频 —— 路肩泥土的斑块（8~20m 尺度的磨损斑）
			var n1: float = _vnoise(float(px), float(py), 0.22) * 0.6 \
					+ _vnoise(float(px), float(py), 0.8) * 0.4
			var n2: float = _vnoise(float(px), float(py), 0.09) * 0.7 \
					+ _vnoise(float(px), float(py), 0.4) * 0.3
			# ---- 路芯：有效边界在 0.40R~0.66R 间波动 ----
			var core_edge: float = 0.40 + 0.26 * n1
			var road_w: float = 1.0 - smoothstep(core_edge - 0.14, core_edge + 0.05, t)
			road_w = clampf(road_w, 0.0, 1.0)
			# ---- 路肩：贴着路芯外侧的斑块状泥土，向 1.25R 淡出 ----
			var outer: float = 1.0 - smoothstep(0.45, 1.25, t)
			var patches: float = smoothstep(0.30, 0.62, n2)
			var shoulder_w: float = clampf(outer * patches * (1.0 - road_w), 0.0, 1.0)

			if road_w > 0.003:
				var c2: Color = img2.get_pixel(px, py)
				var before2: float = _get_comp(c2, road_comp)
				var after2: float = clampf(before2 + amount * road_w, 0.0, 1.0)
				if not is_equal_approx(before2, after2):
					img2.set_pixel(px, py, _set_comp(c2, road_comp, after2))
					changed = true
				# 石板种编码：正量 = 写入手选变种；负量（擦除）= 把 A 清回自动。
				# 只在刷石板路（PAVED）时写 A，土路没有变种。
				if layer == Layer.PAVED:
					var c2b: Color = img2.get_pixel(px, py)
					var va: float = c2b.a
					var va_after: float = venc if amount > 0.0 else va * (1.0 - road_w)
					if not is_equal_approx(va, va_after):
						c2b.a = va_after
						img2.set_pixel(px, py, c2b)
			if shoulder_w > 0.003:
				var c1: Color = img1.get_pixel(px, py)
				var before1: float = _get_comp(c1, 1)   # splat1.g = DIRT
				var after1: float = clampf(before1 + amount * shoulder_w, 0.0, 1.0)
				if not is_equal_approx(before1, after1):
					img1.set_pixel(px, py, _set_comp(c1, 1, after1))
					changed = true

	if not changed:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

## 刷"草地"（2026-10-29）：把 splat2.B 编码成手选草种，并按笔刷权重清掉
## splat1 四通道与 splat2 路面通道——草是程序群系的"底色"，别的层压着它就看不见。
##   variant_idx  草种下标（GRASS_VARIANTS 的 id）
##   amount       正 = 画（写 B + 清其他层），负 = Shift 擦除（B 淡回 0 = 恢复自动噪声）
## 返回两张图的并集脏矩形；调用方必须同时 mark 两个撤销栈。
static func paint_grass_variant(img1: Image, img2: Image, center_px: Vector2,
		radius_px: float, variant_idx: int, amount: float) -> Rect2i:
	if is_zero_approx(amount) or img1 == null or img2 == null:
		return Rect2i()
	# variant_idx < 0 = "自动草"：画下去是把 B 清回 0（恢复噪声分带）+ 清掉别的层
	var venc: float = encode_variant(variant_idx) if variant_idx >= 0 else 0.0
	var sz_x: int = mini(img1.get_width(), img2.get_width())
	var sz_y: int = mini(img1.get_height(), img2.get_height())
	var cx: float = center_px.x
	var cy: float = center_px.y
	var pr: float = maxf(radius_px, 0.5)

	var x0: int = clampi(int(floor(cx - pr)), 0, sz_x - 1)
	var x1: int = clampi(int(ceil(cx + pr)), 0, sz_x - 1)
	var y0: int = clampi(int(floor(cy - pr)), 0, sz_y - 1)
	var y1: int = clampi(int(ceil(cy + pr)), 0, sz_y - 1)
	if x1 < x0 or y1 < y0:
		return Rect2i()

	var changed: bool = false
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var dx: float = float(px) - cx
			var dy: float = float(py) - cy
			var d: float = sqrt(dx * dx + dy * dy)
			if d > pr:
				continue
			var t: float = clampf(d / pr, 0.0, 1.0)
			var w: float = 1.0 - t * t * (3.0 - 2.0 * t)
			# 有机边缘与 apply()/paint_road() 同款（外圈 50% 双频噪声调制）
			if t > 0.5:
				var n: float = _vnoise(float(px), float(py), 0.16) * 0.60 \
						+ _vnoise(float(px), float(py), 0.65) * 0.40
				var edge: float = 0.55 + 0.45 * n
				var w2: float = 1.0 - smoothstep(edge - 0.22, edge + 0.02, t)
				w = minf(w, w2)
			var c2: Color = img2.get_pixel(px, py)
			if amount > 0.0:
				# 画：B 写死编码（硬值不能混权，混了 idx 会串）；其余层按权重压暗
				if not is_equal_approx(c2.b, venc):
					c2.b = venc
					img2.set_pixel(px, py, c2)
					changed = true
				var c1: Color = img1.get_pixel(px, py)
				var c1b: Color = Color(c1.r * (1.0 - w), c1.g * (1.0 - w),
						c1.b * (1.0 - w), c1.a * (1.0 - w))
				var c2n: Color = Color(c2.r * (1.0 - w), c2.g * (1.0 - w), c2.b, c2.a)
				if not c1.is_equal_approx(c1b):
					img1.set_pixel(px, py, c1b)
					changed = true
				if not c2.is_equal_approx(c2n):
					img2.set_pixel(px, py, c2n)
					changed = true
			else:
				# 擦：B 淡回 0（自动噪声分带），其他层不动（草露出即可）
				var vb: float = c2.b
				var vb_after: float = vb * (1.0 - w)
				if not is_equal_approx(vb, vb_after):
					c2.b = vb_after
					img2.set_pixel(px, py, c2)
					changed = true

	if not changed:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

## 一次性把某个像素位置的四个通道读出来（调试 / 自测 / 小地图上色都用它）
static func weights_at(img: Image, px: int, py: int) -> Color:
	if img == null:
		return Color(0, 0, 0, 0)
	var sz_x: int = img.get_width()
	var sz_y: int = img.get_height()
	return img.get_pixel(clampi(px, 0, sz_x - 1), clampi(py, 0, sz_y - 1))

## 最新的一张空拼图（全 0 = 完全由程序群系决定）
static func make_empty(size: int) -> Image:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	return img

## 拿一张拼图里"最明显"的图层（给小地图/缩略图用）。全 0 返回 -1。
static func dominant_layer(img: Image, px: int, py: int) -> int:
	var c: Color = weights_at(img, px, py)
	var best: int = -1
	var best_v: float = 0.10    # 低于 10% 视为没刷
	var vals: Array = [c.r, c.g, c.b, c.a]
	for i in range(4):
		if float(vals[i]) > best_v:
			best_v = float(vals[i])
			best = i
	return best

## 统计有多少比例的像素被刷过（编辑器状态栏 / 自测用）
static func painted_ratio(img: Image) -> float:
	if img == null:
		return 0.0
	var sz_x: int = img.get_width()
	var sz_y: int = img.get_height()
	if sz_x <= 0 or sz_y <= 0:
		return 0.0
	var hit: int = 0
	# 稀疏采样（每 4 像素取 1），200 万像素全扫在拖笔刷时会掉帧
	for py in range(0, sz_y, 4):
		for px in range(0, sz_x, 4):
			var c: Color = img.get_pixel(px, py)
			if c.r + c.g + c.b + c.a > 0.02:
				hit += 1
	var total: int = int(ceil(float(sz_x) / 4.0)) * int(ceil(float(sz_y) / 4.0))
	return float(hit) / float(maxi(total, 1))
