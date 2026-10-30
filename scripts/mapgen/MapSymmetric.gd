extends RefCounted
## MapSymmetric —— 把地图强制对称化（竞技图公平性的唯一可靠做法）
##
## 为什么不能"生成两遍再拼"：噪声天然不可能两次一致，资源量一差，
## 对局就是先天不平衡。所以做法是「取主侧一半，翻到另一半」——
## 严格对称，误差为 0。
##
## 坐标约定：一切以 grid 像素/格为单位，n 是边长。
## 地形高度图是 FORMAT_RF（.r 存米数），镜像时只搬 .r，不碰其他通道。

enum Mode { POINT = 0, MIRROR_X = 1, MIRROR_Z = 2, ROTATE_90 = 3 }

const MODE_NAMES: Array = ["点对称（180°）", "沿 X 轴镜像", "沿 Z 轴镜像", "旋转 90°"]

static func mode_name(m: int) -> String:
	if m >= 0 and m < MODE_NAMES.size():
		return MODE_NAMES[m]
	return "未知"

## 矩形空间里的对称点。w/h 分开传，这样非正方形地图也不会算错。
static func mirror_wh(p: Vector2i, w: int, h: int, mode: int) -> Vector2i:
	match mode:
		Mode.POINT:
			return Vector2i(w - 1 - p.x, h - 1 - p.y)
		Mode.MIRROR_X:
			return Vector2i(p.x, h - 1 - p.y)
		Mode.MIRROR_Z:
			return Vector2i(w - 1 - p.x, p.y)
		Mode.ROTATE_90:
			# 90° 旋转只对方形有意义；非方形时退化成点对称，避免越界
			if w != h:
				return Vector2i(w - 1 - p.x, h - 1 - p.y)
			return Vector2i(p.y, w - 1 - p.x)
	return p

## 方形地图的便捷版本
static func mirror(p: Vector2i, n: int, mode: int) -> Vector2i:
	return mirror_wh(p, n, n, mode)

## p 所在的「对称轨道」。2 阶操作（点对称/镜像）返回 2 个点，
## 4 阶操作（旋转 90°）返回 4 个点，落在地图正中的点返回 1 个（自身）。
##
## 为什么必须按轨道而不是按"一次镜像"处理：90° 旋转下
## p → m(p) → m²(p) → m³(p) → p，只比 p 和 m(p) 会让同一条轨道上
## 出现两个"主点"，对称化直接失效（实测高度差 4.27m）。
static func orbit(p: Vector2i, w: int, h: int, mode: int) -> Array:
	var out: Array = [p]
	var q: Vector2i = p
	for i in range(3):
		q = mirror_wh(q, w, h, mode)
		if out.has(q):
			break
		out.append(q)
	return out

## 轨道上线性索引最小的那个点 —— 它就是「主点」。
## 对称化时所有非主点都从主点取值，这样轨道内必然完全一致。
static func primary_of(p: Vector2i, w: int, h: int, mode: int) -> Vector2i:
	var orb: Array = orbit(p, w, h, mode)
	if orb.size() <= 1:
		return p
	var best: Vector2i = orb[0]
	var best_idx: int = best.y * w + best.x
	for q in orb:
		var idx: int = q.y * w + q.x
		if idx < best_idx:
			best_idx = idx
			best = q
	return best

## p 是否在「主侧」（即它是自己轨道上的主点）。
static func is_primary(p: Vector2i, w: int, h: int, mode: int) -> bool:
	return primary_of(p, w, h, mode) == p

# ------------------------------------------------------------------ 地形

## 把高度图按 mode 对称化，就地改写。返回被改写的像素数。
static func apply_height(img: Image, mode: int) -> int:
	if img == null:
		return 0
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < 2 or h < 2:
		return 0
	var touched: int = 0
	for y in range(h):
		for x in range(w):
			var p := Vector2i(x, y)
			var src: Vector2i = primary_of(p, w, h, mode)
			if src == p:
				continue   # 主点保持原样，由它去覆盖整条轨道
			var v: float = img.get_pixel(src.x, src.y).r
			img.set_pixel(x, y, Color(v, 0.0, 0.0, 1.0))
			touched += 1
	return touched

