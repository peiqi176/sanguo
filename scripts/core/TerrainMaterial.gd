extends RefCounted
## TerrainMaterial — 地形的唯一材质构建入口
##
## 为什么要有这个文件：
##   游戏主场景 Main.tscn 和地图编辑器 MapEditor.tscn 必须渲染出完全一样的地形，
##   否则"编辑器里调好、进游戏变了"。所以 shader 代码与贴图加载只允许存在一份。
##   2026-10-23 从 Main.gd 抽出，顺带修掉两个历史 Bug：
##     ① shader 的 max_height / water_level 以前读 Terrain 常量，而 get_height() 读 params
##        → 拖动"水面高度"时地形变了、视觉不跟。现在统一只认 Terrain.params。
##     ② _load_terrain_tex() 里加载 PNG 的代码被整段注释，永远返回 2x2 纯色
##        → assets/terrain/ 下 7 张贴图一张没生效。现在真的加载。

## 地形平铺贴图目录（缺图时退回纯色，不会崩）
const TERRAIN_TEX_DIR: String = "res://assets/terrain/"

## 主光角度（度）。Main 里的 DirectionalLight3D 必须用同一个值，
## 否则 shader 里手算的明暗和阴影方向对不上，山体看起来会"两面都是亮的"。
const SUN_EULER_DEG: Vector3 = Vector3(-55.0, 45.0, 0.0)

## 一张地表贴图覆盖多少米。
## ⚠️ 2026-10-25 用户反馈：7m 一张时 Agnes 草贴图的草叶笔触显出 0.5~1m 的大形状，
## 比例全错（后续 3D 模型放上去会显得草比人高）。5m 一张让所有地表特征缩小 30%。
const TILE_METERS: float = 5.0

## 贴图缓存：name -> Texture2D（避免每次建材质都走一遍 load）
static var _tex_cache: Dictionary = {}
## 缺失告警只打一次，避免刷屏
static var _missing_warned: Dictionary = {}

