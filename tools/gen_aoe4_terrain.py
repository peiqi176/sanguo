#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_aoe4_terrain.py —— 程序化生成「帝国时代4 风格」地形无缝贴图

为什么不用 AI 生图：
  地形贴图要**可平铺**且**平均色可控**。AI 出图既不能保证 4 边无缝，
  也没法精确对齐各层之间的明度关系（草地要亮、林地要暗、岩石要中性），
  一旦某张偏色，接缝处就会露出明显的"补丁"。程序化生成完全可复现、可微调。

风格锚点（AoE4 的调色逻辑）：
  · 草地是「暖黄绿 / 橄榄」，不是冷绿或苔藓绿；有大量干草黄点缀
  · 林地压暗、偏褐，落叶与苔藓构成明暗碎块
  · 土是暖棕（不是灰褐），沙是暖黄
  · 岩石中性偏暖灰，明度中等——不能比草地亮，否则山像雪堆
  · 全部低对比、中等饱和：靠"层次"而不是"艳丽"出效果

用法：python gen_aoe4_terrain.py [--res 1024] [--out ../assets/terrain]
"""
import os
import sys
import argparse

import numpy as np
from PIL import Image

# ---------------------------------------------------------------- 基础噪声

def _bn(cells_y, cells_x, res, r):
    """可平铺双线性 value noise。cells 必须是整数，采样点落在格子中心 → 4 边严格无缝。"""
    cells_y = max(1, int(cells_y))
    cells_x = max(1, int(cells_x))
    g = r.random((cells_y, cells_x)).astype(np.float32)

    def axis(cells):
        t = (np.arange(res) + 0.5) / res * cells
        i0 = np.floor(t).astype(np.int64)
        f = t - i0
        f = f * f * (3.0 - 2.0 * f)          # smoothstep，避免菱形格感
        i0 = i0 % cells
        return i0, (i0 + 1) % cells, f.astype(np.float32)

    y0, y1, ty = axis(cells_y)
    x0, x1, tx = axis(cells_x)
    a = g[np.ix_(y0, x0)]
    b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]
    d = g[np.ix_(y1, x1)]
    TX = tx[None, :]
    TY = ty[:, None]
    return (a * (1 - TX) + b * TX) * (1 - TY) + (c * (1 - TX) + d * TX) * TY


def fbm(cells, octaves, res, seed, gain=0.5, aniso=(1, 1)):
    """多倍频叠加。aniso=(1,3) 表示横向拉长 3 倍（做草叶/水波痕用）。"""
    r = np.random.default_rng(seed)
    acc = np.zeros((res, res), np.float32)
    amp = 1.0
    tot = 0.0
    cy, cx = cells * aniso[0], cells * aniso[1]
    for _ in range(octaves):
        if cy > res // 2 or cx > res // 2:
            break
        acc += amp * _bn(cy, cx, res, r)
        tot += amp
        amp *= gain
        cy *= 2
        cx *= 2
    return acc / max(tot, 1e-6)


def norm01(a):
    lo, hi = float(a.min()), float(a.max())
    if hi - lo < 1e-6:
        return np.zeros_like(a)
    return (a - lo) / (hi - lo)


def voronoi(res, npts, seed):
    """可平铺 Voronoi，返回 (F1, F2-F1)。用于石板/碎石的分块与缝隙。"""
    r = np.random.default_rng(seed)
    pts = r.random((npts, 2)).astype(np.float32)
    f1 = np.full((res, res), 9.0, np.float32)
    f2 = np.full((res, res), 9.0, np.float32)
    ys = (np.arange(res) + 0.5) / res
    xs = (np.arange(res) + 0.5) / res
    for py, px in pts:
        dy = np.abs(ys - py)
        dy = np.minimum(dy, 1.0 - dy)          # 环绕
        dx = np.abs(xs - px)
        dx = np.minimum(dx, 1.0 - dx)
        d = np.sqrt(dy[:, None] ** 2 + dx[None, :] ** 2)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        f1 = np.where(closer, d, f1)
    return f1, f2 - f1


def blob_field(res, count, rmin, rmax, seed, aspect=(0.45, 1.0), soft=2.0):
    """可平铺的随机椭圆斑点场（累加）。返回 0~1+ 的场。

    为什么不用纯噪声：噪声是"均匀的雾"，无论怎么叠都只会得到一块糊掉的色斑。
    草地上一簇一簇的草、岩壁上大小不一的石块，本质是**离散的形状**，
    必须真的画成一堆形状才有结构感。远处看是明暗颗粒，近处看是草簇/碎石。
    """
    r = np.random.default_rng(seed)
    out = np.zeros((res, res), np.float32)
    for _ in range(count):
        cy = r.random() * res
        cx = r.random() * res
        rad = r.uniform(rmin, rmax)
        ang = r.uniform(0.0, np.pi)
        asp = r.uniform(aspect[0], aspect[1])
        strength = r.uniform(0.55, 1.0)
        R = int(np.ceil(rad * 2.3)) + 1
        yi = np.arange(int(cy) - R, int(cy) + R + 1)
        xi = np.arange(int(cx) - R, int(cx) + R + 1)
        dy = (yi - cy)[:, None]
        dx = (xi - cx)[None, :]
        ca, sa = np.cos(ang), np.sin(ang)
        u = (dx * ca + dy * sa) / rad
        v = (-dx * sa + dy * ca) / (rad * asp)
        d2 = u * u + v * v
        w = np.clip(1.0 - d2 * 0.25, 0.0, 1.0)
        w = w ** soft * strength
        out[np.ix_(yi % res, xi % res)] += w
    return out


def ramp(t, stops):
    """t: 0~1 数组；stops: [(pos, (r,g,b)), ...]，线性插值到 [0,1] RGB。"""
    t = np.clip(t, 0.0, 1.0)
    out = np.zeros(t.shape + (3,), np.float32)
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        m = (t >= p0) & (t <= p1) if i == 0 else (t > p0) & (t <= p1)
        if not np.any(m):
            continue
        k = ((t[m] - p0) / max(p1 - p0, 1e-6))[:, None]
        out[m] = np.array(c0, np.float32) * (1 - k) + np.array(c1, np.float32) * k
    return out


# ---------------------------------------------------------------- 各层配方
# 统一约定：所有返回值是 sRGB 0~1

def make_grass(res, seed=11):
    macro = norm01(fbm(3, 4, res, seed))                    # 大色块：黄绿↔橄榄
    meso = norm01(fbm(14, 3, res, seed + 1))                # 草簇
    micro = norm01(fbm(120, 2, res, seed + 2))              # 碎斑、草尖
    dry = norm01(fbm(5, 3, res, seed + 5))                  # 枯草区
    bare = norm01(fbm(4, 2, res, seed + 6))                 # 露土斑

    # 真实的草是"一簇一簇"的：受光草尖 + 簇间阴影。
    # 纯噪声做不到这种离散结构（怎么叠都像一层绿雾）。
    tuft_hi = np.clip(blob_field(res, 900, res * 0.004, res * 0.016, seed + 10), 0, 1.5) / 1.1
    tuft_lo = np.clip(blob_field(res, 760, res * 0.005, res * 0.020, seed + 11), 0, 1.5) / 1.1

    base = 0.24 + 0.34 * macro + 0.16 * meso + 0.08 * micro \
        + 0.15 * tuft_hi - 0.13 * tuft_lo
    base = np.clip(base, 0, 1)
    col = ramp(base, [
        (0.00, (0.185, 0.215, 0.105)),   # 阴影里的深橄榄
        (0.35, (0.325, 0.360, 0.175)),
        (0.62, (0.455, 0.470, 0.235)),
        (0.85, (0.560, 0.545, 0.290)),   # 亮黄绿
        (1.00, (0.640, 0.605, 0.330)),
    ])

    # 枯草：把偏干的大块推到暖黄（AoE4 草地上那种发黄的斑）
    k = np.clip((dry - 0.55) / 0.45, 0, 1) ** 1.4 * 0.50
    col = col * (1 - k[..., None]) + np.array([0.545, 0.495, 0.250], np.float32) * k[..., None]

    # 露土斑：小块暖褐，靠近 0 的草更"被踩秃"
    k = np.clip((bare - 0.74) / 0.26, 0, 1) ** 2.0 * 0.70
    col = col * (1 - k[..., None]) + np.array([0.330, 0.270, 0.170], np.float32) * k[..., None]

    return np.clip(col, 0, 1)


def make_forest(res, seed=21):
    macro = norm01(fbm(3, 4, res, seed))
    meso = norm01(fbm(18, 3, res, seed + 1))
    micro = norm01(fbm(140, 2, res, seed + 2))
    litter = norm01(fbm(26, 2, res, seed + 3, aniso=(1, 2)))   # 落叶层
    moss = norm01(fbm(7, 3, res, seed + 4))                    # 苔藓

    base = 0.26 + 0.34 * macro + 0.22 * meso + 0.14 * micro
    col = ramp(np.clip(base, 0, 1), [
        (0.00, (0.100, 0.115, 0.060)),
        (0.40, (0.180, 0.200, 0.105)),
        (0.72, (0.285, 0.290, 0.155)),
        (1.00, (0.390, 0.365, 0.200)),
    ])

    # 落叶：暖褐色的椭圆碎块
    k = np.clip((litter - 0.58) / 0.42, 0, 1) ** 1.6 * 0.60
    col = col * (1 - k[..., None]) + np.array([0.330, 0.255, 0.140], np.float32) * k[..., None]

    # 苔藓：偏冷的绿斑（压在暗部）
    k = np.clip((moss - 0.62) / 0.38, 0, 1) ** 1.8 * 0.45
    col = col * (1 - k[..., None]) + np.array([0.145, 0.205, 0.110], np.float32) * k[..., None]

    # 树冠阴影：几处很暗的斑，模拟"树下的黑"
    k = np.clip((macro - 0.72) / 0.28, 0, 1) ** 2.0 * 0.55
    col *= (1 - 0.45 * k)[..., None]
    return np.clip(col, 0, 1)


def make_dirt(res, seed=31):
    macro = norm01(fbm(4, 3, res, seed))
    micro = norm01(fbm(90, 3, res, seed + 1))
    grit = norm01(fbm(220, 1, res, seed + 2))             # 砂砾颗粒
    pebble = norm01(fbm(34, 1, res, seed + 3))            # 小石子
    crack = norm01(fbm(12, 2, res, seed + 4, aniso=(1, 5)))  # 车辙/干裂

    base = 0.34 + 0.36 * macro + 0.20 * micro + 0.10 * grit
    col = ramp(np.clip(base, 0, 1), [
        (0.00, (0.215, 0.160, 0.100)),
        (0.40, (0.330, 0.250, 0.155)),
        (0.75, (0.445, 0.345, 0.215)),
        (1.00, (0.545, 0.435, 0.290)),
    ])

    # 碎石：亮面 + 暗边
    k = np.clip((pebble - 0.74) / 0.26, 0, 1) ** 2.2
    col += (k * 0.18)[..., None] * np.array([0.55, 0.50, 0.42], np.float32)
    k = np.clip((0.32 - pebble) / 0.32, 0, 1) ** 2.5
    col -= (k * 0.10)[..., None] * np.array([0.30, 0.22, 0.14], np.float32)

    # 车辙暗线
    k = np.clip((crack - 0.66) / 0.34, 0, 1) ** 1.5 * 0.40
    col *= (1 - k)[..., None]
    return np.clip(col, 0, 1)


def make_stone(res, seed=41):
    """石板铺装：Voronoi 分块 + 缝 + 每块轻微色差。"""
    f1, edge = voronoi(res, 46, seed)
    tilt = norm01(fbm(6, 2, res, seed + 1))
    grain = norm01(fbm(180, 2, res, seed + 2))

    # 每块石头一个随机明度（用 f1 的局部值近似不行，改用低频噪声当"块内色差"）
    patch = norm01(fbm(8, 2, res, seed + 3))
    v = 0.42 + 0.26 * patch + 0.16 * tilt + 0.10 * grain
    col = ramp(np.clip(v, 0, 1), [
        (0.00, (0.255, 0.255, 0.240)),
        (0.45, (0.360, 0.358, 0.338)),
        (0.80, (0.470, 0.465, 0.440)),
        (1.00, (0.545, 0.540, 0.512)),
    ])

    # 石缝：edge 越小越靠近边界 → 压暗
    seam = np.clip(1.0 - edge / 0.012, 0, 1) ** 1.4
    col *= (1 - 0.55 * seam)[..., None]

    # 缝隙里的一点苔/土
    k = seam * np.clip((tilt - 0.5) * 2.0, 0, 1) * 0.5
    col = col * (1 - k[..., None]) + np.array([0.200, 0.205, 0.120], np.float32) * k[..., None]
    return np.clip(col, 0, 1)


def make_rock(res, seed=51):
    """天然岩石 / 崖面：层理交给 shader（要跟世界 Y 走），这里只做石质与断口。"""
    macro = norm01(fbm(4, 4, res, seed))
    meso = norm01(fbm(22, 3, res, seed + 1))
    micro = norm01(fbm(150, 2, res, seed + 2))
    lichen = norm01(fbm(11, 2, res, seed + 4))

    # 石块：大小不一的凸起。受光面提亮、背光面压暗 → 斜视下才有"块面"而非"糊墙"
    stone_hi = np.clip(blob_field(res, 520, res * 0.006, res * 0.026, seed + 10), 0, 1.3)
    stone_lo = np.clip(blob_field(res, 620, res * 0.006, res * 0.030, seed + 11), 0, 1.3)

    base = 0.26 + 0.28 * macro + 0.18 * meso + 0.08 * micro \
        + 0.19 * stone_hi - 0.16 * stone_lo
    col = ramp(np.clip(base, 0, 1), [
        (0.00, (0.135, 0.128, 0.118)),
        (0.40, (0.280, 0.265, 0.242)),
        (0.76, (0.455, 0.435, 0.398)),
        (1.00, (0.610, 0.585, 0.535)),
    ])

    # 注：这里故意不做"裂纹"。
    # 试过用细长斑点画裂缝，结果是一堆方向随机的黑色划痕（实拍很假）——
    # 岩石的断口是三维的，靠 2D 贴图硬画只会变成脏点。交给 shader 的层理 + 坡度光影。

    # 地衣：冷绿斑，让岩石不死板
    k = np.clip((lichen - 0.72) / 0.28, 0, 1) ** 1.8 * 0.38
    col = col * (1 - k[..., None]) + np.array([0.220, 0.255, 0.150], np.float32) * k[..., None]
    return np.clip(col, 0, 1)


def make_sand(res, seed=61):
    macro = norm01(fbm(5, 3, res, seed))
    grain = norm01(fbm(240, 1, res, seed + 1))
    ripple = norm01(fbm(14, 2, res, seed + 2, aniso=(1, 7)))   # 水波痕
    pebble = norm01(fbm(60, 1, res, seed + 3))

    v = 0.46 + 0.28 * macro + 0.14 * ripple + 0.12 * grain
    col = ramp(np.clip(v, 0, 1), [
        (0.00, (0.520, 0.455, 0.315)),
        (0.45, (0.655, 0.585, 0.420)),
        (0.80, (0.760, 0.700, 0.540)),
        (1.00, (0.845, 0.795, 0.640)),
    ])

    # 水波痕的明暗（斜光下的沙纹）
    s = np.clip((ripple - 0.5) * 2.0, -1, 1)
    col *= (1.0 + 0.10 * s)[..., None]

    # 小卵石
    k = np.clip((pebble - 0.82) / 0.18, 0, 1) ** 2.0
    col += (k * 0.16)[..., None] * np.array([0.62, 0.60, 0.55], np.float32)
    return np.clip(col, 0, 1)


def make_snow(res, seed=71):
    macro = norm01(fbm(4, 3, res, seed))
    micro = norm01(fbm(120, 2, res, seed + 1))
    drift = norm01(fbm(9, 2, res, seed + 2, aniso=(1, 3)))

    v = 0.62 + 0.26 * macro + 0.12 * micro
    col = ramp(np.clip(v, 0, 1), [
        (0.00, (0.700, 0.745, 0.815)),   # 背光偏冷蓝
        (0.45, (0.845, 0.878, 0.925)),
        (0.80, (0.930, 0.950, 0.975)),
        (1.00, (0.985, 0.990, 1.000)),
    ])
    # 雪脊的柔和起伏
    s = np.clip((drift - 0.5) * 2.0, -1, 1)
    col *= (1.0 + 0.07 * s)[..., None]
    return np.clip(col, 0, 1)


# ---------------------------------------------------------------- 主流程

RECIPES = {
    "grass": (make_grass, (108, 116, 62)),     # 目标平均色（sRGB 0-255）
    "forest": (make_forest, (62, 68, 42)),
    "dirt": (make_dirt, (118, 94, 64)),
    "stone": (make_stone, (112, 111, 105)),
    "rock": (make_rock, (104, 98, 88)),
    "sand": (make_sand, (188, 168, 126)),
    "snow": (make_snow, (226, 233, 242)),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--res", type=int, default=1024)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "assets", "terrain"))
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    only = [s for s in args.only.split(",") if s]
    for name, (fn, target) in RECIPES.items():
        if only and name not in only:
            continue
        col = fn(args.res)
        # 校正平均色：作者调节的配方难免偏一点，按目标均值整体微调，
        # 否则草地偏绿、岩石偏亮，山和草原会"断层"。
        cur = col.reshape(-1, 3).mean(axis=0) * 255.0
        gain = np.array(target, np.float32) / np.maximum(cur, 1.0)
        gain = np.clip(gain, 0.75, 1.35)      # 别把明暗层次推平
        col = np.clip(col * gain[None, None, :], 0, 1)
        img = Image.fromarray((col * 255.0 + 0.5).astype(np.uint8), mode="RGB")
        # 存 RGB：地形贴图用不到 alpha，省 1/4 体积
        path = os.path.join(out_dir, name + ".png")
        img.save(path, optimize=True)
        avg = col.reshape(-1, 3).mean(axis=0) * 255.0
        print("[tex] %-7s %dx%d  平均 RGB (%3.0f,%3.0f,%3.0f)  → %s" % (
            name, args.res, args.res, avg[0], avg[1], avg[2], path))


if __name__ == "__main__":
    main()
