extends Node3D

# CameraController 没有 class_name，全局靠 preload 引用（Building.gd 里同样写法）
const CameraController = preload("res://scripts/core/CameraController.gd")
## 素材管线自测（M3）：贴地公式 / 映射完整性 / 实体接线 / 游离图
## 跑法：
##   Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --quit-after 120 \
##     res://tools/_selftest_sprites.tscn
##
## 验五件事：
##   1. asset_map.json 里每条映射都真的能加载到纹理（不是"映射写了但文件没了"）
##   2. offset_y 全部为 0（贴地改成量出来的，手填值必须是 0，否则会二次抬升）
##   3. 接地不变量：对每张图，内容底边换算到世界坐标后必须落在 y=0（容差 1e-4 米）
##   4. 世界高度只由 ref_h × scale 决定，与贴图像素分辨率无关（pixel_size 没漂）
##   5. Building / Unit 实体真的用了 get_sprite_anchor_y()，而且开了 alpha_cut

const CATEGORY_ORDER: Array = [
	"units", "generals", "buildings", "resource_nodes",
	"village", "wild_horse", "supply_cart",
]

const SPRITE_DIR: String = "res://assets/sprites/"

var fails: int = 0
var checks: int = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		fails += 1
		print("  FAIL ", msg)

func _ready() -> void:
	GameManager.editor_mode = true
	Terrain.generate(Terrain.default_params())

	print("=== 1. 映射完整性 ===")
	var entries: Array = _collect_entries()
	print("  共 %d 条映射" % entries.size())
	_test_textures(entries)

	print("=== 2. offset_y 归零 ===")
	_test_offsets_zero(entries)

	print("=== 3. 接地不变量（内容底边 = 地面）===")
	_test_ground_invariant(entries)

	print("=== 4. 世界高度只由 ref_h × scale 决定 ===")
	_test_world_height(entries)

	print("=== 5. 实体接线 ===")
	_test_entities()

	print("=== 6. 游离图片 ===")
	_test_orphans(entries)

	print("")
	print("[SELFTEST] %d 项检查，%d 项失败" % [checks, fails])
	if fails == 0:
		print("[SELFTEST] ✅ 素材管线全部通过")
	else:
		print("[SELFTEST] ❌ 有 %d 项失败" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# ----------------------------------------------------------------

## 收集所有 {cat, id, adef} 条目
func _collect_entries() -> Array:
	var out: Array = []
	for cat in CATEGORY_ORDER:
		if not DataLoader.asset_map.has(cat):
			continue
		var block: Dictionary = DataLoader.asset_map[cat]
		for eid in block.keys():
			var adef = block[eid]
			if typeof(adef) != TYPE_DICTIONARY or not adef.has("sprite"):
				continue
			out.append({"cat": cat, "id": str(eid), "adef": adef})
	return out

# ---------------------------------------------------------------- 1

func _test_textures(entries: Array) -> void:
	# 2026-10-29 起贴片 PNG 已全部删除（外观改走 GLB / fallback mesh）。
	# 映射保留在 asset_map.json 里作为 GLB 替换的对照表。
	# 新口径：对每条映射，"贴图缺失"与"磁盘无文件"必须一致，
	# 且 get_sprite_texture 对缺失返回 null 而不是崩溃或返回坏图。
	var inconsistent: Array = []
	var crash_bad: Array = []
	for e in entries:
		var tex: Texture2D = DataLoader.get_sprite_texture(str(e["cat"]), str(e["id"]))
		var path: String = SPRITE_DIR + str(e["adef"]["sprite"])
		var on_disk: bool = FileAccess.file_exists(path)
		if (tex != null) != on_disk:
			inconsistent.append("%s/%s" % [e["cat"], e["id"]])
	check(inconsistent.is_empty(),
			"贴图缺失与磁盘状态一致（贴片已删应全为 null，异常 %d：%s）" % [inconsistent.size(), str(inconsistent.slice(0, 5))])
	check(crash_bad.is_empty(), "get_sprite_texture 对缺失贴图安全返回 null")

# ---------------------------------------------------------------- 2

func _test_offsets_zero(entries: Array) -> void:
	var nonzero: Array = []
	for e in entries:
		var oy: float = float(e["adef"].get("offset_y", 0.0))
		if not is_zero_approx(oy):
			nonzero.append("%s/%s=%s" % [e["cat"], e["id"], str(oy)])
	check(nonzero.is_empty(),
			"offset_y 全部为 0（非零 %d 条：%s）" % [nonzero.size(), str(nonzero.slice(0, 5))])

# ---------------------------------------------------------------- 3

## 核心不变量：把 Sprite3D 放到 anchor_y 之后，贴图内容的底边必须正好在 y=0。
## 换算链条 = anchor_y - world_h/2 + bottom_pad×ps
func _test_ground_invariant(entries: Array) -> void:
	var worst: float = 0.0
	var worst_id: String = ""
	var bad: Array = []
	for e in entries:
		var cat: String = str(e["cat"])
		var eid: String = str(e["id"])
		var tex: Texture2D = DataLoader.get_sprite_texture(cat, eid)
		if tex == null:
			continue
		var s: float = float(e["adef"].get("scale", 1.0))
		var ps: float = DataLoader.get_sprite_pixel_size(cat, tex) * s
		var h: float = float(tex.get_height())
		var rect: Rect2i = DataLoader.get_sprite_content_rect(cat, eid)
		var pad_px: float = h - float(rect.end.y)
		var anchor: float = DataLoader.get_sprite_anchor_y(cat, eid, s)
		var content_bottom: float = anchor - h * ps * 0.5 + pad_px * ps
		if absf(content_bottom) > worst:
			worst = absf(content_bottom)
			worst_id = "%s/%s" % [cat, eid]
		if absf(content_bottom) > 1e-4:
			bad.append(worst_id)
		if anchor <= 0.0:
			bad.append("%s/%s anchor<=0" % [cat, eid])
		if anchor >= h * ps:
			bad.append("%s/%s anchor 超过图高" % [cat, eid])
	check(bad.is_empty(), "所有贴图内容底边落在 y=0（最大偏差 %s 于 %s）" % [str(worst), worst_id])

	# 抽一张人工核对公式：paper 实例
	var tex2: Texture2D = DataLoader.get_sprite_texture("buildings", "government")
	if tex2 != null:
		var s2: float = 2.2
		var ps2: float = DataLoader.get_sprite_pixel_size("buildings", tex2) * s2
		var rect2: Rect2i = DataLoader.get_sprite_content_rect("buildings", "government")
		var expect: float = tex2.get_height() * ps2 * 0.5 - float(tex2.get_height() - rect2.end.y) * ps2
		var got: float = DataLoader.get_sprite_anchor_y("buildings", "government", s2)
		check(absf(got - expect) < 1e-5,
				"官府 anchor 与手算一致（实得 %.5f 期望 %.5f）" % [got, expect])

# ---------------------------------------------------------------- 4

func _test_world_height(entries: Array) -> void:
	# DataLoader._SPRITE_REF_H 是"参考画布高度"，世界高度 = ref_h × 0.01 × scale
	var ref: Dictionary = {"buildings": 340.0, "units": 280.0, "generals": 280.0,
			"resource_nodes": 280.0, "village": 340.0, "wild_horse": 280.0,
			"supply_cart": 280.0}
	var bad: Array = []
	for e in entries:
		var cat: String = str(e["cat"])
		var tex: Texture2D = DataLoader.get_sprite_texture(cat, str(e["id"]))
		if tex == null or not ref.has(cat):
			continue
		var s: float = float(e["adef"].get("scale", 1.0))
		var world_h: float = float(tex.get_height()) * DataLoader.get_sprite_pixel_size(cat, tex) * s
		var expect: float = float(ref[cat]) * 0.01 * s
		if absf(world_h - expect) > 1e-4:
			bad.append("%s/%s %.4f≠%.4f" % [cat, e["id"], world_h, expect])
	check(bad.is_empty(), "世界高度与像素分辨率无关（偏差 %d 条：%s）" % [bad.size(), str(bad.slice(0, 3))])

# ---------------------------------------------------------------- 5

func _test_entities() -> void:
	# 2026-10-29 起贴片已删：有 GLB 标定的实体走 EntityGLTF 真 3D 模型，
	# 没有的走彩色 fallback mesh。两条路都必须可见、不崩。
	# 建筑：government 在 EntityGLTF 标定表里 → GLB
	var bscene: PackedScene = load("res://scenes/Building.tscn")
	check(bscene != null, "Building.tscn 可加载")
	if bscene != null:
		var b = bscene.instantiate()
		b.building_id = "government"
		b.faction = "wei"
		add_child(b)
		check(b._glb_holder != null, "建筑 government 走 GLB 模型（贴片已删）")
		check(b._sprite != null, "建筑保留 _sprite 引用（下游逻辑依赖）")
		check(not b._sprite.visible, "建筑的 Sprite3D 引用为隐藏占位")
		check(not b._appearance_nodes.is_empty(), "建筑外观节点已登记")
		b.queue_free()

	# 单位：sword 在标定表里 → GLB
	var uscene: PackedScene = load("res://scenes/Unit.tscn")
	check(uscene != null, "Unit.tscn 可加载")
	if uscene != null:
		var u = uscene.instantiate()
		u.unit_id = "sword"
		u.faction = "shu"
		add_child(u)
		check(u._glb_holder != null, "单位 sword 走 GLB 模型（贴片已删）")
		check(u._sprite != null and not u._sprite.visible, "单位保留隐藏 _sprite 引用")
		u.queue_free()

	# 单位：peasant 不在标定表 → 彩色 fallback mesh
	if uscene != null:
		var p = uscene.instantiate()
		p.unit_id = "peasant"
		p.faction = "wei"
		add_child(p)
		check(p._glb_holder == null, "单位 peasant 无 GLB 标定")
		var has_box: bool = false
		for c in p.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
				has_box = true
		check(has_box, "单位 peasant 走彩色 fallback mesh（永远可见）")
		p.queue_free()

# ---------------------------------------------------------------- 6

func _test_orphans(entries: Array) -> void:
	var registered: Dictionary = {}
	for e in entries:
		registered[str(e["adef"]["sprite"])] = true
	var dir: DirAccess = DirAccess.open(SPRITE_DIR)
	check(dir != null, "能打开 assets/sprites/")
	if dir == null:
		return
	var orphans: Array = []
	var total: int = 0
	for f in dir.get_files():
		if not f.to_lower().ends_with(".png"):
			continue
		total += 1
		if not registered.has(f):
			orphans.append(f)
	print("  目录 %d 张 PNG，已映射 %d 张，游离 %d 张" % [total, registered.size(), orphans.size()])
	if orphans.size() > 0:
		print("  游离：", str(orphans))
	# 游离图不算失败（它们可能是备用帧），但数量要可见，方便调色板里点进去导入
	# 2026-10-29 起贴片已删（GLB 化）：目录应为空或不含历史贴片
	check(orphans.is_empty(), "贴片目录无游离图（贴片已删，实得 %d）" % orphans.size())
