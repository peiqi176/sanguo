extends Node
## GLB 树全链路验收：走 ObjectSpawner.spawn_deco 真实链路种一片混交林。
## 验证：调色板 id 解析 / TreeGLTF 加载 / 缩放 0.6 / 贴地。

const ObjectSpawnerS = preload("res://scripts/mapruntime/ObjectSpawner.gd")

var _ed = null

func _ready() -> void:
	_ed = load("res://scenes/MapEditor.tscn").instantiate()
	add_child(_ed)
	await get_tree().create_timer(3.0).timeout

	# ---- 1) 调色板清单自检：树种是否进面板 ----
	var ids: Array = ObjectSpawnerS.deco_ids()
	var species_cnt: int = 0
	for id in ids:
		var info: Dictionary = ObjectSpawnerS.parse_deco_id(str(id))
		if info.has("species"):
			species_cnt += 1
	print("[TREE] deco 清单 %d 项，其中 GLB 树种 %d 个" % [ids.size(), species_cnt])

	# ---- 2) 种一片混交林：5 树种 × 随机位置 ----
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var species: Array[String] = ["willow", "willow_v1", "oak", "spruce", "bamboo"]
	var placed: int = 0
	for i in range(30):
		var sp: String = species[i % species.size()]
		var x: float = 90.0 + rng.randf_range(-30.0, 30.0)
		var z: float = 130.0 + rng.randf_range(-25.0, 25.0)
		var n: Node3D = ObjectSpawnerS.spawn_deco(_ed, null, "tree_" + sp, Vector2(x, z), 1.0)
		if n != null:
			placed += 1
	print("[TREE] 种树 %d/30" % placed)

	var cam: Node3D = _ed.get_node_or_null("CameraController")
	if cam != null and cam.has_method("focus_on"):
		cam.focus_on(Vector3(88, 0, 128))
		if "_distance" in cam:
			cam.set("_distance", 32.0)
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png("C:/Users/shy/桌面/Godot/_shot_willow.png")
		print("[SHOT] forest saved")
	get_tree().quit(0)
