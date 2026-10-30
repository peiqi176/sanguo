extends SceneTree
## GLB 实体模型 AABB 实测探针：打印每个模型的合并包围盒（尺寸 + 最低点），
## 用于 EntityGLTF 缩放标定。纯逻辑无渲染，headless 可跑。
## 用法：godot --headless --path . --script res://tools/_probe_gltf_aabb.gd

const DIR := "res://assets/models/entities/"

func _init() -> void:
	await process_frame
	var d := DirAccess.open(DIR)
	if d == null:
		print("[AABB] 目录不存在: ", DIR)
		quit(1)
		return
	for f in d.get_files():
		if not f.ends_with(".glb"):
			continue
		var path := DIR + f
		var ps: PackedScene = load(path)
		if ps == null:
			print("[AABB] ❌ 加载失败: ", f)
			continue
		var root: Node3D = ps.instantiate()
		var lo := Vector3(1e12, 1e12, 1e12)
		var hi := -lo
		var count := 0
		var stack: Array = [[root, Transform3D.IDENTITY]]
		while not stack.is_empty():
			var e: Array = stack.pop_back()
			var n: Node = e[0]
			var xf: Transform3D = e[1]
			if n is Node3D:
				xf = xf * (n as Node3D).transform
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				var aabb: AABB = xf * mi.get_aabb()
				count += 1
				lo = lo.min(aabb.position)
				hi = hi.max(aabb.position + aabb.size)
			for c in n.get_children():
				stack.append([c, xf])
		var size := hi - lo
		print("[AABB] %s  网格数=%d  尺寸=(%.2f, %.2f, %.2f)  最低点y=%.2f  min=(%.2f,%.2f,%.2f)" % [
			f, count, size.x, size.y, size.z, lo.y, lo.x, lo.y, lo.z])
		root.free()
	quit(0)
