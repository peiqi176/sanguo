extends Node3D
## GLB 实体模型实拍探针：摆官府/城门/刀兵营/牌坊/宫殿 + 士兵 a/b/c + xiao_a/b，
## 相机依次扫拍，确认模型内容、兵种归属、朝向与缩放。
## 带窗口跑（headless 拿不到画面）。

func _ready() -> void:
	await get_tree().create_timer(6.0).timeout

	# 简易光照环境（MapEditor 级曝光口径）
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.light_energy = 1.15
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.5, 0.65)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)

	# 找地形/光照环境（MapEditor 提供完整环境）
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true

	var shots: Array = [
		# [模型列表, 相机位置, 看向点, 文件名]
		[["buildings.government"], Vector3(20, 12, 26), Vector3(0, 3, 0), "gov"],
		[["buildings.barracks_sword"], Vector3(18, 10, 24), Vector3(0, 3, 0), "barracks"],
		[["buildings.gate_stone"], Vector3(12, 8, 16), Vector3(0, 3, 0), "gate"],
		[["buildings.paifang"], Vector3(24, 14, 30), Vector3(0, 5, 0), "paifang"],
		[["units.sword", "units.spear", "units.archer"], Vector3(5, 2.5, 7), Vector3(1.4, 1, 0), "soldiers"],
		[["units.palace"], Vector3(60, 35, 75), Vector3(0, 6, 0), "palace"],
	]
	for shot in shots:
		# 清掉上一轮模型
		for c in get_children():
			if c is Node3D and c != cam:
				c.queue_free()
		await get_tree().process_frame
		for ki in range(shot[0].size()):
			var key: String = shot[0][ki]
			var parts: PackedStringArray = String(key).split(".")
			var holder: Node3D = null
			if parts[0] == "buildings":
				holder = EntityGLTF.spawn("buildings", parts[1], self, Vector3.ZERO)
			elif key == "units.palace":
				# 宫殿不在标定表（暂无实体归属），手动摆
				var ps: PackedScene = load("res://assets/models/entities/gongdian_v4.glb")
				holder = Node3D.new()
				var g: Node3D = ps.instantiate()
				holder.add_child(g)
				holder.scale = Vector3.ONE * 0.5
				add_child(holder)
			else:
				# units.*：优先查 EntityGLTF 标定表（shibing_a_c 等映射名与 key 不同）
				var cfg: Dictionary = EntityGLTF.MODELS.get(key, {})
				var pth: String = str(cfg.get("path", "res://assets/models/entities/%s.glb" % parts[1]))
				var ps2: PackedScene = load(pth)
				holder = Node3D.new()
				holder.add_child(ps2.instantiate())
				holder.scale = Vector3.ONE * 1.6   # 1m 模型 → 1.6m 人高
				holder.position = Vector3(float(ki) * 1.4, 0, 0)   # 一字排开
				add_child(holder)
				holder = null
		cam.position = shot[1]
		cam.look_at(shot[2])
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_glb_%s.png" % shot[3])
		print("[SHOT] %s saved" % shot[3])
	get_tree().quit(0)
