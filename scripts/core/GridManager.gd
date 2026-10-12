extends Node
## GridManager — 网格系统
## 管理建筑放置、占用格、路径寻路的底层网格
## 采用平面网格（X-Z平面），支持建筑占位和寻路

class_name GridManager

var map_size: Vector2i = Vector2i(84, 84)
var cell_size: float = 2.0
var origin: Vector3 = Vector3.ZERO

# 占用网格：0=可通行, 1=建筑占用, 2=城墙(阻挡但可破), 3=水
var occupied: Array = []  # 2D array of int

func _ready() -> void:
	_init_grid()

func _init_grid() -> void:
	occupied = []
	for x in range(map_size.x):
		var col: Array = []
		for z in range(map_size.y):
			col.append(0)
		occupied.append(col)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var gx: int = int((world_pos.x - origin.x) / cell_size)
	var gz: int = int((world_pos.z - origin.z) / cell_size)
	return Vector2i(gx, gz)

func grid_to_world(grid_pos: Vector2i) -> Vector3:
	var wx: float = origin.x + (float(grid_pos.x) + 0.5) * cell_size
	var wz: float = origin.z + (float(grid_pos.y) + 0.5) * cell_size
	return Vector3(wx, origin.y, wz)

func is_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < map_size.x and grid_pos.y >= 0 and grid_pos.y < map_size.y

func is_walkable(grid_pos: Vector2i) -> bool:
	if not is_in_bounds(grid_pos):
		return false
	return occupied[grid_pos.x][grid_pos.y] == 0

func is_placeable(grid_pos: Vector2i, size: Vector2i = Vector2i(1,1)) -> bool:
	for dx in range(size.x):
		for dz in range(size.y):
			var pos: Vector2i = grid_pos + Vector2i(dx, dz)
			if not is_in_bounds(pos):
				return false
			if occupied[pos.x][pos.y] != 0:
				return false
	return true

func set_occupied(grid_pos: Vector2i, size: Vector2i, value: int) -> void:
	for dx in range(size.x):
		for dz in range(size.y):
			var pos: Vector2i = grid_pos + Vector2i(dx, dz)
			if is_in_bounds(pos):
				occupied[pos.x][pos.y] = value

func clear_occupied(grid_pos: Vector2i, size: Vector2i) -> void:
	set_occupied(grid_pos, size, 0)

func get_neighbors(grid_pos: Vector2i) -> Array:
	var neighbors: Array = []
	var dirs: Array = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for d in dirs:
		var n: Vector2i = grid_pos + d
		if is_in_bounds(n):
			neighbors.append(n)
	return neighbors

func get_walkable_neighbors(grid_pos: Vector2i) -> Array:
	var result: Array = []
	for n in get_neighbors(grid_pos):
		if is_walkable(n):
			result.append(n)
	return result