const SHADER_CODE: String = """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D heightmap;   // 数据图：不能加 source_color
uniform sampler2D biome;       // 数据图 R=森林 G=土地 B=石板（不能加 source_color）
uniform sampler2D splat;       // 数据图 R=沙地 G=泥土 B=岩石 A=森林地被（人工笔刷层）
uniform sampler2D splat2;      // 数据图 R=石板路 G=土路（人工笔刷层第二张；B/A 留以后）
uniform float max_height = 16.0;
uniform float world_size = 200.0;
uniform float tile_size = 7.0;    // 一张地表贴图覆盖多少米（越小越"碎"）
uniform float water_level = -2.0;
uniform sampler2D fog_mask : hint_default_white;  // R=已探索 G=当前视野（FogOfWar 写入）
uniform float fog_enabled = 1.0;                  // 0 = 关闭战争迷雾
uniform sampler2D tex_grass : source_color;
uniform sampler2D tex_grass_dry : source_color;   // 草种2：枯黄干草（缺图时绑 grass）
uniform sampler2D tex_grass_lush : source_color;  // 草种3：湿润丰草（缺图时绑 grass）
uniform sampler2D tex_grass_alt1 : source_color;  // 草种4：绿褐野草（缺图时绑 grass）
uniform sampler2D tex_grass_alt2 : source_color;  // 草种5：均匀草坪（缺图时绑 grass）
uniform sampler2D tex_forest : source_color;
uniform sampler2D tex_dirt : source_color;
uniform sampler2D tex_stone : source_color;
uniform sampler2D tex_rock : source_color;
uniform sampler2D tex_rock2 : source_color;       // 岩种2：层状沉积岩崖壁
uniform sampler2D tex_rock3 : source_color;       // 岩种3：碎石砾岩坡面
uniform sampler2D tex_sand : source_color;
uniform sampler2D tex_snow : source_color;
uniform sampler2D tex_paved : source_color;       // 石板路（拼图层4）
uniform sampler2D tex_road_dirt : source_color;   // 土路（拼图层5）
// 石板变种（2026-10-28：用户要求丰富路面、避免满图一张贴图重复）
uniform sampler2D tex_paved_a1 : source_color;    // 131 长苔石板（自动贴路缘）
uniform sampler2D tex_paved_a2 : source_color;    // 138 大块石板
uniform sampler2D tex_paved_a3 : source_color;    // 109 规整灰方石
uniform sampler2D tex_paved_a4 : source_color;    // 111 灰蓝方石
uniform sampler2D tex_paved_a5 : source_color;    // 081 人字铺装
// AoE4 式近景细节层：512² 可平铺灰度图（tools/gen_detail_tex.py 生成），
// ~0.9m 一张乘到 albedo 上，近看有"草叶/碎石"的结构感。缺图时 hint 默认白 = 无效果。
uniform sampler2D tex_detail : hint_default_white;
uniform float detail_tile = 0.6;   // 一张细节贴图覆盖多少米（0.9→0.6：颗粒更细，草叶形状显不出来）
uniform float detail_mix = 0.24;   // 细节层对 albedo 的影响强度（0.40→0.24：用户反馈草叶形状太大太明显）
uniform float debug_gsel = 0.0;    // 诊断：1 = 把草种选择器 gsel 输出成灰度图（用于定阈值）

uniform float slope_rock_start = 0.24;  // 坡度超过此值开始露岩
uniform float slope_rock_full = 0.58;
uniform float macro_strength = 1.0;     // 大尺度色彩变化强度（0 = 关，可用来对比）
uniform float ao_strength = 0.45;       // 山谷/坡脚变暗强度
uniform float detail_strength = 0.17;   // 高频颗粒

// 光照全部交给引擎（NORMAL + DirectionalLight3D + 天空环境光），这里只做材质。

// ---------------------------------------------------------------- 噪声
// 用来做「大尺度色彩变化」。没有它，同一张 7m 贴图平铺整张地图，
// 不管贴图多好都会看出重复的棋盘格；有了它，草原会自然地在暖黄与冷绿之间摆动。
float hash21(vec2 p){
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p){
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ⚠ 2026-10-27 用户反馈"黄色草和绿色草之间一格一格的"——元凶就是这里：
// value noise 的轴对齐插值格 + 每 octave 无旋转，13m 级的方形色块肉眼清晰可辨。
// 修法（业界标准）：每 octave 乘旋转矩阵打散轴对齐 + hash 换更均匀变体 + 4 层倍频。
float fbm2(vec2 p){
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));   // ~37° 旋转（4 标量构造在 Godot shader 会编译失败，用双 vec2 列）
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++){
		v += a * vnoise(p);
		p = rot * p * 2.03 + vec2(11.3, 7.9);
		a *= 0.5;
	}
	return v / 0.9375;
}

// 域扭曲辅助：给"分区噪声"的采样坐标加有机扰动。
// 没有它，单张 fbm 的等值线是一颗颗圆 blob——大片看下来就是"一块地一块地粘贴"。
// 扭曲后每一块的轮廓变成不规则的有机形状，且处处不同（用户口径：每一处都要有随机感）。
vec2 warp2(vec2 p, float amt){
	return p + (vec2(fbm2(p * 0.8 + vec2(3.1, 7.7)), fbm2(p * 0.8 + vec2(9.4, 1.3))) - 0.5) * amt;
}

// ---------------------------------------------------------------- 采样
// 平坦处用水平投影就够；陡坡必须用三向投影，否则贴图会被拉成竖条纹——
// 这是"山看起来像一块抹布"的根本原因（UV 在崖面上被拉长十几倍）。
vec3 flat_samp(sampler2D t, vec2 uvw, float rep){
	vec3 a = texture(t, uvw * rep).rgb;
	vec3 b = texture(t, uvw * rep * 0.371 + vec2(0.61, 0.29)).rgb;
	return mix(a, b, 0.45);
}

vec3 tri_samp(sampler2D t, vec3 wp, vec3 n, float scale){
	vec3 w = pow(abs(n), vec3(3.0)) + vec3(0.001);
	w /= (w.x + w.y + w.z);
	vec3 cx = texture(t, wp.zy * scale).rgb;
	vec3 cy = texture(t, wp.xz * scale).rgb;
	vec3 cz = texture(t, wp.xy * scale).rgb;
	return cx * w.x + cy * w.y + cz * w.z;
}

// 细节层采样：双尺度错位混合防平铺感（与 flat_samp 同思路，但只用 R 通道）
float detail_samp(vec2 wxz){
	vec2 duv = wxz / max(detail_tile, 0.1);
	float a = texture(tex_detail, duv).r;
	float b = texture(tex_detail, duv * 0.371 + vec2(0.61, 0.29)).r;
	return mix(a, b, 0.45);
}

varying vec3 v_world;
varying vec3 v_normal;
varying float v_height;

vec2 uv_of(vec3 local_pos){
	return vec2(local_pos.x / world_size + 0.5, 0.5 - local_pos.z / world_size);
}

float sample_h(vec2 uv){
	return texture(heightmap, uv).r * max_height;
}

void vertex(){
	vec2 uv = uv_of(VERTEX);
	float h = sample_h(uv);
	VERTEX.y += h;

	float e = 1.0 / max(float(textureSize(heightmap, 0).x), 1.0);
	float hL = sample_h(uv - vec2(e, 0.0));
	float hR = sample_h(uv + vec2(e, 0.0));
	float hD = sample_h(uv - vec2(0.0, e));
	float hU = sample_h(uv + vec2(0.0, e));
	float span = 2.0 * e * world_size;
	v_normal = normalize(vec3((hL - hR) / span, 1.0, (hD - hU) / span));

	// 写 NORMAL 交给引擎做光照与阴影。
	NORMAL = v_normal;

	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_height = h;
}

void fragment(){
	// ⚠ 这个公式必须与 uv_of(VERTEX)（顶点位移用）和 TerrainBrush.world_to_pixel（CPU 侧）
	//   完全一致。曾经写成 `x/ws + 0.5` 和 `0.5 - z/ws`，整体偏了半个地图：
	//   靠着纹理 repeat 包裹 + 群系图本身就是噪声，肉眼一直没发现"草色和树对不上"，
	//   直到拼图层（splat）上线——笔刷明明刷在地图中心，颜色却出现在地图角落。
	//   正确的世界→UV：u = x/ws，v = 1 - z/ws（图像第 0 行对应 z = ws 的一侧）。
	vec2 uvw = vec2(v_world.x / world_size, 1.0 - v_world.z / world_size);
	// ---- 群系/拼图层 Domain Warp：有机咬合的过渡边界 ----
	// 直接采 biome/splat 时，草→泥的交界是一圈平滑渐变，一眼"程序生成"。
	// 对采样坐标加 ±1.6m 的噪声扰动，过渡带变成锯齿状互相咬合——AoE4 的交界质感。
	// ⚠ 只 warp 群系/拼层采样；uvw 本身还要给 heightmap AO 和战争迷雾用，必须保持精确对齐。
	vec2 uvb = uvw + (vec2(
		fbm2(v_world.xz * 0.055 + vec2(3.1, 7.7)),
		fbm2(v_world.xz * 0.055 + vec2(9.4, 1.3))) - 0.5) * 0.016;
	vec4 bw = texture(biome, uvb);
	float forestW = bw.r;
	float dirtW = bw.g;
	float stoneW = bw.b;

	float rep = world_size / max(tile_size, 1.0);
	vec3 grass  = flat_samp(tex_grass,  uvw, rep);
	vec3 forest = flat_samp(tex_forest, uvw, rep);
	vec3 dirt   = flat_samp(tex_dirt,   uvw, rep);
	vec3 stone  = flat_samp(tex_stone,  uvw, rep);
	vec3 sand   = flat_samp(tex_sand,   uvw, rep * 0.8);
	vec3 snow   = flat_samp(tex_snow,   uvw, rep * 0.8);
	// 岩石走三向投影：它在陡坡上最显眼，也是拉伸最严重的一层
	vec3 rock   = tri_samp(tex_rock, v_world, v_normal, 1.0 / max(tile_size, 1.0) * 1.35);

	// ---- 草地五变种（丰草/草坪/野草/枯黄）：低频分区 + 域扭曲 + 高频打散 ----
	// 用户口径"草地要多种"：基底 Grass006，按 gsel 分四段带状混入
	// 丰茂 Grass005 / 均匀草坪 Grass008 / 绿褐野草 Grass007 / 枯黄 Grass004。
	//   ① 采样坐标先过 ±5.5m 域扭曲（每块轮廓有机化、不重样）
	//   ② 叠两层高频噪声（把分界线打碎成犬牙交错的细碎过渡）
	float gsel_dbg = 0.5;   // 诊断用（debug_gsel=1 时输出）
	float wd_dbg = 0.0; float wmid_dbg = 0.0; float wl_dbg = 0.0;
	{
		vec3 g_lush = flat_samp(tex_grass_lush, uvw, rep);
		vec3 g_alt2 = flat_samp(tex_grass_alt2, uvw, rep);
		vec3 g_alt1 = flat_samp(tex_grass_alt1, uvw, rep);
		vec3 g_dry  = flat_samp(tex_grass_dry,  uvw, rep);
		vec2 gp = warp2(v_world.xz, 11.0);
		float gsel = fbm2(gp * 0.045)
			+ (fbm2(gp * 0.21) - 0.5) * 0.55
			+ (fbm2(gp * 0.85) - 0.5) * 0.30;
		// 2026-10-29 编辑器手动指定草种：splat2.B 编码变种（0=自动噪声分带，
		// (idx+1)/255 = 第 idx 种）。编码直接读原始 splat2（不能读带抖动的 sw2，
		// 边界抖动 ±0.13 会把 idx 搞串）。gsel 落点 = 各分带阈值的"满权重中点"。
		float gover = texture(splat2, uvb).b;
		if (gover > 0.004) {
			int gidx = int(round(gover * 255.0)) - 1;
			if (gidx == 0) { gsel = 0.15; }        // 0 丰茂草（Grass005，gsel<0.24 满权重）
			else if (gidx == 1) { gsel = 0.42; }   // 1 常绿草基底（Grass006，0.36~0.46 空档）
			else if (gidx == 2) { gsel = 0.55; }   // 2 草坪（Grass008，0.54~0.58）
			else if (gidx == 3) { gsel = 0.67; }   // 3 野草（Grass007，0.64~0.70）
			else if (gidx == 4) { gsel = 0.90; }   // 4 枯黄草（Grass004，>0.78）
		}
		gsel_dbg = gsel;
		// 阈值按 Python 复刻噪声实测的真分布定（p25=0.37 / p50=0.48 / p75=0.59 / p95=0.74）：
		// 丰草 ~15% / 基底 ~30% / 草坪 ~25% / 野草 ~18% / 枯黄 ~10%
		float wL = 1.0 - smoothstep(0.24, 0.36, gsel);                              // 丰草带
		float w8 = smoothstep(0.46, 0.54, gsel) * (1.0 - smoothstep(0.58, 0.64, gsel)); // 草坪带
		float w7 = smoothstep(0.58, 0.64, gsel) * (1.0 - smoothstep(0.70, 0.78, gsel)); // 野草带
		float wD = smoothstep(0.70, 0.78, gsel);                                    // 枯黄带（过渡放宽去硬边）
		grass = mix(grass, g_lush, wL);
		grass = mix(grass, g_alt2, w8);
		grass = mix(grass, g_alt1, w7);
		grass = mix(grass, g_dry,  wD);
		wd_dbg = wD; wmid_dbg = max(w8, w7); wl_dbg = wL;
	}

	// ---- 岩壁三变种（层状岩/碎石岩）：断层参考 AoE4/傲世三国的分层崖面 ----
	// 用另一组独立噪声分区，和草区的噪声错开（同一噪声会让"枯草坡+层状岩"绑死出现）；
	// 同样过域扭曲 + 高频打散，崖面的岩种分布才不会是几颗规则的圆斑。
	{
		vec2 rp = warp2(v_world.xz + vec2(37.0, 91.0), 9.0);
		float rsel = fbm2(rp * 0.035)
			+ (fbm2(rp * 0.18) - 0.5) * 0.50
			+ (fbm2(rp * 0.72) - 0.5) * 0.28;
		vec3 rk2 = tri_samp(tex_rock2, v_world, v_normal, 1.0 / max(tile_size, 1.0) * 1.35);
		vec3 rk3 = tri_samp(tex_rock3, v_world, v_normal, 1.0 / max(tile_size, 1.0) * 1.35);
		float r2w = smoothstep(0.54, 0.68, rsel);
		float r3w = 1.0 - smoothstep(0.40, 0.54, rsel);
		rock = mix(rock, rk2, r2w);
		rock = mix(rock, rk3, r3w);
	}

	float dn = hash21(floor(v_world.xz * 0.6));
	float jit = (dn - 0.5) * 0.16;

	vec3 col = grass;
	col = mix(col, forest, clamp(forestW + jit, 0.0, 1.0));
	col = mix(col, dirt,   clamp(dirtW   + jit, 0.0, 1.0));
	col = mix(col, stone,  clamp(stoneW  + jit, 0.0, 1.0));

	// ---- 坡度 → 露岩 ----
	float slope = 1.0 - clamp(v_normal.y, 0.0, 1.0);
	float rockW = smoothstep(slope_rock_start, slope_rock_full, slope);
	// 岩层：世界 Y 上的条带 + 噪声扰动 → 崖面上一道道横向岩层
	float band = sin(v_world.y * 1.9 + fbm2(v_world.xz * 0.28) * 3.4);
	vec3 rock_c = rock * (1.0 + 0.13 * band);
	col = mix(col, rock_c, rockW);

	// ---- 人工拼图层（沙地 / 泥土 / 岩石 / 森林地被）----
	// 放在"坡度露岩"之后、"雪与沙滩"之前，理由是：
	//   · 放最后会被雪和水边沙滩盖掉 —— 玩家在河湾刷了一片沙洲，结果全被
	//     沙滩规则重算成同一种沙，等于白刷；
	//   · 放进 biome 那一层又会被坡度露岩吃掉 —— 在崖脚刷一圈裸岩，反而看不见。
	// 折中位置 = 人工痕迹盖过"程序群系"，但仍服从"高海拔积雪 / 水边湿沙"的物理规则。
	{
		vec4 sp = texture(splat, uvb);
		// 边界抖动：笔刷是圆的，而地表材质的边界应该是软的、碎的。
		// 叠两级噪声（1.15 m 级 + 4.3 m 级）把圆形污染成不规则形状，
		// 否则手刷的每一笔都是一块肉眼可辨的"圆饼"。
		float sj = (vnoise(v_world.xz * 1.15) - 0.5) * 0.30
			+ (vnoise(v_world.xz * 4.30) - 0.5) * 0.14;
		vec4 sw = clamp(sp + sj * vec4(1.0), 0.0, 1.0);
		// 只保留"有料"的通道：噪声抖动会把 0 抬成 0.15，不掐掉就会满地薄薄一层脏色
		sw *= step(vec4(0.02), sp);
		float stot = sw.r + sw.g + sw.b + sw.a;
		// 超过 1 才归一化 —— 保证四个层叠加永远不"越刷越白"，
		// 但只刷了一层 30% 时仍然只覆盖 30%（不会被硬拉成 100%）
		sw /= max(stot, 1.0);
		vec3 splat_c = sand * sw.r + dirt * sw.g + rock_c * sw.b + forest * sw.a;
		float sw_sum = min(stot, 1.0);
		// 手刷层的质感：给一层轻微的自阴影，让它"贴"在地面上而不是浮在表面
		splat_c *= 0.94 + 0.12 * vnoise(v_world.xz * 3.1);
		col = mix(col, splat_c, sw_sum);
	}

	// ---- 峰顶雪 ----
	// 2026-10-25：雪线 0.80→0.92。原来 12.8m 就积雪，编辑器堆的山全被雪盖住、
	// 岩壁根本看不见；AoE4 只有极高峰才雪顶。现在 ~14.7m 起雪、绝对峰顶也只是薄雪。
	float hN = clamp(v_height / max_height, -1.0, 1.0);
	col = mix(col, snow, smoothstep(0.92, 1.10, hN) * 0.75);

	// ---- 水边沙滩 ----
	col = mix(col, sand, smoothstep(water_level + 1.35, water_level + 0.25, v_height) * 0.92);
	// ---- 水下压暗：水位提高(-2m)后小水坑的亮沙底会把浅水衬成"白饼"，
	// 按水深把河床压暗，浅水才能读出"水"而不是"沙"。
	// 0.50/2.0 → 0.34/1.2：常见坑深只有 0.5m，除以 2.0 时几乎没压到，实测仍发白 ----
	col *= mix(1.0, 0.34, clamp((water_level - v_height) / 1.2, 0.0, 1.0));

	// ---- 人工道路层（石板路 / 土路）——最高优先级的人工痕迹 ----
	// 放在雪与水边沙**之后**：路是人修的，不该被积雪或河滩沙"重新计算"掉。
	// 2026-10-25 用户反馈：石板太大太离谱、边缘生硬。三处修正：
	//   ① 路面贴图采样频率 ×1.6（石块只有拳头大）；
	//   ② 边界抖动减半（路边轮廓更干净利落）；
	//   ③ 路缘加"踩秃的土肩"：权重过渡带混入泥土色，硬边变自然磨损过渡（AoE4 同款）。
	{
		vec4 sp2 = texture(splat2, uvb);
		// 边界抖动与 splat1 同款但更收敛：路是人工物，轮廓要比自然地被利落
		float sj2 = (vnoise(v_world.xz * 1.15) - 0.5) * 0.16
			+ (vnoise(v_world.xz * 4.30) - 0.5) * 0.10;
		vec4 sw2 = clamp(sp2 + sj2 * vec4(1.0), 0.0, 1.0);
		sw2 *= step(vec4(0.02), sp2);
		// 只用 R/G 两通道
		float ptot = sw2.r + sw2.g;
		sw2 /= max(ptot, 1.0);
		if (ptot > 0.001) {
			float w_road = min(ptot, 1.0);
			// 2026-10-28 缩放口径（用户：1 格 = 2m）：070 系一张贴图约 9.5 块石，
			// 周期 8.5m → 单石 ~0.9m，古城石板路尺度。131 苔石 / 138 大板石头更大，周期更短。
			float rs0 = 1.0 / 8.5;   // 070 / 109 / 111 / 081 细密方石
			float rs1 = 1.0 / 6.0;   // 131 苔石
			float rs2 = 1.0 / 5.0;   // 138 大块石板
			// 多种石板按世界噪声分带：不同路段铺不同的石头，打破单一贴图的平铺重复
			vec2 pp = warp2(v_world.xz, 6.0);
			float psel = fbm2(pp * 0.07) + (fbm2(v_world.xz * 0.35) - 0.5) * 0.5;
			// 2026-10-29 编辑器手动指定石板种：splat2.A 编码变种（0=自动噪声分带，
			// (idx+1)/255 = 第 idx 种）。psel 落点 = 各分带的满权重中点。
			float pover = sp2.a;
			if (pover > 0.004) {
				int pidx = int(round(pover * 255.0)) - 1;
				if (pidx == 0) { psel = 0.10; }        // 0 070 基底方石（<0.28 无变种混入）
				else if (pidx == 1) { psel = 0.40; }   // 1 138 大板（0.36~0.44）
				else if (pidx == 2) { psel = 0.62; }   // 2 109 规整方石（0.60~0.68）
				else if (pidx == 3) { psel = 0.78; }   // 3 111 灰蓝方石（0.76~0.80）
				else if (pidx == 4) { psel = 0.95; }   // 4 081 人字铺（>0.88）
			}
			float e = smoothstep(0.04, 0.30, ptot);   // 0=路缘 1=路芯
			vec3 paved_c = tri_samp(tex_paved, v_world, v_normal, rs0);          // 070 基底
			paved_c = mix(paved_c, tri_samp(tex_paved_a2, v_world, v_normal, rs2),
				smoothstep(0.28, 0.36, psel) * (1.0 - smoothstep(0.44, 0.52, psel)));   // 138 大板
			paved_c = mix(paved_c, tri_samp(tex_paved_a3, v_world, v_normal, rs0),
				smoothstep(0.52, 0.60, psel) * (1.0 - smoothstep(0.68, 0.76, psel)));   // 109 方石
			paved_c = mix(paved_c, tri_samp(tex_paved_a4, v_world, v_normal, rs0),
				smoothstep(0.68, 0.76, psel) * (1.0 - smoothstep(0.80, 0.88, psel)));   // 111
			paved_c = mix(paved_c, tri_samp(tex_paved_a5, v_world, v_normal, rs0),
				smoothstep(0.80, 0.88, psel));                                          // 081 人字
			// 131 苔石：贴路缘更容易长苔（老路面外侧长苔是自然现象）
			paved_c = mix(paved_c, tri_samp(tex_paved_a1, v_world, v_normal, rs1), (1.0 - e) * 0.75);
			vec3 road_c  = tri_samp(tex_road_dirt, v_world, v_normal, rs0);
			vec3 road_mix = paved_c * sw2.r + road_c * sw2.g;
			road_mix *= 0.94 + 0.12 * vnoise(v_world.xz * 3.1);
			// 路缘土肩：2026-10-27 起路肩过渡由笔刷真实画进 splat1（SplatBrush.paint_road，
			// 泥土权重带斑块淡出）。这里只保留一小段"路芯边缘"的柔化，强度 0.7→0.4，
			// 否则和笔刷画的路肩叠加会把过渡带糊得过宽。
			float shoulder = smoothstep(0.03, 0.22, ptot) * (1.0 - smoothstep(0.30, 0.70, ptot));
			road_mix = mix(road_mix, dirt * 0.95, shoulder * 0.4);
			col = mix(col, road_mix, w_road);
		}
	}

	// ---- 大尺度色彩变化（打散平铺重复感 + 制造 AoE4 那种"地块"层次）----
	float m1 = fbm2(v_world.xz * 0.0105);   // ~90m 尺度：整片草原冷暖摆动
	// m2 也过域扭曲：地块级明暗如果保持圆 blob，就是"一块亮一块暗"的粘贴感来源之一
	float m2 = fbm2(warp2(v_world.xz, 7.0) * 0.075);   // ~13m 尺度：地块级明暗（有机轮廓）
	float m3 = fbm2(v_world.xz * 0.19);     // ~5m  尺度：脚下颗粒
	float m4 = fbm2(v_world.xz * 1.35);     // ~0.7m 尺度：真正让近景不"塑料"的一层

	vec3 warm = vec3(1.075, 1.025, 0.860);  // 偏黄（干草、日照）
	vec3 cool = vec3(0.905, 0.995, 1.045);  // 偏青（湿润、背光）
	vec3 tint = mix(cool, warm, smoothstep(0.32, 0.70, m1));


	// 地块级明暗：让草原有"这块亮、那块暗"的呼吸感



	// ---- 便宜但有效的 AO：周围比中心高 → 这里是凹地/坡脚 → 压暗 ----
	// 只采 4 点，代价很低，但山谷和崖脚的体积感全靠它。
	float ao_r = 2.6 / world_size;
	float hn = (sample_h(uvw + vec2(ao_r, 0.0)) + sample_h(uvw - vec2(ao_r, 0.0))
		+ sample_h(uvw + vec2(0.0, ao_r)) + sample_h(uvw - vec2(0.0, ao_r))) * 0.25;
	float occl = clamp((hn - v_height) * 0.45, 0.0, 1.0);
	col *= 1.0 - occl * ao_strength;

	// ---- 高频颗粒 ----
	// 近景"像塑料"就是因为缺这一层：7m 一张的贴图在 34m 视距下已经摊得很开，
	// 只剩低频色块，眼睛读到的是"一块纯色"。



	// ---- AoE4 式细节纹理层：真实像素级结构乘上去 ----
	// 上面的 m3/m4 是程序噪声，只有"明暗颗粒"没有"形状"；
	// 这层是真正的纹理像素（草叶/碎石感，gen_detail_tex.py 生成），
	// det 均值 0.48，×2 ≈ 1.0 中性 → 亮处提亮、暗处压暗，是乘法不是加脏色。



	// ---- 微观法线：让阳光在"地面碎起伏"上打出明暗 ----
	// 只改 ALBEDO 是没用的：一片完全平的面被均匀照亮，加多少噪声都像脏了。
	// 真正常见的地面细节（草叶、碎石、土块）本质是**法线扰动**，
	// 斜射的主光会在上面扫出小片明暗——这才是"有质感"的来源。
	{
		// ① 细节纹理梯度法线：从 detail 贴图本身求梯度——真实的"草叶"结构，
		//    阳光扫过时会出现顺着纹理走向的明暗，而不是噪声的均匀碎点。
		//    缺图兜底（hint 白图）时梯度=0，gs=0，自动退回第②层。
		float flat_k = 1.0 - clamp(slope * 2.2, 0.0, 1.0);
		vec2 duv = v_world.xz / max(detail_tile, 0.1);
		float e = 1.5 / 512.0;
		float h0 = texture(tex_detail, duv).r;
		float hx = texture(tex_detail, duv + vec2(e, 0.0)).r;
		float hz = texture(tex_detail, duv + vec2(0.0, e)).r;
		vec3 mg = vec3(-(hx - h0) * 20.0, 1.0, -(hz - h0) * 20.0);
		float gs = clamp(length(mg.xz) * 3.0, 0.0, 1.0);
		// ② 程序噪声粗颗粒（比 detail 贴图更粗一档的碎起伏，保留）
		vec2 duv2 = v_world.xz * 2.6;
		float e2 = 0.045;
		float n0 = vnoise(duv2);
		float nx = vnoise(duv2 + vec2(e2, 0.0));
		float nz = vnoise(duv2 + vec2(0.0, e2));
		vec3 micro2 = normalize(vec3(-(nx - n0) * 18.0, 1.0, -(nz - n0) * 18.0));
		vec3 micro = normalize(mix(micro2, mg, gs));
		vec3 micro_view = normalize((VIEW_MATRIX * vec4(micro, 0.0)).xyz);
		NORMAL = normalize(mix(NORMAL, micro_view, 0.60 * flat_k));
	}

	// 饱和度微调：贴图本身偏灰，提一点色彩（照明交给引擎，这里只动材质色）
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, 1.08);

	// ---- 战争迷雾：未探索≈全黑，探索过压暗，当前视野全亮 ----
	if (fog_enabled > 0.5) {
		vec4 fv = texture(fog_mask, uvw);
		float dark = mix(0.035, 0.62, fv.r);
		dark = mix(dark, 1.0, fv.g);
		col *= dark;
	}

	ALBEDO = clamp(col, 0.0, 1.0);
	// DEBUG: gsel 灰度诊断（黑=丰草带 … 白=枯黄带）
	if (debug_gsel > 0.5) {
		ALBEDO = vec3(clamp(gsel_dbg, 0.0, 1.0));
	}
	if (debug_gsel > 1.5) {
		ALBEDO = vec3(clamp(wd_dbg,0.0,1.0), clamp(wmid_dbg,0.0,1.0), clamp(wl_dbg,0.0,1.0));
	}
	// DEBUG: 显示 splat1 DIRT 权重（绿=高），必须放在原 ALBEDO 之后才能覆盖
	ROUGHNESS = 0.96;
	METALLIC = 0.0;
	SPECULAR = 0.10;
}
"""

