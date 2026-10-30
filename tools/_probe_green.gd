extends Node3D
## 探针：找出起点附近所有"大块绿色"的网格，确认那块突兀的绿板是什么。

const MapTemplates = preload("res://scripts/mapgen/MapTemplates.gd")
const MapGenService = preload("res://scripts/mapgen/MapGenService.gd")
const MapIO = preload("res://scripts/mapformat/MapIO.gd")

var _t: int = 0
var _main = null
const NAME: String = "_probe_green"

func _ready() -> void:
	var tpl: Dictionary = MapTemplates.template_def("two_kingdoms")
	tpl["grid_n"] = 84
	tpl["players"] = 2
	var gen: Dictionary = MapGenService.generate_and_save(tpl, {"map_name": NAME, "heightmap_size": 128, "biome_size": 128})
	print("[PROBE] 生成 ok=%s" % str(gen["ok"]))
	GameManager.game_settings_override = {"map_mode": "custom", "map_saved_name": NAME}
	GameManager.apply_settings()
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)

func _process(_d: float) -> void:
	_t += 1
	if _t != 50:
		return
	set_process(false)
	var gov = null
	for c in _main.get_children():
		if c.get("building_id") == "government":
			gov = c
			break
	if gov == null:
		print("[PROBE] 没找到官府")
		_done()
		return
	var c0: Vector3 = (gov as Node3D).global_position
	print("[PROBE] 官府 @ %s" % str(c0))
	_scan(_main, c0, 16.0)
	_done()

func _scan(n: Node, center: Vector3, radius: float) -> void:
	if n is MeshInstance3D and n.mesh != null:
		var mi: MeshInstance3D = n
		var gp: Vector3 = mi.global_position
		if gp.distance_to(center) <= radius:
			var sz: Vector3 = mi.mesh.get_aabb().size * mi.global_transform.basis.get_scale()
			var col: String = "?"
			var mat = mi.material_override if mi.material_override != null else mi.get_active_material(0)
			if mat is StandardMaterial3D:
				col = str((mat as StandardMaterial3D).albedo_color)
			var mname: String = mi.mesh.get_class()
			# 只看像"板子"的东西：某个维度特别薄，或者整体大于 1.5m
			if maxf(maxf(sz.x, sz.y), sz.z) > 1.5:
				print("[PROBE] Mesh %s @ %s  size=%s  color=%s  parent=%s(%s)" % [
					mname, str(gp), str(sz.round()), col,
					str(n.get_parent().name), n.get_parent().get_class()])
	elif n is Sprite3D and n.texture != null:
		var gp2: Vector3 = (n as Node3D).global_position
		if gp2.distance_to(center) <= radius:
			var sp: Sprite3D = n
			print("[PROBE] Sprite @ %s  vis=%s scale=%s px=%.5f mod=%s tex=%dx%d parent=%s(%s)" % [
				str(gp2), str(sp.visible), str(sp.scale), sp.pixel_size,
				str(sp.modulate), sp.texture.get_width(), sp.texture.get_height(),
				str(n.get_parent().name), n.get_parent().get_class()])
	elif n is MeshInstance3D and n.mesh is BoxMesh:
		var bx: MeshInstance3D = n
		var bs: Vector3 = bx.mesh.get_aabb().size
		if bs.x > 3.0 and bs.z > 3.0 and bs.y < 0.6:
			print("[PROBE] 平板 @ %s size=%s vis=%s parent=%s(%s)" % [
				str(bx.global_position), str(bs), str(bx.visible),
				str(bx.get_parent().name), bx.get_parent().get_class()])
	for c in n.get_children():
		_scan(c, center, radius)

func _done() -> void:
	MapIO.delete_map(NAME)
	get_tree().quit()
