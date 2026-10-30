extends Node3D
## GLB 实体游戏内验收探针：进 Main → 找到第一个建筑（玩家基地）与单位
## → 相机飞过去实拍，确认战场上 GLB 模型生效。

var _main = null

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(5.0).timeout

	# 关战争迷雾/地形雾（同 _shot_roads：地形 shader 的 fog_enabled 是 FOW 遮罩强度）
	var fstack: Array = [_main]
	while not fstack.is_empty():
		var nd: Node = fstack.pop_back()
		if nd is MeshInstance3D:
			var mi := nd as MeshInstance3D
			var mats: Array = []
			if mi.material_override != null:
				mats.append(mi.material_override)
			for i in range(mi.get_surface_override_material_count()):
				var m2: Material = mi.get_surface_override_material(i)
				if m2 != null:
					mats.append(m2)
			for m in mats:
				if m is ShaderMaterial:
					(m as ShaderMaterial).set_shader_parameter("fog_enabled", 0.0)
		for c in nd.get_children():
			fstack.append(c)

	# 找场景里的建筑与单位
	var building: Node3D = null
	var unit: Node3D = null
	var stack: Array = [_main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() != null:
			var s: Script = n.get_script()
			if s.get_global_name() == "Building" and building == null:
				building = n
			elif s.get_global_name() == "Unit" and unit == null:
				unit = n
		for c in n.get_children():
			stack.append(c)
	print("[SHOT] building=%s unit=%s" % [building != null, unit != null])

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var target: Vector3 = building.global_position if building != null else Vector3.ZERO
	cam.position = target + Vector3(14, 11, 18)
	cam.look_at(target + Vector3(0, 2, 0))
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_game_glb.png")
	print("[SHOT] game glb saved")

	if unit != null:
		var t2: Vector3 = unit.global_position
		cam.position = t2 + Vector3(2.2, 1.8, 3.0)
		cam.look_at(t2 + Vector3(0, 0.8, 0))
		print("[SHOT] unit pos=", t2)
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_game_unit.png")
		print("[SHOT] game unit saved")
	get_tree().quit(0)
