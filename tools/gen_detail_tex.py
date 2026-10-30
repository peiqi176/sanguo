#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
gen_detail_tex.py — 生成地表细节贴图（AoE4 式近景颗粒层）

为什么需要它：
  主地表贴图 7m 一张，俯视 30m 视距下已经摊得很开，近景只剩低频色块。
  AoE4 的做法是再叠一层 ~1m 周期的高频细节纹理（灰度，乘到 albedo 上），
  近看有"草叶/碎石"的结构感。这层贴图不需要 Agnes——程序噪声就够了，
  关键是要可平铺 + 带一点各向异性拉伸（读起来像草叶而不是纯雪花点）。

输出：assets/terrain/detail.png（512² 灰度，中灰 0.5 为基准，±0.35 对比）
用法：python tools/gen_detail_tex.py
"""
import math
import random
from PIL import Image, ImageFilter

SIZE = 512
OUT = "assets/terrain/detail.png"


def make_lattice(period, seed):
    """period×period 的格点随机值表（wrap 取模 → 可平铺）。"""
    rng = random.Random(seed)
    return [[rng.random() for _ in range(period)] for _ in range(period)]


def vnoise_wrap(x, y, lat, period):
    """格点双线性插值（平滑曲线），坐标 wrap 保证平铺无缝。"""
    xi, yi = int(math.floor(x)) % period, int(math.floor(y)) % period
    xf, yf = x - math.floor(x), y - math.floor(y)
    u = xf * xf * (3.0 - 2.0 * xf)
    v = yf * yf * (3.0 - 2.0 * yf)
    a = lat[yi][xi]
    b = lat[yi][(xi + 1) % period]
    c = lat[(yi + 1) % period][xi]
    d = lat[(yi + 1) % period][(xi + 1) % period]
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v


def main():
    # 多倍频：从 ~16px 的粗颗粒到 ~2px 的细颗粒（512 图上）
    octaves = [
        # (period, amp)
        (16, 0.32), (32, 0.26), (64, 0.20), (128, 0.14), (256, 0.08),
    ]
    lats = [make_lattice(p, seed=1000 + i * 77) for i, (p, _) in enumerate(octaves)]

    # 各向异性层：沿 45° 轻微拉伸 → 只留一点点"纤维感"。
    # ⚠️ 2026-10-25 用户反馈：原来的强拉伸(0.22)在游戏里显出一条条大草叶形状，
    #    像铺了层大草席，比例全错。AoE4 的草地是"细绒毯"，看不出单根草叶——
    #    拉伸幅度砍半以上，只做细腻的方向感。
    ani_lat = make_lattice(64, seed=4242)

    img = Image.new("L", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            v = 0.5
            for i, (p, amp) in enumerate(octaves):
                fx = x * p / SIZE
                fy = y * p / SIZE
                v += (vnoise_wrap(fx, fy, lats[i], p) - 0.5) * amp
            # 45° 拉伸：u = (x+y)/√2 压缩 → 沿对角线出现细条纹（弱化版）
            su = (x + y) * 64.0 / (SIZE * 1.4142)
            sv = (x - y + SIZE) * 16.0 / (SIZE * 1.4142)
            v += (vnoise_wrap(su, sv, ani_lat, 64) - 0.5) * 0.09
            # 轻微 ridged：翻折一次取绝对值，给"碎裂感"（弱化）
            r = abs(vnoise_wrap(x * 128.0 / SIZE, y * 128.0 / SIZE, lats[3], 128) - 0.5)
            v -= r * 0.06
            px[x, y] = max(0, min(255, int(v * 255)))

    # 轻微模糊平滑格点痕迹，再拉对比（1.55 → 1.30：颗粒更含蓄）
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    img = img.point(lambda v: max(0, min(255, int(128 + (v - 128) * 1.30))))
    img.save(OUT)
    print("已生成 %s（%dx%d 可平铺细节贴图）" % (OUT, SIZE, SIZE))


if __name__ == "__main__":
    main()
