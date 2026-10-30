extends Node
## Pathfinder — A* 网格寻路（带缓存 + 迭代上限 + 整数索引加速）
## 使用 GameManager.grid 的占用网格进行寻路

class_name Pathfinder

var _cache: Dictionary = {}  # "start.x,start.y-goal.x,goal.y" → path Array
const _MAX_CACHE_SIZE: int = 256
const _MAX_ITER_MULT: int = 2  # 🔥 从 6 降到 2，防止长距离卡住
const _DEBUG_PRINT: bool = false

func _log(msg: String) -> void:
	if _DEBUG_PRINT:
		print("[Pathfinder] %s" % msg)

## 🔥 把 Vector2i 转成扁平整数索引
func _to_idx(p: Vector2i, w: int) -> int:
	return p.y * w + p.x

func find_path(start: Vector2i, goal: Vector2i) -> Array:
	var grid = GameManager.grid
	if grid == null:
		_log("❌ grid is null!")
		return []
	if not grid.is_in_bounds(start) or not grid.is_in_bounds(goal):
		_log("❌ out of bounds start=%s goal=%s" % [start, goal])
		return []
	
	var w: int = grid.map_size.x
	var h: int = grid.map_size.y
	var total: int = w * h
	
	# 🔥 智能 goal 落位
	if not grid.is_walkable(goal):
		goal = _find_nearest_walkable(goal, grid)
	if not grid.is_walkable(start):
		var ns: Vector2i = _find_nearest_walkable(start, grid)
		if ns == start:
			return []
		start = ns
	if start == goal:
		return [start]
	
	# 🔥 查缓存
	var cache_key: String = "%d,%d-%d,%d" % [start.x, start.y, goal.x, goal.y]
	if _cache.has(cache_key):
		var cached: Array = _cache[cache_key]
		if cached.size() > 0:
			return cached
		_cache.erase(cache_key)
	
	# 🔥 整数索引 Array 代替 Dictionary（GDScript Array 比 Dictionary 快 5-10x）
	var INF_VAL: float = 1e9
	var g_arr: PackedFloat32Array = PackedFloat32Array()
	g_arr.resize(total)
	g_arr.fill(INF_VAL)
	var f_arr: PackedFloat32Array = PackedFloat32Array()
	f_arr.resize(total)
	f_arr.fill(INF_VAL)
	var came_from: PackedInt32Array = PackedInt32Array()
	came_from.resize(total)
	came_from.fill(-1)
	var closed: PackedByteArray = PackedByteArray()
	closed.resize(total)
	closed.fill(0)
	
	var start_idx: int = _to_idx(start, w)
	var goal_idx: int = _to_idx(goal, w)
	g_arr[start_idx] = 0.0
	
	# 二叉最小堆（存整数索引）
	var heap: Array = []
	var heap_f: PackedFloat32Array = PackedFloat32Array()
	heap.append(start_idx)
	heap_f.append(_heuristic_i(start_idx, goal_idx, w))
	
	var max_iter: int = total * _MAX_ITER_MULT
	var iter_count: int = 0
	# 8 方向：只走 4 方向时路径是"楼梯状"，单位走起来一折一折地拐，
	# 再叠上贴地就特别像"原地抽搐"。斜向代价用 √2，避免斜线比直线更便宜。
	# dx, dy, cost
	var dirs: Array = [
		[1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0],
		[1, 1, 1.4142], [1, -1, 1.4142], [-1, 1, 1.4142], [-1, -1, 1.4142],
	]
	
	while heap.size() > 0:
		iter_count += 1
		if iter_count > max_iter:
			_log("⚠ 迭代上限触发 start=%s goal=%s iter=%d" % [start, goal, iter_count])
			return []
		var current: int = _heap_pop_i(heap, heap_f)
		
		if current == goal_idx:
			var path: Array = _reconstruct_path_i(came_from, current, w)
			path = _smooth_path(path, grid)
			if _cache.size() >= _MAX_CACHE_SIZE:
				var keys: Array = _cache.keys()
				for k in keys.slice(0, keys.size() / 2):
					_cache.erase(k)
			_cache[cache_key] = path
			return path
		
		if closed[current] != 0:
			continue
		closed[current] = 1
		
		var cx: int = current % w
		var cy: int = current / w
		for d in dirs:
			var nx: int = cx + int(d[0])
			var ny: int = cy + int(d[1])
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				continue
			var ni: int = ny * w + nx
			if closed[ni] != 0:
				continue
			if not grid.is_walkable(Vector2i(nx, ny)):
				continue
			# 防切角：斜向必须两个正交邻格都通，否则会"擦着墙角穿过去"
			if d[0] != 0 and d[1] != 0:
				if not grid.is_walkable(Vector2i(cx + int(d[0]), cy)):
					continue
				if not grid.is_walkable(Vector2i(cx, cy + int(d[1]))):
					continue
			var tentative_g: float = g_arr[current] + float(d[2])
			if tentative_g < g_arr[ni]:
				came_from[ni] = current
				g_arr[ni] = tentative_g
				var nf: float = tentative_g + _heuristic_i(ni, goal_idx, w)
				f_arr[ni] = nf
				_heap_push_i(heap, heap_f, ni, nf)
	
	_log("❌ 无路径 start=%s goal=%s iter=%d" % [start, goal, iter_count])
	return []

