class_name MapParams
extends Resource
## 地图生成参数（可被存档/读档/编辑器调参复用）
## 所有字段均有默认值，Terrain.generate() 用这些字段驱动高度场与生物群系。
## 同一组参数 + 同一 seed 必然生成完全相同的地图（可复现、可分享）。

# --- 基础尺寸 ---
@export var seed: int = 20261016
@export var world_size: float = 300.0   # 2026-10-25 用户要求加大：200→300（对战模板按格子数自算，不受影响）
# ⚠️ 256 → 512：用户反馈"地图拼接不够细致"。256² 在 200m 上 = 0.78m/像素，
# 缓坡上会出现一段一段的折面；512² 细一倍，过渡明显更顺（内存代价：RF 图 1MB，可接受）。
@export var heightmap_size: int = 512
@export var biome_size: int = 512
@export var max_height: float = 16.0
@export var water_level: float = -2.0   # 2026-10-25 用户要求：下压见水太深（-5m），改 -2m（平地 1.92m 压 ~4m 出水）

# --- 地形起伏（分形噪声）---
@export var noise_frequency: float = 0.014
@export var noise_octaves: int = 5
@export var moisture_frequency: float = 0.020
@export var rock_frequency: float = 0.025
@export var base_height: float = 0.12          # 整体上抬，避免大面积淹水
# ⚠️ 0.35 → 0.20 → 0.05：用户口径"AoE4 整体是平的，高低只用来区分不让过的区域"。
# 0.05×16m ≈ ±0.8m 微波（AoE4 平地质感）；真正的山体全靠 ridge（山脊噪声）造，
# 山 = 不可通行的天然屏障，平地 = 全部可游玩区。
@export var height_scale: float = 0.05          # 噪声振幅占 max_height 的比例
@export var ridge_scale: float = 0.50           # 山脊额外高度（比例）。0 = 纯圆丘地形，越大山峰越突兀
@export var ridge_frequency: float = 0.021      # 山脊密度（越小山块越大）

# --- 岛屿（四周沉入水下）---
@export var island_radius: float = 130.0
@export var island_center_factor: float = 0.42   # center = world_size * factor（≈玩法中心 84）
@export var island_falloff_inner: float = 0.78   # 此比例内保持陆地
@export var island_falloff_outer: float = 1.05   # 超过此比例沉入水下
@export var ocean_depth: float = -0.90           # 岛外高度（≈ -14m）
@export var edge_falloff: float = 0.105          # 方形边界下沉带占 world_size 的比例（0=关）

# --- 河流 ---
@export var river_count: int = 1
@export var river_width: float = 13.5   # 河谷半宽（米）。太小会让河流变成两壁陡直的"运河"
@export var river_depth: float = 0.90            # 河床下切比例（越大河越深）
@export var river_wind: float = 52.0             # 主蛇形幅度
@export var river_wind2: float = 16.0            # 次蛇形幅度

# --- 湖泊 ---
@export var lake_count: int = 1
@export var lake_radius: float = 22.0
@export var lake_depth: float = 0.85

# --- 平地模式（地图编辑器白纸图）---
# true = 跳过全部噪声/山脊/河流/湖泊/岛屿遮罩：高度恒为 base_height，群系全草地。
# AoE4 式编辑器口径：进场就是一张全平的"白纸"，所有高低都由地形笔刷自己塑。
# 会随 capture_terrain_from/apply_terrain_to 一起存进地图文档，试玩时保持平地。
@export var flat_ground: bool = false

# --- 生物群系密度（1.0 = 默认；>1 更偏向该群系，<1 更稀疏）---
@export var forest_density: float = 1.0
@export var dirt_density: float = 0.55
@export var stone_density: float = 1.0
