extends Node
## GLB 树导入视觉验收探针：三棵样树放编辑器平地上，45° 俯视截图。

func _ready() -> void:
	var _ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout

	# 三棵树间隔 8m 排一排，检查贴地 / alpha / 比例
	var names: Array[String] = ["tree_oak", "tree_bamboo", "tree_spruce"]
	var i: int = 0
	for n in names:
		var ps: PackedScene = load("res://assets/models/trees/%s.glb" % n)
		if ps == null:
			push_warning("[TREE] load fail: " + n)
			continue
		var t: Node3D = ps.instantiate()
		_ed.add_child(t)
		t.global_position = Vector3(120.0 + float(i) * 8.0, Terrain.get_height(120.0 + float(i) * 8.0, 120.0), 120.0)
		# 打印包围盒，核对原点/尺寸
		var aabb: AABB = _compute_aabb(t)
		print("[TREE] %s  pos=%.1f  aabb.pos=%s  aabb.size=%s" % [n, t.global_position.y, aabb.position, aabb.size])
		i += 1

	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null and cam.has_method("focus_on"):
		cam.focus_on(Vector3(124, 0, 120))
		if "_distance" in cam:
			cam.set("_distance", 28.0)
		await get_tree().create_timer(1.8).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_tree_import.png")
		print("[SHOT] tree import saved")
	get_tree().quit(0)

func _compute_aabb(n: Node) -> AABB:
	var total := AABB()
	var first := true
	for mi in _mesh_instances(n):
		var ab: AABB = mi.get_aabb()
		if first:
			total = ab
			first = false
		else:
			total = total.merge(ab)
	return total

func _mesh_instances(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			out.append(cur)
		for c in cur.get_children():
			stack.append(c)
	return out
