#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_ground_detail.py —— 生成地表装饰贴图（草簇 / 碎石 / 灌木）

为什么需要这一层：
  地形 shader 再怎么做，本质上只有"一张贴图 + 法线扰动"。而玩家在 30m 视距下
  看地面时，眼睛判断"这是草地"靠的是**立起来的东西**——草叶、石块、灌木。
  缺了这些，地面永远是"一块绿布"。AoE4 的地面就是靠大量小装饰撑起来的。

输出（都是透明底 PNG，Godot 里走 billboard）：
  grass_tuft.png   一小簇草（几十根叶片）
  rock_small.png   一块碎石（带受光面/背光面）
  bush_small.png   低矮灌木（几个绿团）

用法：python gen_ground_detail.py [--size 256] [--out ../assets/ground]
"""
import os
import math
import random
import argparse

from PIL import Image, ImageDraw, ImageFilter

SS = 3   # 超采样倍数：先画大图再缩小，边缘才不会有锯齿


def _rand_color(base, rnd, lo=0.82, hi=1.18, alpha=255):
    return (min(255, int(base[0] * rnd.uniform(lo, hi))),
            min(255, int(base[1] * rnd.uniform(lo, hi))),
            min(255, int(base[2] * rnd.uniform(lo, hi))),
            alpha)


def make_grass_tuft(size, seed=3):
    """一簇草：从底部一点发散出来的细长叶片，尖端偏黄绿（受光）"""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = random.Random(seed)

    base_x = s * 0.5
    base_y = s * 0.97
    # 叶片从后往前画（先画深的、远的，再画浅的、近的）
    blades = []
    for i in range(96):
        ang = rnd.gauss(0.0, 0.42)                       # 相对竖直方向的倾角
        length = s * rnd.uniform(0.34, 0.72)
        curve = rnd.uniform(-0.55, 0.55)
        blades.append((ang, length, curve, rnd.random()))
    blades.sort(key=lambda b: b[3])

    for ang, length, curve, k in blades:
        tip = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        td = ImageDraw.Draw(tip)
        # 颜色：根部深墨绿 → 中段草绿 → 尖端黄绿（阳光透射）
        c_root = (38, 52, 22, 255)
        c_mid = (78, 98, 40, 255)
        c_tip = (112, 132, 58, 255)
        pts = []
        steps = 14
        for t in range(steps + 1):
            u = t / steps
            x = base_x + math.sin(ang) * length * u + curve * length * u * u
            y = base_y - math.cos(ang) * length * u
            pts.append((x, y))
        # 分三段画，做颜色渐变
        width = max(2, int(s * 0.0115))
        for seg, col in ((pts[:5], c_root), (pts[4:10], c_mid), (pts[9:], c_tip)):
            if len(seg) >= 2:
                td.line(seg, fill=_rand_color(col, rnd, 0.85, 1.15), width=width)
        # 叶片根部稍粗
        td.ellipse([base_x - width, base_y - width * 2.2, base_x + width, base_y + width], fill=c_root)
        img = Image.alpha_composite(img, tip)

    return img


def make_rock(size, seed=11):
    """一块碎石：不规则轮廓 + 明确的受光面/背光面"""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = random.Random(seed)

    cx, cy = s * 0.5, s * 0.62
    rx, ry = s * 0.36, s * 0.27
    n = 14
    top = []
    for i in range(n):
        a = 2 * math.pi * i / n
        # 上半部不规则起伏，下半部压平成"坐在地上"的感觉
        wob = 1.0 + rnd.uniform(-0.18, 0.18)
        px = cx + math.cos(a) * rx * wob
        py = cy + math.sin(a) * ry * wob * (0.55 if math.sin(a) > 0 else 1.0)
        top.append((px, py))

    # 主体（中灰）
    d.polygon(top, fill=(112, 106, 96, 255))
    # 受光面：左上偏亮
    lit = [(p[0] * 0.86 + cx * 0.14, p[1] * 0.86 + cy * 0.14) for p in top]
    d.polygon(lit, fill=(139, 133, 121, 255))
    # 背光面：右下压暗
    d.polygon([top[i] for i in range(n // 2, n)] + [top[0]], fill=(84, 79, 71, 255))
    # 顶面高光
    hl = [(cx + (p[0] - cx) * 0.5, cy - ry * 0.42 + (p[1] - cy) * 0.35) for p in top]
    d.polygon(hl, fill=(158, 152, 139, 255))
    # 一点苔痕
    for _ in range(3):
        gx = cx + rnd.uniform(-rx * 0.6, rx * 0.6)
        gy = cy + rnd.uniform(-ry * 0.3, ry * 0.5)
        r = s * rnd.uniform(0.02, 0.045)
        d.ellipse([gx - r, gy - r * 0.7, gx + r, gy + r * 0.7], fill=(74, 88, 52, 190))
    return img


def make_bush(size, seed=21):
    """低矮灌木：几个重叠的绿团，底暗顶亮"""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    rnd = random.Random(seed)

    blobs = []
    for i in range(7):
        bx = s * 0.5 + rnd.uniform(-s * 0.26, s * 0.26)
        by = s * 0.74 + rnd.uniform(-s * 0.20, s * 0.10)
        br = s * rnd.uniform(0.13, 0.22)
        blobs.append((bx, by, br))
    blobs.sort(key=lambda b: b[1])

    for bx, by, br in blobs:
        layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        # 底暗（阴影里的叶），顶亮（受光叶）
        d.ellipse([bx - br, by - br * 0.92, bx + br, by + br * 0.92], fill=(44, 60, 28, 255))
        d.ellipse([bx - br * 0.82, by - br * 0.95, bx + br * 0.66, by + br * 0.45], fill=(66, 86, 38, 255))
        d.ellipse([bx - br * 0.58, by - br * 0.90, bx + br * 0.36, by + br * 0.10], fill=(92, 112, 52, 255))
        img = Image.alpha_composite(img, layer)
    return img


def finish(img, out_size):
    """缩小 + 轻微锐化，让边缘在 mipmap 下不糊"""
    img = img.resize((out_size, out_size), Image.LANCZOS)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "assets", "ground"))
    args = ap.parse_args()
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    jobs = [
        ("grass_tuft", make_grass_tuft),
        ("rock_small", make_rock),
        ("bush_small", make_bush),
    ]
    for name, fn in jobs:
        n = 3 if name == "grass_tuft" else 2      # 草簇多出几个变体，避免撒出来一模一样
        for v in range(n):
            img = finish(fn(args.size, seed=3 + v * 17), args.size)
            fn_out = "%s%s.png" % (name, "" if v == 0 else "_v%d" % (v + 1))
            img.save(os.path.join(out_dir, fn_out), optimize=True)
            print("[ground] %-14s %s" % (fn_out, "ok"))


if __name__ == "__main__":
    main()
