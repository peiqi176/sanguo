#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
normalize_sprites.py —— 贴图接地线归零批处理（M3-3）

背景
----
asset_map.json 里每条贴图都有一个 `offset_y`（Sprite3D 的 position.y）。
历史上这些值是手填的，范围 0.5 ~ 1.5，但每张 PNG 的「内容底边留白」实测
从 0%（wall_inner）到 21.3%（farm）不等 —— 手填值和真实留白毫无相关性，
结果就是有的兵半截陷进地里、有的建筑浮空。

现在改成运行时用 `Image.get_used_rect()` 量出内容包围盒来算贴地高度
（见 DataLoader.get_sprite_anchor_y），`offset_y` 退化为「人工在地面之上
额外抬升几米」的微调旋钮，默认必须为 0。

这个脚本做两件事（可反复跑，幂等）：
  1. 把所有 offset_y 归零；
  2. 打印每张图的底边留白，标出可疑图（留白 > 25%，通常是画歪了或
     底部带了一条不该有的投影/水印）。

用法
----
    python tools/normalize_sprites.py            # 只报告，不改文件
    python tools/normalize_sprites.py --write    # 归零并写回 asset_map.json
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_MAP = os.path.join(ROOT, "config", "asset_map.json")
SPRITE_DIR = os.path.join(ROOT, "assets", "sprites")
ALPHA_THRESHOLD = 8          # 0~255，低于此值视为透明（压掉抗锯齿噪点）
WARN_PAD_RATIO = 0.25        # 底边留白超过 25% 就值得人看一眼

CATEGORIES = [
    "units", "generals", "buildings", "resource_nodes",
    "village", "wild_horse", "supply_cart",
]


def content_bottom_pad(path):
    """返回 (canvas_h, bbox, bottom_pad_px)；读不到图返回 None。"""
    try:
        from PIL import Image
    except ImportError:
        sys.exit("需要 pillow：pip install pillow")
    im = Image.open(path).convert("RGBA")
    alpha = im.split()[3]
    bbox = alpha.point(lambda v: 255 if v > ALPHA_THRESHOLD else 0).getbbox()
    if bbox is None:
        return im.size[1], None, im.size[1]
    return im.size[1], bbox, im.size[1] - bbox[3]


def main():
    write = "--write" in sys.argv
    with open(ASSET_MAP, encoding="utf-8") as f:
        data = json.load(f)

    rows = []
    changed = 0
    for cat in CATEGORIES:
        block = data.get(cat)
        if not isinstance(block, dict):
            continue
        for eid, adef in block.items():
            if not isinstance(adef, dict):
                continue
            sprite = adef.get("sprite", "")
            if not sprite:
                continue
            path = os.path.join(SPRITE_DIR, sprite)
            if not os.path.isfile(path):
                rows.append((cat, eid, sprite, None, "缺文件"))
                continue
            h, bbox, pad = content_bottom_pad(path)
            ratio = pad / h if h else 0.0
            old = adef.get("offset_y", None)
            if old not in (0, 0.0, None):
                changed += 1
            if write:
                adef["offset_y"] = 0
                adef["content_pad"] = round(ratio, 4)   # 只作诊断信息，运行时不读
            flag = "⚠ 留白偏大" if ratio > WARN_PAD_RATIO else ""
            if bbox is None:
                flag = "⚠ 全透明"
            rows.append((cat, eid, sprite, ratio, flag))

    rows.sort(key=lambda r: (-(r[3] or 0.0)))
    print("%-16s %-22s %-14s %-8s %s" % ("分类", "实体", "文件", "底边留白", "备注"))
    print("-" * 78)
    for cat, eid, sprite, ratio, flag in rows:
        pad_s = "%.1f%%" % (ratio * 100) if ratio is not None else "—"
        print("%-16s %-22s %-14s %-8s %s" % (cat, eid, sprite, pad_s, flag))

    warn = [r for r in rows if r[4]]
    print("-" * 78)
    print("共 %d 条映射，其中 %d 条的 offset_y 非零，%d 条有告警。" % (len(rows), changed, len(warn)))

    if write:
        meta = data.setdefault("_meta", {})
        meta["sprite_policy"] = (
            "offset_y 语义 = 在地面之上的额外抬升（米），默认必须为 0。"
            "贴地高度由 DataLoader.get_sprite_anchor_y() 用 alpha 包围盒实时计算；"
            "content_pad 是该图底边留白占比，仅供诊断，运行时不读。"
        )
        with open(ASSET_MAP, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print("✅ 已写回 %s" % ASSET_MAP)
    else:
        print("（只读模式。加 --write 才会归零并写回）")


if __name__ == "__main__":
    main()
