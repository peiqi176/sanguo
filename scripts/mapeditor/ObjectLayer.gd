extends RefCounted
## ObjectLayer —— 编辑器的对象层（放置 / 选择 / 删除 / 与 doc 双向同步）
##
## 一条铁律：**doc.objects 是唯一真相，场景节点只是它的投影。**
##   · 放置：先生成 obj 字典 → spawn 出节点 → 再 doc.add_object() → _nodes 追加
##   · 删除：先 doc.remove_object() → 再释放节点 + 归还占位
##   · 改属性：改 doc → 重建该节点（不直接改节点字段，否则存盘就是旧值）
##
## _nodes 与 doc.objects 严格同索引对齐。任何一边增删，另一边必须同步，
## 否则选中索引会错位到你没点过的东西上。

const ObjectSpawner = preload("res://scripts/mapruntime/ObjectSpawner.gd")
const PlacementGhost = preload("res://scripts/mapeditor/PlacementGhost.gd")
const TerrainPicker = preload("res://scripts/mapeditor/TerrainPicker.gd")

var editor = null
var host: Node3D = null
var grid = null
var ghost = null

var placing_kind: String = ""
var placing_id: String = ""

var _nodes: Array = []              # 与 editor.doc.objects 一一对应
var _hover_grid: Vector2i = Vector2i.ZERO

func setup(ed: Node3D, grid_node) -> void:
	editor = ed
	host = ed
	grid = grid_node
	ghost = PlacementGhost.new()
	host.add_child(ghost)
	ghost.hide_ghost()

# ---------------------------------------------------------------- 放置

func is_placing() -> bool:
	return placing_kind != ""

func begin_placement(kind: String, id: String) -> void:
	placing_kind = kind
	placing_id = id
	ghost.setup(id, kind, grid.cell_size if grid != null else 2.0)
	ghost.show_ghost()
	editor.set_tool_mode(editor.Tool.PLACE)
	editor.toast("放置：%s（左键落位，右键/Esc 取消）" % id)

func cancel_placement() -> void:
	placing_kind = ""
	placing_id = ""
	if ghost != null:
		ghost.hide_ghost()
	editor.set_tool_mode(editor.Tool.TERRAIN)

## 光标移动时更新 ghost 位置与合法性。返回是否消费了这次移动。
func update_hover(screen_pos: Vector2) -> bool:
	if not is_placing():
		return false
	var vp: Viewport = host.get_viewport()
	var hit = TerrainPicker.world_from_screen(vp, screen_pos)
	if hit == null:
		ghost.hide_ghost()
		return true

	var gp: Vector2i = _align_to_footprint(grid.world_to_grid(hit))
	_hover_grid = gp
	ghost.move_to(gp, grid)
	ghost.set_valid(can_place_at(gp))
	return true

## 把光标所在格对齐成 footprint 的左上角 —— 让光标看起来在建筑中心
func _align_to_footprint(cursor: Vector2i) -> Vector2i:
	var fp: Vector2i = ghost.footprint
	return cursor - Vector2i(int(float(fp.x - 1) * 0.5), int(float(fp.y - 1) * 0.5))

func can_place_at(gp: Vector2i) -> bool:
	if grid == null:
		return false
	if not grid.is_in_bounds(gp):
		return false

	if placing_kind == "deco":
		# 装饰允许重叠、不占格，只要不在水里
		var wp: Vector3 = grid.grid_to_world(gp)
		return not Terrain.is_water(wp.x, wp.z)

	if placing_kind == "building":
		return grid.is_placeable(gp, ghost.footprint)

	# 单位 / 资源 / 村庄 / 野马：单格且必须空地
	return grid.is_placeable(gp, Vector2i(1, 1))

## 落位。成功返回 true。
func place_at(screen_pos: Vector2) -> bool:
	if not is_placing():
		return false
	var vp: Viewport = host.get_viewport()
	var hit = TerrainPicker.world_from_screen(vp, screen_pos)
	if hit == null:
		return false

	var gp: Vector2i = _align_to_footprint(grid.world_to_grid(hit))
	if not can_place_at(gp):
		return false

	var obj: Dictionary = _make_object(gp, hit)
	if obj.is_empty():
		return false

	# 先 spawn（内部会占格），失败了不能写 doc
	var node: Node = ObjectSpawner.spawn(host, grid, obj)
	if node == null:
		return false

	editor.doc.add_object(obj)
	_nodes.append(node)
	editor.mark_dirty()
	return true

func _make_object(gp: Vector2i, hit: Vector3) -> Dictionary:
	match placing_kind:
		"building":
			return {"kind": "building", "id": placing_id, "owner": editor.paint_owner,
					"grid": [gp.x, gp.y], "rot": 0}
		"unit":
			return {"kind": "unit", "id": placing_id, "owner": editor.paint_owner,
					"grid": [gp.x, gp.y], "rot": 0}
		"resource":
			return {"kind": "resource", "id": placing_id, "grid": [gp.x, gp.y], "amount": 800}
		"village":
			return {"kind": "village", "id": placing_id, "grid": [gp.x, gp.y]}
		"horse":
			return {"kind": "horse", "id": placing_id, "grid": [gp.x, gp.y]}
		"deco":
			# deco 用世界坐标，允许半格偏移
			return {"kind": "deco", "id": placing_id, "pos": [hit.x, hit.z], "scale": 1.0}
	return {}