## 加载一张地形平铺贴图。失败时返回 fallback 纯色（并只告警一次）。
static func load_terrain_tex(tex_name: String, fallback: Color) -> Texture2D:
	if _tex_cache.has(tex_name):
		return _tex_cache[tex_name]
	var path: String = TERRAIN_TEX_DIR + tex_name + ".png"
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path) as Texture2D
		if t != null:
			_tex_cache[tex_name] = t
			return t
	if not _missing_warned.has(tex_name):
		_missing_warned[tex_name] = true
		print("[TerrainMaterial] 缺少地形贴图 " + tex_name + ".png → 用纯色占位")
	var solid: ImageTexture = _make_solid_tex(fallback)
	_tex_cache[tex_name] = solid
	return solid

static func _make_solid_tex(c: Color) -> ImageTexture:
	var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

## 「什么都没刷」的拼图层：全 0（RGBA 都是 0），shader 侧权重和 = 0 → 完全不参与混合
static func _empty_splat_tex() -> ImageTexture:
	if _tex_cache.has("__empty_splat"):
		return _tex_cache["__empty_splat"]
	var t: ImageTexture = _make_solid_tex(Color(0.0, 0.0, 0.0, 0.0))
	_tex_cache["__empty_splat"] = t
	return t

## 构建地形材质。数据全部从 Terrain autoload 取，保证与 get_height() 同源。
static func build() -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = SHADER_CODE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader

	var p = Terrain.params
	var ws: float = p.world_size if p != null else Terrain.WORLD_SIZE
	var mh: float = p.max_height if p != null else Terrain.MAX_HEIGHT
	var wl: float = p.water_level if p != null else Terrain.WATER_LEVEL

	mat.set_shader_parameter("heightmap", Terrain.heightmap_tex)
	mat.set_shader_parameter("biome", Terrain.biome_tex)
	# ⚠️ splat 纹理不能传 null：GLSL 里未绑定的 sampler2D 采样出来是纯白，
	#    R/G/B/A 全 1 会被拼图层解释成"整张地图都刷满了四层材质"，地面立刻糊掉。
	#    所以拿不到纹理时绑一张 1×1 全透明图当"什么都没刷"。
	if Terrain.splat_tex != null:
		mat.set_shader_parameter("splat", Terrain.splat_tex)
	else:
		mat.set_shader_parameter("splat", _empty_splat_tex())
	# 第二张拼图（石板路/土路）：没有就绑"什么都没刷"
	if Terrain.splat2_tex != null:
		mat.set_shader_parameter("splat2", Terrain.splat2_tex)
	else:
		mat.set_shader_parameter("splat2", _empty_splat_tex())
	mat.set_shader_parameter("max_height", mh)
	mat.set_shader_parameter("water_level", wl)
	mat.set_shader_parameter("world_size", ws)
	mat.set_shader_parameter("tile_size", TILE_METERS)

	mat.set_shader_parameter("tex_grass",  load_terrain_tex("grass",  Color(0.38, 0.50, 0.24)))
	# 森林地被：优先用"高草+落叶"版（用户口径：森林的地面要高草和落叶，不需要单独建模
	# —— 落叶直接画进贴图，AoE4 同款做法）；缺图退回老的深色苔藓 forest。
	var _fg_path: String = ProjectSettings.globalize_path(TERRAIN_TEX_DIR + "forest_grass.png")
	if FileAccess.file_exists(_fg_path):
		mat.set_shader_parameter("tex_forest", load_terrain_tex("forest_grass", Color(0.26, 0.38, 0.20)))
	else:
		mat.set_shader_parameter("tex_forest", load_terrain_tex("forest", Color(0.26, 0.38, 0.20)))
	mat.set_shader_parameter("tex_dirt",   load_terrain_tex("dirt",   Color(0.46, 0.37, 0.25)))
	mat.set_shader_parameter("tex_stone",  load_terrain_tex("stone",  Color(0.55, 0.55, 0.58)))
	mat.set_shader_parameter("tex_rock",   load_terrain_tex("rock",   Color(0.43, 0.43, 0.46)))
	mat.set_shader_parameter("tex_sand",   load_terrain_tex("sand",   Color(0.76, 0.70, 0.50)))
	mat.set_shader_parameter("tex_snow",   load_terrain_tex("snow",   Color(0.92, 0.94, 0.97)))
	# 变种/道路贴图：缺图时绑同家族的已有贴图（枯草缺→普通草、层状岩缺→原岩），
	# 保证"没生成新图 = 画面和从前完全一样"，绝不会出现纯色补丁。
	mat.set_shader_parameter("tex_grass_dry",  load_terrain_tex("grass_dry",  Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_grass_lush", load_terrain_tex("grass_lush", Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_grass_alt1", load_terrain_tex("grass_alt1", Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_grass_alt2", load_terrain_tex("grass_alt2", Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_rock2",      load_terrain_tex("rock2",      Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_rock3",      load_terrain_tex("rock3",      Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_paved",      load_terrain_tex("paved",      Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_paved_a1",   load_terrain_tex("paved_a1",   Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_paved_a2",   load_terrain_tex("paved_a2",   Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_paved_a3",   load_terrain_tex("paved_a3",   Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_paved_a4",   load_terrain_tex("paved_a4",   Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_paved_a5",   load_terrain_tex("paved_a5",   Color(0.0, 0.0, 0.0)))
	mat.set_shader_parameter("tex_road_dirt",  load_terrain_tex("road_dirt",  Color(0.0, 0.0, 0.0)))
	_fix_missing_variants(mat)
	# 细节层（缺图时 fallback 中性灰 0.5 → 梯度 0 → 无效果，不会崩也不会变脏）
	mat.set_shader_parameter("tex_detail", load_terrain_tex("detail", Color(0.5, 0.5, 0.5)))

	# 雾随地图尺寸放大（大地图看全）
	var far_v: float = clampf(ws * 2.2, 320.0, 1200.0)
	mat.set_shader_parameter("fog_near", far_v * 0.32)
	mat.set_shader_parameter("fog_far", far_v)
	return mat

## 变种贴图缺图兜底：绑回同家族的已有贴图。
## load_terrain_tex 对缺失图返回 2×2 纯色（黑），直接用会把枯草区/崖面涂成黑块 ——
## 这里在材质组装后统一把"纯色兜底"的 uniform 换成家族正主，缺图 = 无变化。
static func _fix_missing_variants(mat: ShaderMaterial) -> void:
	var pairs := {
		"tex_grass_dry": "tex_grass",
		"tex_grass_lush": "tex_grass",
		"tex_grass_alt1": "tex_grass",
		"tex_grass_alt2": "tex_grass",
		"tex_rock2": "tex_rock",
		"tex_rock3": "tex_rock",
		"tex_paved": "tex_stone",
		"tex_paved_a1": "tex_paved",
		"tex_paved_a2": "tex_paved",
		"tex_paved_a3": "tex_paved",
		"tex_paved_a4": "tex_paved",
		"tex_paved_a5": "tex_paved",
		"tex_road_dirt": "tex_dirt",
	}
	var assets_dir: String = ProjectSettings.globalize_path(TERRAIN_TEX_DIR)
	for var_name in pairs.keys():
		var tex_name: String = var_name.trim_prefix("tex_")
		if not FileAccess.file_exists(assets_dir + tex_name + ".png"):
			mat.set_shader_parameter(var_name, mat.get_shader_parameter(pairs[var_name]))

## 手动清缓存（换贴图后调用）
static func clear_cache() -> void:
	_tex_cache.clear()
	_missing_warned.clear()