## 视线拉直：把"一格一格拐"的路径压成几个拐点。
## 8 方向 A* 出来仍然是一串格子，直接用会让单位像在画方格；拉直后是直线段。
func _smooth_path(path: Array, grid) -> Array:
	if path.size() <= 2:
		return path
	var out: Array = [path[0]]
	var i: int = 0
	while i < path.size() - 1:
		var j: int = path.size() - 1
		while j > i + 1:
			if _line_of_sight(path[i], path[j], grid):
				break
			j -= 1
		out.append(path[j])
		i = j
	return out

func _line_of_sight(a: Vector2i, b: Vector2i, grid) -> bool:
	# 逐格 DDA：每一小段都验证"目标格可走"，
	# 且斜跨时两侧正交格也必须可走（否则拉直会从两个斜挨着的障碍之间穿过去）。
	var dx: int = b.x - a.x
	var dy: int = b.y - a.y
	var steps: int = maxi(absi(dx), absi(dy))
	if steps == 0:
		return true
	var x: int = a.x
	var y: int = a.y
	for i in range(1, steps + 1):
		var nx: int = a.x + int(round(float(dx) * float(i) / float(steps)))
		var ny: int = a.y + int(round(float(dy) * float(i) / float(steps)))
		if not grid.is_walkable(Vector2i(nx, ny)):
			return false
		if nx != x and ny != y:
			if not grid.is_walkable(Vector2i(nx, y)):
				return false
			if not grid.is_walkable(Vector2i(x, ny)):
				return false
		x = nx
		y = ny
	return true

func _heuristic_i(a_idx: int, b_idx: int, w: int) -> float:
	var ax: int = a_idx % w
	var ay: int = a_idx / w
	var bx: int = b_idx % w
	var by: int = b_idx / w
	return float(abs(ax - bx) + abs(ay - by))

func _reconstruct_path_i(came_from: PackedInt32Array, current: int, w: int) -> Array:
	# 🔥 先 append（O(1)），最后 reverse 一次（O(n)），比 push_front 快 N 倍
	var path: Array = []
	while current != -1:
		var cx: int = current % w
		var cy: int = current / w
		path.append(Vector2i(cx, cy))
		current = came_from[current]
	# path 现在是倒序的（从 goal 到 start），reverse 一下
	path.reverse()
	return path

# ===== 整数索引二叉最小堆 =====
func _heap_push_i(heap: Array, heap_f: PackedFloat32Array, item: int, f: float) -> void:
	heap.append(item)
	heap_f.append(f)
	_sift_up_i(heap, heap_f, heap.size() - 1)

func _heap_pop_i(heap: Array, heap_f: PackedFloat32Array) -> int:
	var root: int = heap[0]
	var last_item: int = heap.pop_back()
	var last_f: float = heap_f[heap_f.size() - 1]
	heap_f.resize(heap_f.size() - 1)
	if heap.size() > 0:
		heap[0] = last_item
		# 原来是 heap_f.insert(0, last_f)：每次弹堆都要搬整个数组（O(n)），
		# 长路径上弹几万次就是几十万次搬移。直接覆盖下标等价且是 O(1)。
		heap_f[0] = last_f
		_sift_down_i(heap, heap_f, 0)
	return root

func _sift_up_i(heap: Array, heap_f: PackedFloat32Array, i: int) -> void:
	while i > 0:
		var p: int = (i - 1) >> 1
		if heap_f[p] <= heap_f[i]:
			break
		var ti: int = heap[i]
		heap[i] = heap[p]
		heap[p] = ti
		var tf: float = heap_f[i]
		heap_f[i] = heap_f[p]
		heap_f[p] = tf
		i = p

func _sift_down_i(heap: Array, heap_f: PackedFloat32Array, i: int) -> void:
	var n: int = heap.size()
	while true:
		var l: int = 2 * i + 1
		var r: int = 2 * i + 2
		var sm: int = i
		if l < n and heap_f[l] < heap_f[sm]:
			sm = l
		if r < n and heap_f[r] < heap_f[sm]:
			sm = r
		if sm == i:
			break
		var ti2: int = heap[i]
		heap[i] = heap[sm]
		heap[sm] = ti2
		var tf2: float = heap_f[i]
		heap_f[i] = heap_f[sm]
		heap_f[sm] = tf2
		i = sm

func _find_nearest_walkable(pos: Vector2i, grid) -> Vector2i:
	for radius in range(1, 8):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if abs(dx) == radius and abs(dz) == radius:
					continue
				var check: Vector2i = pos + Vector2i(dx, dz)
				if grid.is_in_bounds(check) and grid.is_walkable(check):
					return check
	for radius in range(1, 8):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var check: Vector2i = pos + Vector2i(dx, dz)
				if grid.is_in_bounds(check) and grid.is_walkable(check):
					return check
	return pos

func clear_cache() -> void:
	_cache.clear()