## 群系图（RGBA8）同样搬一遍。返回被改写的像素数。
static func apply_biome(img: Image, mode: int) -> int:
	if img == null:
		return 0
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < 2 or h < 2:
		return 0
	var touched: int = 0
	for y in range(h):
		for x in range(w):
			var p := Vector2i(x, y)
			var src: Vector2i = primary_of(p, w, h, mode)
			if src == p:
				continue
			img.set_pixel(x, y, img.get_pixel(src.x, src.y))
			touched += 1
	return touched

# ------------------------------------------------------------------ 对象

## 对象按 mode 复制一份到对称位置，就地写回 doc.objects。
##
## owner_map: {"wei": "shu"} —— 镜像出来的对象该归谁。
##   不传则原样保留 owner（适合做"同阵营混战"图）。
## skip_kinds: 不想复制的类型（例如玩家起点相关的 deco）。
##
## 返回新增的对象数组（调用方/撤销栈可能要用）。
static func apply_objects(doc, mode: int, owner_map: Dictionary = {}, skip_kinds: Array = []) -> Array:
	var added: Array = []
	if doc == null:
		return added
	var n: int = int(doc.grid_n)
	if n < 2:
		return added
	# 先记下现有对象占据的位置，避免镜像出重复（例如本来就已经手摆了一份）
	var occupied: Dictionary = {}
	for o in doc.objects:
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var k: String = str(o.get("kind", ""))
		if o.has("grid"):
			occupied["%s:%s" % [k, str(o["grid"])]] = true
		elif o.has("pos"):
			occupied["%s:%s" % [k, str(o["pos"])]] = true

	var src: Array = doc.objects.duplicate()
	for o in src:
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var kind: String = str(o.get("kind", ""))
		if skip_kinds.has(kind):
			continue

		if kind == "deco" and o.has("pos"):
			# 装饰走世界坐标：先换成格，镜像，再换回来
			var cs: float = float(doc.cell_size)
			if cs <= 0.0:
				continue
			var pos: Array = o["pos"]
			var gp := Vector2i(int(floor(float(pos[0]) / cs)), int(floor(float(pos[1]) / cs)))
			# 先夹到合法格范围，再镜像：装饰可能被摆在界外一点点（拖拽边缘），
			# 不夹的话镜像结果会跑出地图，生成一堆不可见的装饰。
			var gp_safe := Vector2i(clampi(gp.x, 0, n - 1), clampi(gp.y, 0, n - 1))
			for mp in orbit(gp_safe, n, n, mode):
				if mp == gp_safe:
					continue
				var cd: Dictionary = o.duplicate(true)
				cd["pos"] = [(float(mp.x) + 0.5) * cs, (float(mp.y) + 0.5) * cs]
				if owner_map.has(str(o.get("owner", ""))):
					cd["owner"] = owner_map[str(o.get("owner", ""))]
				doc.objects.append(cd)
				added.append(cd)

		elif o.has("grid"):
			var g: Array = o["grid"]
			if g.size() < 2:
				continue
			var p := Vector2i(int(g[0]), int(g[1]))
			for mq in orbit(p, n, n, mode):
				if mq == p:
					continue   # 自身不复制（否则自己叠自己）
				var key: String = "%s:%s" % [kind, str([mq.x, mq.y])]
				if occupied.has(key):
					continue   # 目标位置本来就有同类对象，别叠一份
				occupied[key] = true
				var copy: Dictionary = o.duplicate(true)
				copy["grid"] = [mq.x, mq.y]
				if owner_map.has(str(o.get("owner", ""))):
					copy["owner"] = owner_map[str(o.get("owner", ""))]
				doc.objects.append(copy)
				added.append(copy)

	if not added.is_empty():
		doc.touch()
	return added

# ------------------------------------------------------------------ 一步到位

## 地形 + 群系 + 对象一次做完，给生成器/向导用。
## 返回 { "pixels": int, "objects": int }
static func apply_all(doc, height: Image, biome: Image, mode: int,
		owner_map: Dictionary = {}, skip_kinds: Array = []) -> Dictionary:
	var px: int = apply_height(height, mode)
	if biome != null:
		apply_biome(biome, mode)
	var objs: Array = apply_objects(doc, mode, owner_map, skip_kinds)
	return {"pixels": px, "objects": objs.size()}
