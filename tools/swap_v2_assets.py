# -*- coding: utf-8 -*-
"""
把 assets/sprites_v2/ 里"统一锚点"的新素材接进游戏
================================================
只做三件事，全部可回滚：
  1. 备份旧贴图到 assets/sprites_backup_pre_v2/
  2. 把 sprites_v2/<id>.png 拷成 assets/sprites/<id>.png
  3. 在 config/asset_map.json 里把对应条目改成 {sprite, scale, offset_y: 0}

scale 为什么统一：素材已经按同一套锚点归一化（内容占画布 78%、脚底贴底边），
如果还像以前那样一条条手调 scale，等于把刚统一好的比例又拆散。
数值见 docs/美术锚点规范_v1.md 第 5 节。

用法：
  python tools/swap_v2_assets.py            # 干跑，只报告
  python tools/swap_v2_assets.py --write    # 真写
"""
import argparse
import io
import json
import os
import shutil

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "sprites_v2")
DST = os.path.join(ROOT, "assets", "sprites")
BAK = os.path.join(ROOT, "assets", "sprites_backup_pre_v2")
ASSET_MAP = os.path.join(ROOT, "config", "asset_map.json")

UNIT_SCALE = 0.85      # 256 画布、内容 200px → 兵约 1.86 m
BUILDING_SCALE = 2.60  # 512 画布、内容 400px → 官府约 7 m


def load_unit_ids() -> set:
    d = json.load(io.open(os.path.join(ROOT, "config", "units.json"), encoding="utf-8-sig"))
    return set(d["units"].keys())


def load_building_ids() -> set:
    d = json.load(io.open(os.path.join(ROOT, "config", "buildings.json"), encoding="utf-8-sig"))
    return set(d["buildings"].keys())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    units = load_unit_ids()
    blds = load_building_ids()
    amap = json.load(io.open(ASSET_MAP, encoding="utf-8"))
    amap.setdefault("units", {})
    amap.setdefault("buildings", {})

    files = sorted(f for f in os.listdir(SRC) if f.lower().endswith(".png"))
    plan = []
    for f in files:
        eid = os.path.splitext(f)[0]
        if eid in units:
            cat, scale = "units", UNIT_SCALE
        elif eid in blds:
            cat, scale = "buildings", BUILDING_SCALE
        else:
            print("[skip] %-16s 不在 units/buildings 清单里" % eid)
            continue
        src = os.path.join(SRC, f)
        im = Image.open(src).convert("RGBA")
        bb = im.getbbox()
        content_h = (bb[3] - bb[1]) if bb else 0
        plan.append({"eid": eid, "cat": cat, "file": f, "scale": scale,
                     "canvas": im.size, "content_h": content_h})

    print("%-16s %-10s %-6s %-8s %s" % ("实体", "类别", "画布", "内容高", "scale"))
    for p in plan:
        print("%-16s %-10s %-6s %-8d %.2f" % (p["eid"], p["cat"],
              "%dx%d" % p["canvas"], p["content_h"], p["scale"]))

    if not args.write:
        print("\n干跑结束。加 --write 真写。")
        return

    os.makedirs(BAK, exist_ok=True)
    shutil.copy2(ASSET_MAP, os.path.join(BAK, "asset_map.json"))
    n = 0
    for p in plan:
        src = os.path.join(SRC, p["file"])
        dst = os.path.join(DST, p["file"])
        if os.path.isfile(dst):
            shutil.copy2(dst, os.path.join(BAK, p["file"]))
        shutil.copy2(src, dst)
        amap[p["cat"]][p["eid"]] = {
            "sprite": p["file"],
            "scale": p["scale"],
            "offset_y": 0,
        }
        n += 1
    io.open(ASSET_MAP, "w", encoding="utf-8", newline="\n").write(
        json.dumps(amap, ensure_ascii=False, indent=2))
    print("\n已接入 %d 张。旧图与旧 asset_map 备份在 %s" % (n, BAK))
    print("记得跑一次：godot --headless --path . --import")


if __name__ == "__main__":
    main()
