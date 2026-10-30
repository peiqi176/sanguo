extends Node
## 岩石层验收截图：自动找坡度最大处（露岩区）对准拍三档距离

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
	# 临时造山：默认图太平露不出岩，把山脊拉高重新生成（只为截图评估）
	Terrain.params.ridge_scale = 0.95
	Terrain.params.height_scale = 0.30
	Terrain.regenerate(Terrain.params.seed)
	await get_tree().create_timer(1.5).timeout
	# 扫高度图找最陡坡（露岩区）
	var terrain = Terrain  # autoload 单例
	var best := Vector2(150.0, 150.0)
	var best_s: float = -1.0
	if terrain != null and terrain.heightmap_img != null:
		var img: Image = terrain.heightmap_img
		var n: int = img.get_width()
		var span: float = terrain.WORLD_SIZE
		for iy in range(3, n - 3, 4):
			for ix in range(3, n - 3, 4):
				var hL: float = img.get_pixel(ix - 3, iy).r
				var hR: float = img.get_pixel(ix + 3, iy).r
				var hD: float = img.get_pixel(ix, iy - 3).r
				var hU: float = img.get_pixel(ix, iy + 3).r
				var s: float = abs(hR - hL) + abs(hU - hD)
				if s > best_s:
					best_s = s
					best = Vector2(float(ix) / float(n) * span, float(iy) / float(n) * span)
	print("[SHOT] 最陡坡 at ", best, " slope=", best_s)
	# 藏掉建筑/单位，避免挡镜头（只为贴图评估）
	for b in GameManager.all_buildings:
		if is_instance_valid(b):
			b.visible = false
	for u in GameManager.all_units:
		if is_instance_valid(u):
			u.visible = false
	var cam: Node3D = get_tree().get_first_node_in_group("camera_controller")
	var target := Vector3(best.x, terrain.get_height(best.x, best.y), best.y)
	# 用专用相机正对崖壁：沿最陡下降方向的水平反向后退
	var hL2: float = terrain.heightmap_img.get_pixel(int(best.x / terrain.WORLD_SIZE * terrain.heightmap_img.get_width()), int(best.y / terrain.WORLD_SIZE * terrain.heightmap_img.get_height())).r
	var step: float = terrain.WORLD_SIZE / terrain.heightmap_img.get_width() * 4.0
	var hx: float = terrain.get_height(best.x + step, best.y) - terrain.get_height(best.x - step, best.y)
	var hz: float = terrain.get_height(best.x, best.y + step) - terrain.get_height(best.x, best.y - step)
	var downhill := Vector2(-hx, -hz).normalized()
	var cam3 := Camera3D.new()
	add_child(cam3)
	for dist in [[30.0, "far"], [16.0, "close"], [7.0, "macro"]]:
		var d: float = dist[0]
		var pos := target + Vector3(downhill.x, 0.0, downhill.y) * d * 0.75 + Vector3(0.0, d * 0.55 + 1.5, 0.0)
		cam3.position = pos
		cam3.look_at(target + Vector3(0.0, 1.0, 0.0))
		cam3.current = true
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_rock_%s.png" % dist[1])
	get_tree().quit(0)
