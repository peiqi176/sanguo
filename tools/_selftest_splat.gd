extends Node
## 拼图层（splat）自测：笔刷算子 + Terrain 数据层 + MapIO 往返（headless，无需 3D 场景）
##
## 跑法：
##   Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --quit-after 60 \
##     res://tools/_selftest_splat.tscn
##
## 重点验四件容易出错的事：
##   1. 通道隔离：刷"沙地"绝不能碰到"泥土"（RGBA 通道写错就是四层全花）
##   2. 擦除语义：amount 为负时只会把已刷的层减回 0，不会变出负值或污染别的通道
##   3. MapIO 存/读往返：splat.png 落盘再读回来必须逐像素一致
##   4. Terrain.generate() 之后拼图层必须回到全空（换种子不该带着上一张图的笔刷痕迹）

const SplatBrush = preload("res://scripts/mapeditor/SplatBrush.gd")
const UndoStack = preload("res://scripts/mapeditor/UndoStack.gd")
const MapIO = preload("res://scripts/mapformat/MapIO.gd")
const MapDoc = preload("res://scripts/mapformat/MapDoc.gd")

var fails: int = 0
var checks: int = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)

func _make_empty(sz: int) -> Image:
	var img: Image = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	return img

func _ready() -> void:
	print("=== 1. 通道隔离 ===")
	_test_channels()

	print("=== 2. 擦除与边界 ===")
	_test_erase_and_clamp()

	print("=== 3. 撤销（独立栈）===")
	_test_undo()

	print("=== 4. Terrain 数据层 ===")
	_test_terrain_layer()

	print("=== 5. MapIO 往返 ===")
	_test_mapio()

	print("=== 6. 派生工具 ===")
	_test_helpers()

	print("=== 7. 变种笔刷（草种/石板种编码）===")
	_test_variants()

	print("")
	print("[SELFTEST] %d 项检查，%d 项失败" % [checks, fails])
	if fails == 0:
		print("[SELFTEST] ✅ 拼图层全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# ----------------------------------------------------------------

func _test_channels() -> void:
	var img: Image = _make_empty(64)

	# 刷沙地（R）
	SplatBrush.apply(img, Vector2(32.0, 32.0), 8.0, SplatBrush.Layer.SAND, 0.8)
	var c: Color = img.get_pixel(32, 32)
	check(absf(c.r - 0.8) < 0.005, "刷沙地后 R=0.8（实得 %.3f）" % c.r)
	check(c.g == 0.0 and c.b == 0.0 and c.a == 0.0, "其余三个通道不受影响")

	# 刷泥土（G）
	SplatBrush.apply(img, Vector2(32.0, 32.0), 8.0, SplatBrush.Layer.DIRT, 0.5)
	c = img.get_pixel(32, 32)
	check(absf(c.g - 0.5) < 0.005, "刷泥土后 G=0.5（实得 %.3f）" % c.g)
	check(absf(c.r - 0.8) < 0.005, "已有的沙地权重不被泥土笔刷覆盖")

	# 刷岩石（B）、林地（A）
	SplatBrush.apply(img, Vector2(10.0, 10.0), 4.0, SplatBrush.Layer.ROCK, 1.0)
	SplatBrush.apply(img, Vector2(50.0, 50.0), 4.0, SplatBrush.Layer.FOREST, 1.0)
	check(absf(img.get_pixel(10, 10).b - 1.0) < 0.005, "岩石通道写入正确")
	check(absf(img.get_pixel(50, 50).a - 1.0) < 0.005, "林地通道写入正确")

	# 四层全部叠加时总权重超 1 → shader 会归一化，这里只验数据层不越界
	check(c.r <= 1.0 and c.g <= 1.0, "单通道永不越界（<= 1）")

func _test_erase_and_clamp() -> void:
	var img: Image = _make_empty(64)

	# 连续刷 5 次让中心饱和，再擦除
	for i in range(5):
		SplatBrush.apply(img, Vector2(32.0, 32.0), 8.0, SplatBrush.Layer.SAND, 0.4)
	check(img.get_pixel(32, 32).r >= 0.999, "反复刷会饱和到 1.0（实得 %.3f）" % img.get_pixel(32, 32).r)

	var r: Rect2i = SplatBrush.apply(img, Vector2(32.0, 32.0), 8.0, SplatBrush.Layer.SAND, -0.6)
	check(r.size.x > 0, "擦除也返回脏矩形")
	check(img.get_pixel(32, 32).r < 0.5, "擦除让权重下降（实得 %.3f）" % img.get_pixel(32, 32).r)
	check(img.get_pixel(32, 32).r >= 0.0, "擦除不会变负")

	# 擦到 0 之后再擦 → 脏矩形应为空（没有实际变化就不该让撤销入栈）
	SplatBrush.apply(img, Vector2(32.0, 32.0), 8.0, SplatBrush.Layer.SAND, -5.0)
	check(img.get_pixel(32, 32).r == 0.0, "擦干净后为 0")
	var r2: Rect2i = SplatBrush.apply(img, Vector2(32.0, 32.0), 8.0, SplatBrush.Layer.SAND, -0.3)
	check(r2.size.x <= 0, "对空层擦除返回空矩形（不产生假撤销记录）")

	# 一次都没刷过的图，painted_ratio 应为 0
	check(absf(SplatBrush.painted_ratio(_make_empty(32))) < 0.0001, "空图 painted_ratio = 0")

func _test_undo() -> void:
	var img: Image = _make_empty(96)
	var orig: PackedByteArray = img.get_data()

	var us = UndoStack.new()
	us.max_steps = 8

	us.begin(img)
	for i in range(4):
		var cx: float = 30.0 + float(i) * 6.0
		var r: Rect2i = SplatBrush.apply(img, Vector2(cx, 48.0), 7.0, SplatBrush.Layer.DIRT, 0.25)
		us.mark(r)
	var pushed: bool = us.end(img)

	check(pushed, "一次拖动只入栈一条记录")
	check(img.get_data() != orig, "拼图确实被改了")

	var modified: PackedByteArray = img.get_data()
	check(us.undo(img), "undo 返回 true")
	check(img.get_data() == orig, "撤销后逐字节还原（RGBA8 的 blit_rect 有效）")
	check(us.redo(img), "redo 返回 true")
	check(img.get_data() == modified, "重做后逐字节回到修改后状态")

	# 新笔画清空重做链
	us.undo(img)
	us.begin(img)
	var r2: Rect2i = SplatBrush.apply(img, Vector2(10.0, 10.0), 5.0, SplatBrush.Layer.ROCK, 0.3)
	us.mark(r2)
	us.end(img)
	check(not us.can_redo(), "新操作清空重做链")

	# clear_redo：高度/拼图双栈并存的场景下必须能单独清重做。
	# 语义：undo() 把记录从撤销栈挪到重做栈，clear_redo 把重做栈里的这条**永久丢弃**
	#（新笔画入栈后旧重做就必须作废，这是唯一正确的语义）。
	us.undo(img)
	check(us.can_redo(), "撤销后产生重做记录")
	us.clear_redo()
	check(not us.can_redo(), "clear_redo 清掉重做链")
	check(not us.can_undo(), "被撤销的那条记录已随重做链一起作废（不能复活）")

func _test_terrain_layer() -> void:
	# Terrain 是 autoload，headless 下 _ready 已经跑过一次 generate
	var t = Terrain
	t.ensure_splat(128)
	check(t.splat_img != null, "ensure_splat 建出拼图层")
	check(t.splat_img.get_width() == 128, "尺寸生效（实得 %d）" % t.splat_img.get_width())

	# 刷一点 → generate() 换种子 → 手刷痕迹必须被清掉
	# （2026-10-28 起 generate() 会自动修路：splat1 只允许 G=路肩泥、splat2 只允许 R/G=路，
	#   其余通道必须全零 —— 那是生成器写的，不是上一张图的笔刷残留）
	SplatBrush.apply(t.splat_img, Vector2(64.0, 64.0), 10.0, SplatBrush.Layer.SAND, 1.0)
	check(SplatBrush.painted_ratio(t.splat_img) > 0.0, "刷完之后 painted_ratio > 0")

	var p = t.default_params()
	p.seed = 424242
	t.generate(p)
	var leaked: bool = false
	for py in range(0, t.splat_img.get_height(), 7):
		for px in range(0, t.splat_img.get_width(), 7):
			var c: Color = t.splat_img.get_pixel(px, py)
			if c.r > 0.001 or c.b > 0.001 or c.a > 0.001:
				leaked = true
	check(leaked == false,
		"generate() 后沙/岩/林通道全空（不能带着上一张图的笔刷痕迹）")

	# set_splat_image：外部图（含缩放）盖回来，归一化到项目统一的 SPLAT_SIZE
	var src: Image = _make_empty(64)
	src.fill(Color(0.0, 0.5, 0.0, 0.0))
	t.set_splat_image(src)
	check(t.splat_img.get_width() == t.SPLAT_SIZE, "外部图被归一化到项目拼图尺寸 %d（实得 %d）" % [t.SPLAT_SIZE, t.splat_img.get_width()])
	check(absf(t.splat_img.get_pixel(t.splat_img.get_width() / 2, t.splat_img.get_height() / 2).g - 0.5) < 0.02, "外部图的通道值保留（缩放后 G≈0.5）")

	t.splat_clear()
	check(SplatBrush.painted_ratio(t.splat_img) < 0.0001, "splat_clear 清空全部痕迹")

func _test_mapio() -> void:
	var doc = MapDoc.new()
	doc.map_name = "_splat_selftest_map"
	# 清掉上一次跑测试留下的同名地图
	MapIO.delete_map(doc.map_name)

	var splat: Image = _make_empty(32)
	# 左上角刷一片沙地、右下角刷一片岩石，验证往返不串道
	for py in range(4, 10):
		for px in range(4, 10):
			splat.set_pixel(px, py, Color(0.9, 0.0, 0.0, 0.0))
	for py in range(20, 26):
		for px in range(20, 26):
			splat.set_pixel(px, py, Color(0.0, 0.0, 0.7, 0.0))

	var ok: bool = MapIO.save(doc, null, null, splat)
	check(ok, "save（只写拼图层）返回 true")
	check(FileAccess.file_exists("user://maps/_splat_selftest_map/splat.png"), "splat.png 落盘")

	var loaded: Dictionary = MapIO.load_map(doc.map_name)
	check(not loaded.is_empty(), "load_map 返回非空")
	var back: Image = loaded.get("splat", null)
	check(back != null, "读回 splat 图")
	if back != null:
		check(back.get_format() == Image.FORMAT_RGBA8, "读回格式是 RGBA8（实得 %d）" % back.get_format())
		var a: Color = back.get_pixel(6, 6)
		var b: Color = back.get_pixel(22, 22)
		check(absf(a.r - 0.9) < 0.02 and a.b == 0.0, "左上角沙地权重往返一致（%.3f）" % a.r)
		check(absf(b.b - 0.7) < 0.02 and b.r == 0.0, "右下角岩石权重往返一致（%.3f）" % b.b)

	# 全空拼图 → 落盘时应删掉旧文件（不留一张全透明 PNG 制造歧义）
	var empty: Image = _make_empty(32)
	MapIO.save(doc, null, null, empty)
	check(not FileAccess.file_exists("user://maps/_splat_selftest_map/splat.png"),
		"全空拼图不落盘（并清掉旧文件）")
	var loaded2: Dictionary = MapIO.load_map(doc.map_name)
	check(loaded2.get("splat", null) == null, "再读回时 splat 为 null（Terrain 用空图）")

	MapIO.delete_map(doc.map_name)
	check(not MapIO.exists(doc.map_name), "测试地图已清理")

func _test_helpers() -> void:
	var img: Image = _make_empty(32)
	check(SplatBrush.dominant_layer(img, 5, 5) == -1, "空像素的 dominant_layer = -1")
	img.set_pixel(5, 5, Color(0.0, 0.6, 0.0, 0.0))
	check(SplatBrush.dominant_layer(img, 5, 5) == SplatBrush.Layer.DIRT, "泥土占优时返回 DIRT")
	img.set_pixel(5, 5, Color(0.9, 0.1, 0.0, 0.0))
	check(SplatBrush.dominant_layer(img, 5, 5) == SplatBrush.Layer.SAND, "沙地占优时返回 SAND")

	check(SplatBrush.layer_component(SplatBrush.Layer.SAND) == 0, "SAND → R")
	check(SplatBrush.layer_component(SplatBrush.Layer.DIRT) == 1, "DIRT → G")
	check(SplatBrush.layer_component(SplatBrush.Layer.ROCK) == 2, "ROCK → B")
	check(SplatBrush.layer_component(SplatBrush.Layer.FOREST) == 3, "FOREST → A")

## 2026-10-29 变种笔刷：splat2.B = 草种、splat2.A = 石板种的编码与读写
func _test_variants() -> void:
	# 编码往返：idx → 0~1 → RGBA8 一步长内无损
	for idx in range(5):
		var v: float = SplatBrush.encode_variant(idx)
		check(int(round(v * 255.0)) - 1 == idx,
				"encode_variant(%d) 往返一致（实得 %d）" % [idx, int(round(v * 255.0)) - 1])
	check(is_zero_approx(SplatBrush.encode_variant(-1)), "encode_variant(-1) = 0（自动）")

	# 草地变种：画下去 B 写死编码 + 清掉压着草的层
	var i1: Image = _make_empty(32)
	var i2: Image = _make_empty(32)
	i1.set_pixel(16, 16, Color(1.0, 0.5, 0.0, 0.5))          # 假装这里刷过沙地
	i2.set_pixel(16, 16, Color(0.9, 0.0, 0.0, 0.0))          # 假装这里有石板路
	var r: Rect2i = SplatBrush.paint_grass_variant(i1, i2, Vector2(16, 16), 6, 4, 1.0)
	check(r.size.x > 0, "草地变种笔刷返回脏矩形")
	var cg: Color = i2.get_pixel(16, 16)
	check(absf(cg.b - SplatBrush.encode_variant(4)) < 0.005,
			"枯黄草(idx4)编码写进 splat2.B（实得 %.4f）" % cg.b)
	check(cg.r < 0.05, "石板路面权重被草地笔刷清掉（实得 %.3f）" % cg.r)
	var c1: Color = i1.get_pixel(16, 16)
	check(c1.r < 0.05 and c1.g < 0.6, "splat1 沙地权重被草地笔刷清掉（r=%.3f g=%.3f）" % [c1.r, c1.g])

	# 草地"自动"（variant=-1）：把 B 清回 0 恢复噪声分带
	SplatBrush.paint_grass_variant(i1, i2, Vector2(16, 16), 6, -1, 1.0)
	check(i2.get_pixel(16, 16).b == 0.0, "画自动草把 B 清回 0（恢复程序分带）")

	# 草地擦除：负量把 B 淡回 0，不动别的层
	SplatBrush.paint_grass_variant(i1, i2, Vector2(16, 16), 6, 2, 1.0)
	SplatBrush.paint_grass_variant(i1, i2, Vector2(16, 16), 6, 2, -1.0)
	check(i2.get_pixel(16, 16).b < 0.05, "Shift 擦除把草种编码淡回自动")

	# 石板路变种：paint_road 带 variant 时 A 写编码，擦除时 A 清回 0
	var j1: Image = _make_empty(32)
	var j2: Image = _make_empty(32)
	SplatBrush.paint_road(j1, j2, Vector2(16, 16), 8, SplatBrush.Layer.PAVED, 1.0, 1)
	var pa: Color = j2.get_pixel(16, 16)
	check(pa.r > 0.5, "石板路路芯刷上了（r=%.3f）" % pa.r)
	check(absf(pa.a - SplatBrush.encode_variant(1)) < 0.005,
			"大板138(idx1)编码写进 splat2.A（实得 %.4f）" % pa.a)
	SplatBrush.paint_road(j1, j2, Vector2(16, 16), 8, SplatBrush.Layer.PAVED, -1.0, 1)
	check(j2.get_pixel(16, 16).a < 0.05, "擦除道路把石种编码清回自动")
	# 土路不带变种：A 通道不应被碰
	var k1: Image = _make_empty(32)
	var k2: Image = _make_empty(32)
	k2.set_pixel(16, 16, Color(0.0, 0.0, 0.0, SplatBrush.encode_variant(3)))
	SplatBrush.paint_road(k1, k2, Vector2(16, 16), 8, SplatBrush.Layer.ROAD, 1.0)
	check(absf(k2.get_pixel(16, 16).a - SplatBrush.encode_variant(3)) < 0.005,
			"刷土路不碰 A 通道（别处石种编码保留）")
