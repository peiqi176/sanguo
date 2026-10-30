extends Node
## 笔刷 + 撤销栈自测（headless，不需要 3D 场景）
##
## 跑法：
##   Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --quit-after 60 \
##     res://tools/_selftest_brush.tscn
##
## 重点验三件容易出错的事：
##   1. world_to_pixel 的 v 轴是反的（图像第 0 行 = 地图 z 大的一侧），搞反了笔刷会上下镜像
##   2. Image.blit_rect 对 FORMAT_RF 是否真的逐字节还原（撤销靠它）
##   3. 差量撤销的内存是否真的比整图快照小一个量级

const TerrainBrush = preload("res://scripts/mapeditor/TerrainBrush.gd")
const UndoStack = preload("res://scripts/mapeditor/UndoStack.gd")

var fails: int = 0
var checks: int = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)

func _make_flat(sz: int, v: float) -> Image:
	var img: Image = Image.create(sz, sz, false, Image.FORMAT_RF)
	img.fill(Color(v, 0.0, 0.0, 1.0))
	return img

func _ready() -> void:
	print("=== 1. 世界坐标 → 像素映射 ===")
	_test_mapping()

	print("=== 2. 抬升笔刷 ===")
	_test_raise()

	print("=== 3. 撤销 / 重做（逐像素还原）===")
	_test_undo_redo()

	print("=== 4. 差量撤销的内存 ===")
	_test_memory()

	print("")
	print("[SELFTEST] %d 项检查，%d 项失败" % [checks, fails])
	if fails == 0:
		print("[SELFTEST] ✅ 笔刷与撤销全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# ----------------------------------------------------------------

func _test_mapping() -> void:
	var ws: float = 200.0
	var sz: int = 256
	var last: float = float(sz - 1)

	# z = 0 一侧 → 图像最后一行；z = ws 一侧 → 图像第 0 行
	var p_origin_z: Vector2 = TerrainBrush.world_to_pixel(Vector3(0, 0, 0), ws, sz)
	check(absf(p_origin_z.x) < 0.001, "世界 x=0 → px=0")
	check(absf(p_origin_z.y - last) < 0.001, "世界 z=0 → py=末行（v 轴反向）")

	var p_far: Vector2 = TerrainBrush.world_to_pixel(Vector3(ws, 0, ws), ws, sz)
	check(absf(p_far.x - last) < 0.001, "世界 x=ws → px=末列")
	check(absf(p_far.y) < 0.001, "世界 z=ws → py=0（v 轴反向）")

	var p_mid: Vector2 = TerrainBrush.world_to_pixel(Vector3(100, 0, 100), ws, sz)
	check(absf(p_mid.x - last * 0.5) < 0.001, "地图中心 → 像素中心 x")
	check(absf(p_mid.y - last * 0.5) < 0.001, "地图中心 → 像素中心 y")

	# 半径换算：12 米 / 200 米世界 × 255 ≈ 15.3 像素
	var r: float = TerrainBrush.world_radius_to_pixel(12.0, ws, sz)
	check(absf(r - 15.3) < 0.2, "12 米半径 → 约 15.3 像素（实得 %.2f）" % r)
	check(TerrainBrush.world_radius_to_pixel(0.0001, ws, sz) >= 1.0, "极小半径保底 1 像素")

func _test_raise() -> void:
	var sz: int = 128
	var img: Image = _make_flat(sz, 0.0)
	var center: Vector2 = Vector2(64.0, 64.0)
	var radius: float = 10.0

	var rect: Rect2i = TerrainBrush.apply(img, center, radius, 0.1, TerrainBrush.Mode.RAISE, 0.0)

	check(rect.size.x > 0 and rect.size.y > 0, "返回非空脏矩形")
	check(rect.position.x <= 54 and rect.position.x + rect.size.x >= 74, "脏矩形覆盖半径范围")

	var c: float = img.get_pixel(64, 64).r
	check(absf(c - 0.1) < 0.005, "笔刷中心抬到 0.1（实得 %.4f）" % c)

	var outside: float = img.get_pixel(2, 2).r
	check(outside == 0.0, "半径外不受影响")

	# 衰减：中心应该高于半径边缘内侧
	var mid: float = img.get_pixel(64 + 7, 64).r
	check(c > mid and mid > 0.0, "有平滑衰减（中心 %.4f > 内侧 %.4f）" % [c, mid])

	# 下压方向相反
	var img2: Image = _make_flat(sz, 0.5)
	TerrainBrush.apply(img2, center, radius, 0.1, TerrainBrush.Mode.LOWER, 0.0)
	check(img2.get_pixel(64, 64).r < 0.5, "下压让高度变小")

	# clamp：把平坦图刷到超出上限，应该被 H_MAX 夹住
	var img3: Image = _make_flat(sz, TerrainBrush.H_MAX)
	TerrainBrush.apply(img3, center, radius, 5.0, TerrainBrush.Mode.RAISE, 0.0)
	check(img3.get_pixel(64, 64).r <= TerrainBrush.H_MAX + 0.0001, "抬升被 H_MAX 夹住")

	# 平台：目标 0.8，起笔在 0 的图上刷，应逼近 0.8
	var img4: Image = _make_flat(sz, 0.0)
	for i in range(30):
		TerrainBrush.apply(img4, center, radius, 0.5, TerrainBrush.Mode.FLATTEN, 0.8)
	check(absf(img4.get_pixel(64, 64).r - 0.8) < 0.02, "平台笔刷收敛到目标高度（实得 %.4f）" % img4.get_pixel(64, 64).r)

func _test_undo_redo() -> void:
	var sz: int = 96
	var img: Image = _make_flat(sz, 0.25)
	var orig: PackedByteArray = img.get_data()

	var us = UndoStack.new()
	us.max_steps = 8

	# 模拟一次拖动：begin → 多帧 apply+mark → end
	us.begin(img)
	for i in range(5):
		var cx: float = 40.0 + float(i) * 3.0
		var r: Rect2i = TerrainBrush.apply(img, Vector2(cx, 48.0), 8.0, 0.05, TerrainBrush.Mode.RAISE, 0.0)
		us.mark(r)
	var pushed: bool = us.end(img)

	check(pushed, "一次拖动只入栈一条记录")
	check(us.undo_count() == 1, "栈里 1 条（不是每帧一条）")
	check(img.get_data() != orig, "地形确实被改了")

	var modified: PackedByteArray = img.get_data()

	check(us.undo(img), "undo 返回 true")
	check(img.get_data() == orig, "撤销后逐字节还原到原始状态（blit_rect 对 RF 格式有效）")
	check(us.can_redo(), "撤销后可以重做")

	check(us.redo(img), "redo 返回 true")
	check(img.get_data() == modified, "重做后逐字节回到修改后状态")

	# 新操作应截断重做链
	us.undo(img)
	us.begin(img)
	var r2: Rect2i = TerrainBrush.apply(img, Vector2(10.0, 10.0), 6.0, 0.05, TerrainBrush.Mode.RAISE, 0.0)
	us.mark(r2)
	us.end(img)
	check(not us.can_redo(), "新操作会清空重做链")

	# 没有实际改动时不该占栈位
	var before_count: int = us.undo_count()
	us.begin(img)
	us.mark(Rect2i(0, 0, 4, 4))     # 只 mark 不改图
	var pushed_empty: bool = us.end(img)
	check(not pushed_empty and us.undo_count() == before_count, "空笔画不入栈")

func _test_memory() -> void:
	# 512² 的整图 = 1MB；一次 100×100 的笔刷应该只占几十 KB
	var sz: int = 512
	var img: Image = _make_flat(sz, 0.3)
	var full_bytes: int = img.get_data().size()

	var us = UndoStack.new()
	us.begin(img)
	var r: Rect2i = TerrainBrush.apply(img, Vector2(256.0, 256.0), 50.0, 0.02, TerrainBrush.Mode.RAISE, 0.0)
	us.mark(r)
	us.end(img)

	var used: int = us.memory_bytes()
	print("       整图 = %d 字节，一条差量 = %d 字节（%.1f%%）" % [
		full_bytes, used, 100.0 * float(used) / float(full_bytes)])
	check(used > 0, "差量记录非空")
	check(used < full_bytes / 4, "一条撤销记录远小于整图（< 25%）")
