extends Node
## Pathfinder — A* 网格寻路
## 使用 GameManager.grid 的占用网格进行寻路

class_name Pathfinder

func find_path(start: Vector2i, goal: Vector2i) -> Array:
	var grid: GridManager = GameManager.grid
	if grid == null:
		return []
	if not grid.is_in_bounds(start) or not grid.is_in_bounds(goal):
		return []
	if not grid.is_walkable(goal):
		goal = _find_nearest_walkable(goal, grid)
	
	var open_set: Array = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var f_score: Dictionary = {}
	var closed: Dictionary = {}
	
	g_score[start] = 0.0
	f_score[start] = _heuristic(start, goal)
	
	while open_set.size() > 0:
		open_set.sort_custom(func(a, b): return f_score.get(a, INF) < f_score.get(b, INF))
		var current: Vector2i = open_set.pop_front()
		
		if current == goal:
			return _reconstruct_path(came_from, current)
		
		closed[current] = true
		
		for neighbor in grid.get_walkable_neighbors(current):
			if closed.has(neighbor):
				continue
			var tentative_g: float = g_score.get(current, INF) + 1.0
			if not open_set.has(neighbor):
				open_set.append(neighbor)
			elif tentative_g >= g_score.get(neighbor, INF):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative_g
			f_score[neighbor] = tentative_g + _heuristic(neighbor, goal)
	
	return []

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float(abs(a.x - b.x) + abs(a.y - b.y))

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array:
	var path: Array = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path

func _find_nearest_walkable(pos: Vector2i, grid: GridManager) -> Vector2i:
	for radius in range(1, 6):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var check: Vector2i = pos + Vector2i(dx, dz)
				if grid.is_in_bounds(check) and grid.is_walkable(check):
					return check
	return pos
