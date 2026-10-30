#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
资源点/村庄新立绘的后处理 + 合入：
  assets/sprites_new/<file>.png  →  assets/sprites/<file>.png

四步：
  1. 抠底：模型偶尔不守"透明背景"的约定（见过黑底、白底、白雾渐隐）。
     以四角颜色为背景采样，从边缘做泛洪填充——只删"连着边框的那片背景"，
     物件内部相近的颜色（石头上的浅色高光、粮袋的白麻布）不会被误删。
  2. 裁边：按 alpha 包围盒裁掉四周的空透明区。
  3. 归一化画布：内容等比缩放到指定像素高，贴在 1024×1024 画布、
     水平居中、底边留 24px。DataLoader.get_sprite_anchor_y() 是按内容包围盒
     量"中心→底边"的距离来贴地的，所以只要画布规矩，缩放比例就是世界尺寸。
  4. 合入：旧图先备份到 assets/sprites_backup_props/，再覆盖。

用法：
  python finalize_props_v2.py            # 全部
  python finalize_props_v2.py --only wood,stone
"""

import os
import sys
import json
import shutil
from collections import deque
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
SRC_DIR = os.path.join(PROJ, "assets", "sprites_new")
DST_DIR = os.path.join(PROJ, "assets", "sprites")
BAK_DIR = os.path.join(PROJ, "assets", "sprites_backup_props")
os.makedirs(DST_DIR, exist_ok=True)
os.makedirs(BAK_DIR, exist_ok=True)

CANVAS = 1024
BOTTOM_PAD = 24

# 内容目标像素高 + 期望的世界高度（米）。
# 世界高度 = canvas_px_h × pixel_size × scale，
#   pixel_size = ref_h × 0.01 / canvas(1024)，
#   content_world = content_px / canvas × ref_h × 0.01 × scale
# 反推 scale = 期望世界高 / (content_ratio × ref_h × 0.01)。
# ref_h 来自 scripts/data/DataLoader.gd 的 _SPRITE_REF_H：
#   resource_nodes=280, village=340
ASSETS = {
    "wood":    {"file": "2168-1.png", "ref_h": 280.0, "world_h": 2.5},
    "stone":   {"file": "2170-1.png", "ref_h": 280.0, "world_h": 2.3},
    "food":    {"file": "2172-1.png", "ref_h": 280.0, "world_h": 1.9},
    "village": {"file": "2382-1.png", "ref_h": 340.0, "world_h": 8.5},
}


# ---------------------------------------------------------------- 1. 抠底
def key_background(im: Image, tol: int = 34) -> Image:
    """从四边泛洪删背景。返回 RGBA8 新图。"""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()

    # 背景色采样：四角 + 四边中点。模型给的底色偶尔不均匀（黑底上有一圈白），
    # 多采几个点，逐一作为"种子颜色"参与判定。
    seeds = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1],
             px[w // 2, 0], px[w // 2, h - 1], px[0, h // 2], px[w - 1, h // 2]]
    # 已经是透明的图（角 alpha=0）就不用抠了
    if sum(s[3] for s in seeds) == 0:
        return im

    def is_bg(c) -> bool:
        for s in seeds:
            if s[3] < 8:      # 透明种子：只匹配同样透明的像素
                if c[3] < 8:
                    return True
                continue
            dr = abs(c[0] - s[0]); dg = abs(c[1] - s[1]); db = abs(c[2] - s[2])
            if dr + dg + db <= tol * 3:
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

    # 软边：把贴着透明区的 1 圈半透明像素压一压，避免出现白色锯齿描边
    alpha = im.getchannel("A")
    a = alpha.load()
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


# ---------------------------------------------------------------- 2/3. 裁边 + 归一化
def normalize(im: Image, target_content_h: int) -> Image:
    bbox = im.getbbox()          # 非零 alpha 的包围盒
    if bbox:
        im = im.crop(bbox)
    # 等比缩放到目标内容高度
    ratio = target_content_h / max(im.height, 1)
    tw = max(int(round(im.width * ratio)), 1)
    im = im.resize((tw, target_content_h), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(im, ((CANVAS - tw) // 2, CANVAS - BOTTOM_PAD - target_content_h))
    return canvas


def process(key: str) -> None:
    a = ASSETS[key]
    src = os.path.join(SRC_DIR, a["file"])
    dst = os.path.join(DST_DIR, a["file"])
    if not os.path.isfile(src):
        print(f"  [skip] {key}: 源图不存在 {src}")
        return

    im = Image.open(src)
    im = key_background(im)
    # 内容高 = 画布 - 底部留白 - 顶部留 12px 余量（防高光被裁）
    target_h = CANVAS - BOTTOM_PAD - 12
    im = normalize(im, target_h)
    im.save(dst)

    # 反推 scale：让内容世界高度 = world_h
    content_ratio = target_h / float(CANVAS)
    scale = a["world_h"] / (content_ratio * a["ref_h"] * 0.01)
    print(f"  [OK] {key}: {dst}  建议 scale = {scale:.3f}")
    SCALES[key] = round(scale, 3)


SCALES = {}

if __name__ == "__main__":
    argv = sys.argv[1:]
    only = None
    for i, s in enumerate(argv):
        if s == "--only" and i + 1 < len(argv):
            only = [x.strip() for x in argv[i + 1].split(",") if x.strip()]
    keys = only if only else list(ASSETS.keys())

    print(f"=== 后处理 {len(keys)} 张 → assets/sprites/ ===")
    for k in keys:
        # 备份旧图（只备份第一次，反复跑不会把新图覆盖进备份）
        bak = os.path.join(BAK_DIR, ASSETS[k]["file"])
        dst = os.path.join(DST_DIR, ASSETS[k]["file"])
        if os.path.isfile(dst) and not os.path.isfile(bak):
            shutil.copy2(dst, bak)
            print(f"  [bak] 旧图已备份 → {bak}")
        process(k)

    # 写出建议 scale，供人工核对后合入 asset_map.json
    out = os.path.join(SRC_DIR, "_scales.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(SCALES, f, ensure_ascii=False, indent=2)
    print(f"=== 完成，建议 scale 已写入 {out} ===")
    print(json.dumps(SCALES, ensure_ascii=False, indent=2))
