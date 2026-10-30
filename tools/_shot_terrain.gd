extends Node
## 地面画质评估截图 v3：对准玩家基地 + 关战争迷雾 + 三档距离

const TerrainPicker = preload("res://scripts/mapeditor/TerrainPicker.gd")
var _main = null

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(3.5).timeout
	# 关战争迷雾
	var stack: Array = [_main]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
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
			stack.append(c)
	# 对准玩家基地（第一栋本方建筑）或第一个单位
	var cam: Node3D = get_tree().get_first_node_in_group("camera_controller")
	var target: Node3D = null
	for b in GameManager.all_buildings:
		if is_instance_valid(b) and b.get("faction") == GameManager.player_faction:
			target = b
			break
	if target == null:
		for u in GameManager.all_units:
			if is_instance_valid(u) and u.get("faction") == GameManager.player_faction:
				target = u
				break
	if target != null and cam != null and cam.has_method("focus_on"):
		cam.focus_on(target.global_position)
		print("[SHOT] 对准: ", target.global_position)
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_default.png")
	if cam != null and "_distance" in cam:
		cam.set("_distance", 14.0)
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_close.png")
		cam.set("_distance", 7.0)
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_macro.png")
	get_tree().quit(0)
