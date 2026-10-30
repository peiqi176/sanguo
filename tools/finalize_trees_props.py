#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
树木 / 道具立绘抠底：Agnes 这次没给真 alpha（白底/棋盘格底/灰底），
用 finalize_props_v2 同款「四边泛洪删背景」处理。in-place。

每文件容差（tol = RGB 各通道允许的偏差）：
  · 默认 30：白底/灰底
  · birch 12：白桦树干本身就接近白色，容差大会把树干吃掉
  · oak   40：棋盘格底两种色块（255 白 / 230 浅灰）都要覆盖
"""

import os
import sys
from collections import deque
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
DIRS = [os.path.join(PROJ, "assets", "trees"), os.path.join(PROJ, "assets", "props")]

TOL = {
    "birch.png": 12,
    "oak.png": 40,
}


def key_background(im: Image.Image, tol: int) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()

    seeds = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1],
             px[w // 2, 0], px[w // 2, h - 1], px[0, h // 2], px[w - 1, h // 2]]
    if sum(s[3] for s in seeds) == 0:
        return im   # 已透明

    def is_bg(c) -> bool:
        for s in seeds:
            if s[3] < 8:
                if c[3] < 8:
                    return True
                continue
            if abs(c[0] - s[0]) + abs(c[1] - s[1]) + abs(c[2] - s[2]) <= tol * 3:
                return True
        return False

    visited = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg(px[x, y]) and not visited[y * w + x]:
                visited[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(px[x, y]) and not visited[y * w + x]:
                visited[y * w + x] = 1
                q.append((x, y))
    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny * w + nx]:
                visited[ny * w + nx] = 1
                if is_bg(px[nx, ny]):
                    q.append((nx, ny))

    # 软边：贴着透明区的 1 圈压半透明，防白色锯齿描边
    a = im.getchannel("A").load()
    edge = []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if a[x, y] == 0:
                continue
            if a[x - 1, y] == 0 or a[x + 1, y] == 0 or a[x, y - 1] == 0 or a[x, y + 1] == 0:
                edge.append((x, y))
    for x, y in edge:
        r, g, b, av = px[x, y]
        px[x, y] = (r, g, b, int(av * 0.55))
    return im


if __name__ == "__main__":
    force = "--force" in sys.argv
    for d in DIRS:
        for f in sorted(os.listdir(d)):
            if not f.endswith(".png"):
                continue
            path = os.path.join(d, f)
            im = Image.open(path)
            # 已抠过（四角透明）且未 --force → 跳过
            cs = [im.getpixel(p)[3] for p in [(0, 0), (im.width - 1, 0), (0, im.height - 1)]]
            if not force and sum(cs) == 0:
                print("  [skip] %s 已抠底" % f)
                continue
            out = key_background(im, TOL.get(f, 30))
            # 裁到 alpha 包围盒
            bbox = out.getbbox()
            if bbox:
                out = out.crop(bbox)
            if out.width > 1024:
                out = out.resize((1024, int(out.height * 1024 / out.width)), Image.LANCZOS)
            out.save(path, optimize=True)
            print("  [OK] %s -> %s" % (f, out.size))
