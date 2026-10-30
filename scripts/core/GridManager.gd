extends Node
## GridManager — 网格系统
## 管理建筑放置、占用格、路径寻路的底层网格
## 采用平面网格（X-Z平面），支持建筑占位和寻路

class_name GridManager

var map_size: Vector2i = Vector2i(84, 84)
var cell_size: float = 2.0
var origin: Vector3 = Vector3.ZERO

# 占用网格：0=可通行, 1=建筑占用, 2=城墙(阻挡但可破), 3=水, 4=边界禁区(永远不可通行)
var occupied: Array = []  # 2D array of int

## 边界禁区宽度（格）。对齐 AoE4：地图最外圈一圈谁都过不去（骑兵也不行），
## 视觉上用一圈密集的"边界树"标出来（见 Main._spawn_border_forest）。
## 4 格 × 2m = 8m 宽的隔离带，够种两排树也够让玩家一眼看出"这里过不去"。
const BORDER_CELLS: int = 4

func _ready() -> void:
	_init_grid()

func _init_grid() -> void:
	occupied = []
	for x in range(map_size.x):
		var col: Array = []
		for z in range(map_size.y):
			col.append(0)
		occupied.append(col)
	# 标记水下格（地形低于水面 -> 不可通行），供寻路避让
	for x in range(map_size.x):
		for z in range(map_size.y):
			var wx: float = origin.x + (float(x) + 0.5) * cell_size
			var wz: float = origin.z + (float(z) + 0.5) * cell_size
			if Terrain.is_water(wx, wz):
				occupied[x][z] = 3
	# 标记边界禁区：最外 BORDER_CELLS 圈一律不可通行/不可放置。
	# 放在水标记之后覆盖它——就算边界沉在水下也统一算禁区，提示语义一致。
	for x in range(map_size.x):
		for z in range(map_size.y):
			if x < BORDER_CELLS or z < BORDER_CELLS \
					or x >= map_size.x - BORDER_CELLS or z >= map_size.y - BORDER_CELLS:
				occupied[x][z] = 4

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var gx: int = int((world_pos.x - origin.x) / cell_size)
	var gz: int = int((world_pos.z - origin.z) / cell_size)
	return Vector2i(gx, gz)

func grid_to_world(grid_pos: Vector2i) -> Vector3:
	var wx: float = origin.x + (float(grid_pos.x) + 0.5) * cell_size
	var wz: float = origin.z + (float(grid_pos.y) + 0.5) * cell_size
	return Vector3(wx, Terrain.get_height(wx, wz), wz)

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
