extends Node3D
## 探针：找出野马附近"飘在空中"的精灵。
## 用连通域思路不行（那是图片处理），这里直接遍历场景树量每个 Sprite3D 的底边离地高度。

var _main = null
var _t: int = 0

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)

func _process(_d: float) -> void:
	_t += 1
	if _t != 60:
		return
	set_process(false)
	var horse = null
	for h in GameManager.wild_horses:
		if is_instance_valid(h):
			horse = h
			break
	if horse == null:
		print("[PROBE] 没有野马")
		get_tree().quit()
		return
	var hp: Vector3 = horse.global_position
	print("[PROBE] 野马 @ %s" % str(hp))
	_scan(_main, hp, 18.0)
	get_tree().quit()

func _scan(n: Node, center: Vector3, radius: float) -> void:
	if n is Sprite3D:
		var s: Sprite3D = n
		var gp: Vector3 = s.global_position
		if gp.distance_to(center) <= radius:
			var gh: float = Terrain.get_height(gp.x, gp.z)
			var tex_path: String = ""
			if s.texture != null:
				tex_path = s.texture.resource_path
			print("[PROBE] Sprite3D @ %s  离地 %+.2f m  tex=%s  size=%s  parent=%s" % [
				str(gp), gp.y - gh, tex_path,
				str(s.texture.get_size() if s.texture else Vector2.ZERO),
				str(n.get_parent().name if n.get_parent() else "?")])
	for c in n.get_children():
		_scan(c, center, radius)
