extends Object
class_name TreeGLTF
## GLB 树模型加载层（2026-10-27）。
## 用户用 Blender 交付了 35 树种 / 109 棵 GLB（res://assets/models/trees/），
## 本类负责：id → 文件映射、统一缩放、随机旋转/高矮抖动、贴地。
##
## id 约定：tree_<树种名>[_v1|_v2][_dead]
##   例：tree_oak / tree_bamboo_v1 / tree_elm_dead_v2
##   缺 _vN 时随机挑一个变种（让森林不呆板）。
## 旧 deco id（tree_0 ~ tree_3）仍走程序树，见 ObjectSpawner.parse_deco_id。

## 全局缩放：模型按真实尺寸做（橡树高 14m / 冠幅 18m），RTS 观感太大
## （一格 2m 时橡树占 9 格），压到约六成——橡树冠 ≈ 5 格，AoE4 同级。
const TREE_SCALE: float = 0.6

## 树种目录：启动时扫一遍 res://assets/models/trees/，缓存可用 id 集合
static var _catalog: Dictionary = {}

## 树种中文名（调色板显示用，与交付说明对照）
const SPECIES_CN: Dictionary = {
	"acacia": "金合欢", "bamboo": "竹丛", "birch": "白桦",
	"cherry_old": "老樱花", "cherry_young": "小樱花", "cypress": "柏树",
	"date_palm": "椰枣棕榈", "doum": "姜果棕", "dove": "榄仁树",
	"elm": "榆树", "gutta": "杜仲", "huangshan_pine": "黄山松",
	"larch": "落叶松", "maple": "枫树", "oak": "橡树",
	"olive_old": "老橄榄", "olive_young": "小橄榄", "saxaul": "梭梭",
	"snowy_cherry": "雪樱", "snowy_maple": "雪枫", "snowy_pine": "雪松",
	"spruce": "云杉", "tall_banyan": "大榕树", "tall_camphor": "大香樟",
	"tall_chinafir": "杉木", "tall_ginkgo": "大银杏", "tall_metasequoia": "水杉",
	"tall_phoenix": "凤凰木", "tall_poplar": "高杨", "tall_redwood": "红杉",
	"tall_sophora": "国槐", "tall_sweetgum": "枫香", "tamarisk": "柽柳",
	"willow": "柳树", "golden_needle": "银针树",
}

## 把 GLB 实例包进一个 Node3D 宿主返回（宿主负责旋转/缩放，GLB 保持原始姿势）。
## 失败返回 null（文件不存在 / 解析失败）。
static func spawn(host: Node3D, species: String, pos: Vector3, rng: RandomNumberGenerator = null) -> Node3D:
	var path: String = pick_variant(species)
	if path.is_empty():
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null

	var glb: Node3D = ps.instantiate()
	var holder := Node3D.new()
	holder.name = "Tree_" + species
	holder.add_child(glb)

	# ---- 缩放：全局系数 × 每棵高矮抖动（同种树不一般齐）----
	var sc := TREE_SCALE
	if rng != null:
		sc *= rng.randf_range(0.88, 1.12)
	holder.scale = Vector3.ONE * sc

	# ---- 随机朝向：森林里每棵树面向不同方向 ----
	if rng != null:
		holder.rotation.y = rng.randf_range(0.0, TAU)

	holder.position = pos
	host.add_child(holder)
	return holder

## 按树种挑一个 GLB：有 _v1/_v2 变种就随机挑；带 _dead 后缀匹配枯树。
## 返回 res:// 路径，树种不存在返回 ""。
static func pick_variant(species: String) -> String:
	ensure_catalog()
	# 精确命中（用户点名某个文件）
	var direct := "res://assets/models/trees/tree_%s.glb" % species
	if _catalog.has(direct):
		return direct
	# 拆出 基名 与 dead 后缀：elm_dead → 基 elm + 枯
	var dead := species.ends_with("_dead")
	var base := species.trim_suffix("_dead")
	var candidates: PackedStringArray = []
	for v in ["", "_v1", "_v2"]:
		var p := "res://assets/models/trees/tree_%s%s.glb" % [base, v]
		if _catalog.has(p):
			candidates.append(p)
	if candidates.is_empty():
		return ""
	if candidates.size() == 1:
		return candidates[0]
	return candidates[randi() % candidates.size()]

## 扫目录建树种目录（key = res 路径）。ResourceLoader.exists 在 --import 前会 false，
## 所以这里用 DirAccess 读磁盘文件名。
static func ensure_catalog() -> void:
	if not _catalog.is_empty():
		return
	var d := DirAccess.open("res://assets/models/trees")
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".glb"):
			_catalog["res://assets/models/trees/" + f] = true

## 树种名列表（编辑器 UI 用）
static func species_list() -> PackedStringArray:
	ensure_catalog()
	var bases := {}
	for p: String in _catalog.keys():
		var f := p.get_file().trim_suffix(".glb").trim_prefix("tree_")
		# 归并变种/枯树到基名：tree_oak_v2 → oak
		f = f.trim_suffix("_v1").trim_suffix("_v2").trim_suffix("_dead")
		bases[f] = true
	var out := PackedStringArray(bases.keys())
	out.sort()
	return out
