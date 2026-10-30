extends Object
class_name EntityGLTF
## 实体 GLB 渲染层（2026-10-29）。
## 贴片（assets/sprites）已按用户要求全部删除；单位/建筑的外观改走真 3D GLB。
## 本类负责：实体ID → GLB 映射、统一缩放（标定值来自 tools/_probe_gltf_aabb.gd 实测）、
## 贴地补偿、固定朝向。没有映射的实体由调用方走原 fallback mesh。
##
## 模型来源：C:\Users\shy\桌面\模型\（用户 Blender/Meshy 交付）。
## meshy 产物带 KHR_mesh_quantization（Godot 不支持），已用 Blender 重导出（*_c.glb）。

## 标定表：key = "类别.实体ID"
##  path    res:// GLB 路径
##  scale   均匀缩放（以"目标实际高度"为准，一格 = 2m）
##  dy      贴地补偿（模型最低点在原点下方时为正，= -min_y × scale）
##  yaw     朝向（度；建筑需对齐等距相机观感，单位先 0）
const MODELS: Dictionary = {
	# ---- 建筑 ----
	"buildings.government": {
		"path": "res://assets/models/entities/guanfu_lod1.glb",
		"scale": 9.9, "dy": 4.455, "yaw": 0.0,   # 0.91m ×9.9 ≈ 9m；min_y=-0.45
	},
	"buildings.gate_stone": {
		"path": "res://assets/models/entities/chengmen.glb",
		"scale": 10.4, "dy": 0.0, "yaw": 0.0,     # 0.67m ×10.4 ≈ 7m；原点贴地
	},
	"buildings.gate_wood": {
		"path": "res://assets/models/entities/chengmen.glb",
		"scale": 10.4, "dy": 0.0, "yaw": 0.0,
	},
	"buildings.barracks_sword": {
		"path": "res://assets/models/entities/daobingying_c.glb",
		"scale": 10.0, "dy": 4.0, "yaw": 0.0,     # 0.80m ×10 ≈ 8m；min_y=-0.40
	},
	"buildings.paifang": {
		"path": "res://assets/models/entities/paifang.glb",
		"scale": 0.6, "dy": 0.036, "yaw": 0.0,    # 13.8m ×0.6 ≈ 8.3m；min_y=-0.06
	},
	# ---- 单位（实拍确认：a/b 均为持长杆枪兵；c 实为红枫树已移入树库）----
	"units.spear": {
		"path": "res://assets/models/entities/shibing_a_c.glb",
		"scale": 1.79, "dy": 0.86, "yaw": 0.0,    # 0.95m ×1.79 ≈ 1.7m；min_y=-0.48
	},
	"units.axeman": {
		"path": "res://assets/models/entities/shibing_b_c.glb",
		"scale": 1.79, "dy": 0.86, "yaw": 0.0,
	},
	"units.sword": {
		# 刀兵模型未交付，暂与枪兵共用 a（拿到刀兵 GLB 后替换）
		"path": "res://assets/models/entities/shibing_a_c.glb",
		"scale": 1.79, "dy": 0.86, "yaw": 0.0,
	},
}

## 已加载的 PackedScene 缓存
static var _scene_cache: Dictionary = {}

## 尝试为实体生成 GLB 外观。成功返回宿主 Node3D（已 add_child 到 host），
## 没有映射或加载失败返回 null（调用方走 fallback mesh）。
static func spawn(cat: String, eid: String, host: Node3D, pos: Vector3) -> Node3D:
	var cfg: Dictionary = MODELS.get(cat + "." + eid, {})
	if cfg.is_empty():
		return null
	var path: String = cfg["path"]
	var ps: PackedScene = _scene_cache.get(path)
	if ps == null:
		if not ResourceLoader.exists(path):
			push_warning("[EntityGLTF] GLB 不存在: " + path)
			return null
		ps = load(path)
		if ps == null:
			return null
		_scene_cache[path] = ps

	var glb: Node3D = ps.instantiate()
	var holder := Node3D.new()
	holder.name = "GLB_" + eid
	holder.add_child(glb)

	var sc: float = float(cfg.get("scale", 1.0))
	holder.scale = Vector3.ONE * sc
	holder.rotation.y = deg_to_rad(float(cfg.get("yaw", 0.0)))
	holder.position = pos + Vector3(0.0, float(cfg.get("dy", 0.0)), 0.0)
	host.add_child(holder)
	return holder

## 诊断：列出标定表里有但磁盘上不存在的 GLB
static func validate() -> PackedStringArray:
	var missing := PackedStringArray()
	for k: String in MODELS:
		var p: String = MODELS[k].get("path", "")
		if p != "" and not ResourceLoader.exists(p):
			missing.append(k + " → " + p)
	return missing
