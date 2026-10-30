extends Node3D
var t := 0
func _ready():
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	print("[PLANE] 默认 AABB = ", pm.get_aabb())
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.rotation.x = deg_to_rad(-90)
	add_child(mi)
	print("[PLANE] 旋转-90 后 AABB = ", mi.get_aabb())

	var cam := Camera3D.new()
	cam.position = Vector3(0, 12, 12)
	add_child(cam)
	cam.look_at(Vector3.ZERO)
	cam.make_current()

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.3)
	we.environment = env
	add_child(we)

func _process(_d):
	t += 1
	if t == 10:
		get_viewport().get_texture().get_image().save_png("res://docs/_probe_plane.png")
		print("[PLANE] saved")
		get_tree().quit()
