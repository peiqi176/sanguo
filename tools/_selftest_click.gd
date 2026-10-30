extends Node3D
## 真实点击链路自测：鼠标按下 → _unhandled_input → _screen_to_world → _place_building
##
## 为什么单独立一套：`_selftest_build.gd` 是直接调 `_place_building()`，
## 绕过了「点击到底有没有送达」这一段。用户反馈"点了没反应"，
## 光验证函数能跑通是不够的 —— 必须真的把鼠标事件打进 viewport。

# TerrainPicker 没有 class_name，是 Main 里用 const preload 引的，这里照抄
const TerrainPicker = preload("res://scripts/mapeditor/TerrainPicker.gd")

var _pass: int = 0
var _fail: int = 0
var _main = null
var _t: int = 0
var _n0: int = 0
var _aim_screen: Vector2 = Vector2.ZERO
var _pick: Vector2i = Vector2i.ZERO

func check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("[CLICK] ✅ ", what)
	else:
		_fail += 1
		print("[CLICK] ❌ ", what)

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	# 边缘滚屏在 headless 下会把相机往左上推，先关掉
	var cc = _main.get_node_or_null("CameraController")
	if cc != null:
		cc.edge_scroll = false

func _physics_process(_delta: float) -> void:
	_t += 1
	if _t == 30:
		_prepare()
	elif _t == 34:
		_click()
	elif _t == 44:
		_verify()

func _prepare() -> void:
	var g = GameManager.grid
	_n0 = GameManager.all_buildings.size()
	var gov = null
	for b in GameManager.all_buildings:
		if b.get("building_id") == "government" and str(b.get("faction")) == GameManager.player_faction:
			gov = b
			break
	if gov == null:
		check(false, "找到玩家官府")
		_done()
		return
	# 找一块 3x3 全空的空地，离官府 5~14 格
	var home: Vector2i = g.world_to_grid(gov.global_position)
	var found: bool = false
	for r in range(5, 15):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var p: Vector2i = home + Vector2i(dx, dz)
				if g.is_placeable(p, Vector2i(2, 2)):
					_pick = p
					found = true
					break
			if found:
				break
		if found:
			break
	check(found, "官府附近找到 2x2 空地 %s" % str(_pick))
	if not found:
		_done()
		return

	# 把相机对准目标格，让点击点正好落在屏幕中心
	# （headless 视口是正方形，而相机 FOV 按 16:9 调的，直接 unproject
	#   目标会跑到屏幕最顶上、正好压在 HUD 资源栏底下 → 被 GUI 吃掉）
	var wp: Vector3 = g.grid_to_world(_pick)
	var cc2 = _main.camera_controller
	cc2._target = wp
	cc2._update_camera()
	var cam: Camera3D = cc2.get_node("Camera3D")
	var vp: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	_aim_screen = vp * 0.5
	var back: Vector3 = TerrainPicker.world_from_screen(get_viewport(), _aim_screen)
	print("[CLICK] 屏幕中心反投回世界 = %s (目标 %s)" % [str(back), str(wp)])
	if back != null:
		_pick = g.world_to_grid(back)
	check(_aim_screen.x > 0 and _aim_screen.x < vp.x and _aim_screen.y > 0 and _aim_screen.y < vp.y,
		"目标点在屏幕内 %s (视口 %s)" % [str(_aim_screen), str(vp)])
	print("[CLICK] 目标格 %s  世界 %s  屏幕 %s" % [str(_pick), str(wp), str(_aim_screen)])

	_main.start_build_mode("house")
	check(_main._build_mode == "house", "进入建造模式")

func _click() -> void:
	var vp := get_viewport()
	# 诊断：点之前相机还在原位吗？（headless 下相机每帧都会被 _update_camera 重算）
	var cam: Camera3D = _main.camera_controller.get_node("Camera3D")
	var now_hit = TerrainPicker.world_from_screen(vp, _aim_screen)
	print("[CLICK] 点击前再反投一次 = %s  （相机 pos=%s target=%s）" % [
		str(now_hit), str(cam.global_position), str(_main.camera_controller._target)])
	# 先动一下鼠标，让 ghost 跟上（真实玩家也都是先移动再点）
	var mv := InputEventMouseMotion.new()
	mv.position = _aim_screen
	mv.global_position = _aim_screen
	vp.push_input(mv, true)
	# 左键按下
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = _aim_screen
	ev.global_position = _aim_screen
	vp.push_input(ev, true)
	# 抬起
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = _aim_screen
	up.global_position = _aim_screen
	vp.push_input(up, true)

func _verify() -> void:
	var n1: int = GameManager.all_buildings.size()
	check(n1 == _n0 + 1, "点击后建筑数 %d → %d（应 +1）" % [_n0, n1])
	var placed = null
	for b in GameManager.all_buildings:
		print("[CLICK]   建筑 %s @%s grid=%s progress=%.2f" % [
			str(b.get("building_id")), str(b.global_position),
			str(b.get("grid_pos")), float(b.get("build_progress"))])
		if b.get("building_id") == "house" and float(b.get("build_progress")) < 0.999:
			placed = b
			break
	check(placed != null, "新房子出现在世界且处于建造中")
	if placed != null:
		var gp: Vector2i = placed.get("grid_pos")
		check(gp == _pick, "落点就是鼠标指的那一格 %s == %s" % [str(gp), str(_pick)])
	check(_main._build_mode == "", "放置后自动退出建造模式")
	_done()

func _done() -> void:
	set_physics_process(false)
	print("[SELFTEST] %d 项检查，%d 项失败" % [_pass + _fail, _fail])
	if _fail == 0:
		print("[SELFTEST] ✅ 鼠标点击建造链路全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