# ---------------------------------------------------------------- 选择

## 用"最近对象"命中，不依赖碰撞体（实体不一定都带 CollisionShape3D）。
## 半径按类型给：建筑给一个 footprint 量级的宽容度，其他给小圆。
func select_at(screen_pos: Vector2) -> int:
	var vp: Viewport = host.get_viewport()
	var hit = TerrainPicker.world_from_screen(vp, screen_pos)
	if hit == null:
		editor.clear_selection()
		return -1

	var best: int = -1
	var best_d: float = 1e9
	var cs: float = grid.cell_size if grid != null else 2.0

	for i in range(editor.doc.objects.size()):
		var obj = editor.doc.objects[i]
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		var wp: Vector3 = object_world_pos(obj)
		var d: float = Vector2(hit.x - wp.x, hit.z - wp.z).length()
		var radius: float = cs * 1.1
		if str(obj.get("kind", "")) == "building":
			radius = cs * 2.2
		elif str(obj.get("kind", "")) == "deco":
			radius = cs * 0.8
		if d <= radius and d < best_d:
			best_d = d
			best = i

	if best >= 0:
		editor.set_selection(best)
	else:
		editor.clear_selection()
	return best

func object_world_pos(obj: Dictionary) -> Vector3:
	if str(obj.get("kind", "")) == "deco":
		var p = obj.get("pos", [0, 0])
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			var wx: float = float(p[0])
			var wz: float = float(p[1])
			return Vector3(wx, Terrain.get_height(wx, wz), wz)
	var g = obj.get("grid", [0, 0])
	var gx: int = int(g[0]) if typeof(g) == TYPE_ARRAY and (g as Array).size() >= 2 else 0
	var gy: int = int(g[1]) if typeof(g) == TYPE_ARRAY and (g as Array).size() >= 2 else 0
	if grid != null:
		return grid.grid_to_world(Vector2i(gx, gy))
	return Vector3(float(gx) * 2.0, 0.0, float(gy) * 2.0)

# ---------------------------------------------------------------- 删除 / 改属性

func delete(idx: int) -> bool:
	var obj: Dictionary = editor.doc.get_object(idx)
	if obj.is_empty():
		return false

	ObjectSpawner.release_footprint(grid, obj)

	if idx >= 0 and idx < _nodes.size():
		var n = _nodes[idx]
		_nodes.remove_at(idx)
		if n != null and is_instance_valid(n):
			n.queue_free()

	editor.doc.remove_object(idx)
	editor.mark_dirty()
	return true

## 改归属：改 doc 后重建这个节点（Building/Unit 的颜色是在 _ready 里定的，改字段没用）
func change_owner(idx: int, owner: String) -> void:
	var obj: Dictionary = editor.doc.get_object(idx)
	if obj.is_empty():
		return
	obj["owner"] = owner
	editor.doc.replace_object(idx, obj)
	respawn_one(idx)

## 改资源量
func change_amount(idx: int, amount: int) -> void:
	var obj: Dictionary = editor.doc.get_object(idx)
	if obj.is_empty():
		return
	obj["amount"] = amount
	editor.doc.replace_object(idx, obj)
	respawn_one(idx)

## 重建第 idx 个节点（保持 doc 不变）
func respawn_one(idx: int) -> void:
	if idx < 0 or idx >= _nodes.size():
		return
	var obj: Dictionary = editor.doc.get_object(idx)
	if obj.is_empty():
		return

	ObjectSpawner.release_footprint(grid, obj)
	var old = _nodes[idx]
	if old != null and is_instance_valid(old):
		old.queue_free()

	var node: Node = ObjectSpawner.spawn(host, grid, obj)
	_nodes[idx] = node
	editor.mark_dirty()

# ---------------------------------------------------------------- 批量同步

## 从 doc 全量重建（读档、切图用）。会先清掉现有节点并重置占位。
func rebuild_all() -> void:
	clear_nodes()
	if editor.doc == null:
		return
	for obj in editor.doc.objects:
		if typeof(obj) != TYPE_DICTIONARY:
			_nodes.append(null)
			continue
		_nodes.append(ObjectSpawner.spawn(host, grid, obj))
	editor.clear_selection()

func clear_nodes() -> void:
	for n in _nodes:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	if grid != null:
		grid._init_grid()     # 占位表重置（会重新按地形标水域）

## 地形改完调一次：让所有对象重新贴地。
## 单位自己有贴地逻辑（editor_mode 下也保留），但建筑是 StaticBody3D，不会自己动。
func resnap() -> void:
	for i in range(_nodes.size()):
		var n = _nodes[i]
		if n == null or not is_instance_valid(n) or not (n is Node3D):
			continue
		var obj: Dictionary = editor.doc.get_object(i)
		if obj.is_empty():
			continue
		var wp: Vector3 = object_world_pos(obj)
		(n as Node3D).global_position.y = Terrain.get_height(wp.x, wp.z)

func node_at(idx: int):
	if idx < 0 or idx >= _nodes.size():
		return null
	return _nodes[idx]

func node_count() -> int:
	return _nodes.size()
