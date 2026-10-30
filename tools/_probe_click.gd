extends Node
## 点击顿卡探针：注入真实左键/右键事件，逐帧计时找尖峰。
## 用法：godot --path . res://tools/_probe_click.tscn

var _main = null

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(2.5).timeout

	var vp: Viewport = get_viewport()
	var center: Vector2 = vp.get_visible_rect().size * 0.5

	# 1) 基线 60 帧（无交互）
	var base: Array = await _measure_frames(60)

	# 2) 模拟"已选中一队单位"
	var units: Array = GameManager.all_units
	var sel = _main.selection
	var n_sel: int = 0
	for u in units:
		if n_sel >= 10:
			break
		if is_instance_valid(u):
			sel.selected_units.append(u)
			u.set_selected(true)
			n_sel += 1

	# 3) 连续 30 次右键移动指令（真实事件注入）
	var cmd_frames: Array = []
	for i in range(30):
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = true
		ev.position = center + Vector2(randf_range(-250, 250), randf_range(-180, 180))
		vp.push_input(ev, true)
		cmd_frames.append(await _frame_ms())

	# 4) 连续 20 次左键点选（按下+抬起）
	var sel_frames: Array = []
	for i in range(20):
		var dn := InputEventMouseButton.new()
		dn.button_index = MOUSE_BUTTON_LEFT
		dn.pressed = true
		dn.position = center + Vector2(randf_range(-350, 350), randf_range(-250, 250))
		vp.push_input(dn, true)
		sel_frames.append(await _frame_ms())
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.position = dn.position
		vp.push_input(up, true)
		sel_frames.append(await _frame_ms())

	# 5) 强制小地图连画 30 帧测 UI 开销
	var mm_frames: Array = []
	var gui: Node = _main.get_node_or_null("GameUI")
	if gui != null and "_minimap_canvas" in gui and gui._minimap_canvas != null:
		for i in range(30):
			gui._minimap_canvas.queue_redraw()
			mm_frames.append(await _frame_ms())

	print("[CLICK] 基线        avg %.2f ms  max %.2f ms" % [_avg(base), _max(base)])
	print("[CLICK] 右键指令30次 avg %.2f ms  max %.2f ms" % [_avg(cmd_frames), _max(cmd_frames)])
	print("[CLICK] 左键点选40帧 avg %.2f ms  max %.2f ms" % [_avg(sel_frames), _max(sel_frames)])
	if mm_frames.size() > 0:
		print("[CLICK] 小地图30帧  avg %.2f ms  max %.2f ms" % [_avg(mm_frames), _max(mm_frames)])
	_report_spikes("右键指令", cmd_frames)
	_report_spikes("左键点选", sel_frames)
	_report_spikes("小地图", mm_frames)
	get_tree().quit(0)

func _frame_ms() -> float:
	var t0: int = Time.get_ticks_usec()
	await get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0

func _measure_frames(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append(await _frame_ms())
	return out

func _avg(a: Array) -> float:
	var s: float = 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)

func _max(a: Array) -> float:
	var m: float = 0.0
	for v in a:
		m = maxf(m, v)
	return m

func _report_spikes(tag: String, frames: Array) -> void:
	for i in range(frames.size()):
		if frames[i] > 33.0:
			print("[CLICK] ⚠ %s 尖峰 #%d = %.1f ms" % [tag, i, frames[i]])
