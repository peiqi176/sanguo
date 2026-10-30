#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
第二批地形贴图：道路（石板路/土路）+ 草地变种（枯草/丰草）+ 岩壁变种（层状岩/碎石岩）。

用途（用户 2026-10-25 需求）：
  ① 拼图层扩到 6 层：9=石板路(paved) 0=土路(road_dirt) → 路要"专门的资源"
  ② 草地种类太少 → shader 按 13m 尺度噪声在 草/枯草/丰草 三种间分区
  ③ 岩石种类太少 + 断层参考 AoE4/傲世三国 → 崖面在 层状岩/碎石岩/原岩 三种间分区

管线复用 gen_terrain_hd.py：Agnes 2K → 可平铺化 → 向家族色对齐 → 2048² 落盘 assets/terrain/。
原图存 assets/terrain_hd/_raw/，后处理出 bug 重跑 finalize 即可不重下。

用法：
  python gen_roads_grass.py            # 生成缺失的
  python gen_roads_grass.py --force    # 全部重生成
  python gen_roads_grass.py --only paved,grass_dry
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_terrain_hd as base  # 复用 API 调用 / 可平铺化 / 色彩校正

OUT_DIR = base.OUT_DIR
OLD_DIR = base.OLD_DIR

# 新贴图：name -> (subject, 色彩对齐目标, 对比压缩)
# 对齐目标 = 向家族里已有的贴图校色，保证整体配色体系不跑偏。
TEXS2 = {
    "paved": (
        "古代官道的石板路面：大量细密的小块石板与鹅卵石密集铺成（每块只有拳头大小），"
        "石块之间是压实的深色泥土缝隙，表面磨损均匀、有浅色走痕，"
        "整体看起来是细密的碎石路面质感，绝不是大块石板，不要大石头"
        ,
        "stone", 1.0,
    ),
    "road_dirt": (
        "干燥压实的浅色土路路面（2026-10-27 重做：路芯要比周围草地/泥土明显浅一档，"
        "像被人和车长期踩压实的新月色浅褐-奶白色夯实土，表面有轻微起伏的压实纹与浅色磨损斑，"
        "散布极细的砂粒与小碎石，局部有更浅的干土斑块）；"
        "完全无方向性：绝对不能有平直的车辙印、条纹或任何方向性纹路（要能任意方向拼接成蜿蜒小路）"
        ,
        "_ref_road_core", 1.0,
    ),
    "grass_dry": (
        "干旱的枯黄草地：黄褐色与枯草色的短草绒毯，草叶极短极密、完全看不出单根草叶和笔触，"
        "细腻如绒布的颗粒，有被晒枯的浅黄斑与裸露干土点，"
        "整体比普通草坪黄一档、干燥蓬松，绝不能出现成缕的草叶或拉丝笔触"
        ,
        "grass", 0.55,
    ),
    "grass_lush": (
        "湿润肥沃的翠绿草地：深绿与鲜绿交织的短草绒毯，草叶极短极密、完全看不出单根草叶和笔触，"
        "细腻如绒布的颗粒，间杂深绿色苔藓斑块与极少小野花白点，"
        "整体比普通草坪绿一档、水润茂盛，绝不能出现成缕的草叶或拉丝笔触"
        ,
        "grass", 0.55,
    ),
    "forest_grass": (
        "帝国时代4风格的林地地表：深褐色腐殖土为主，散落大量细小的棕褐色落叶碎片"
        "（指甲盖大小的碎叶，密而均匀，不是大片完整叶子），"
        "暗绿色苔藓斑块与细小枯枝碎屑点缀，颗粒细腻、明暗斑驳自然，"
        "整体色调深沉湿润，看不出单根草叶，不是明亮的高草地"
        ,
        "forest", 1.0,
    ),
    "rock2": (
        "层状沉积岩的陡崖断面：清晰的水平岩层带状纹理，一层深灰一层浅灰像千层饼，"
        "层间有风化凹槽与锈黄色氧化纹，局部岩层碎裂错动，块面感极强"
        "（这张会被三向投影贴在陡崖壁上，横向层理要明显）"
        ,
        "rock", 1.0,
    ),
    "rock3": (
        "碎石砾岩的崩塌坡面：大量灰褐色碎石角砾混杂堆积，砾石大小不一、棱角分明，"
        "缝隙是深色岩屑与砂土，局部有小片苔藓与风化白斑，粗粝松散"
        "（这张会被三向投影贴在陡崖壁上）"
        ,
        "rock", 1.0,
    ),
}


def generate(name: str, subject: str, force: bool) -> bool:
    """Agnes 文生图（与 base.generate 相同逻辑，仅 prompt 组装不同）。"""
    import json, time, base64, urllib.request, urllib.error
    raw_dir = os.path.join(OUT_DIR, "_raw")
    os.makedirs(raw_dir, exist_ok=True)
    path = os.path.join(raw_dir, name + ".png")
    if os.path.isfile(path) and not force:
        print("  [skip] %s 已存在" % name)
        return True

    prompt = "游戏地表材质贴图。" + subject + "。" + base.BASE
    payload = json.dumps({
        "model": base.MODEL,
        "prompt": prompt,
        "size": "2K",
        "ratio": "1:1",
        "return_base64": True,
    }).encode("utf-8")

    for attempt in range(5):
        req = urllib.request.Request(base.API_URL, data=payload, method="POST")
        req.add_header("Authorization", "Bearer " + base.KEY)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=240) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            item = (data.get("data") or [{}])[0]
            b64 = item.get("b64_json")
            if not b64:
                print("  [!] %s 无 b64_json: %s" % (name, str(data)[:200]))
                return False
            with open(path, "wb") as f:
                f.write(base64.b64decode(b64))
            print("  [OK] %s" % name)
            return True
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")
            if e.code in (429, 503):
                wait = 12 * (attempt + 1)
                print("  [%d] %s 队列忙，等 %ds 重试 (%d/5)" % (e.code, name, wait, attempt + 1))
                time.sleep(wait)
                continue
            print("  [HTTP %d] %s: %s" % (e.code, name, body[:200]))
            return False
        except Exception as e:
            print("  [ERR] %s: %s" % (name, e))
            time.sleep(6)
    return False


def finalize(name: str, match_to: str, contrast: float) -> None:
    """可平铺化 + 向家族色对齐 + 对比压缩 → assets/terrain/<name>.png"""
    from PIL import Image
    raw_path = os.path.join(OUT_DIR, "_raw", name + ".png")
    im = Image.open(raw_path).convert("RGB")
    im = im.resize((base.WORK, base.WORK), Image.LANCZOS)
    im = base.make_tileable(im)
    im = base.color_match(im, os.path.join(OLD_DIR, match_to + ".png"))

    if contrast != 1.0:
        px = im.load()
        means = [sum(px[x, y][c] for x in range(0, im.width, 16)
                     for y in range(0, im.height, 16)) / 4096.0 for c in range(3)]
        for y in range(im.height):
            for x in range(im.width):
                p = px[x, y]
                px[x, y] = tuple(max(0, min(255, int(means[c] + (p[c] - means[c]) * contrast)))
                                 for c in range(3))

    im = im.resize((base.FINAL, base.FINAL), Image.LANCZOS)
    out_path = os.path.join(OLD_DIR, name + ".png")
    im.save(out_path)
    print("  [finalize] %s -> %s" % (name, out_path))


def main() -> None:
    base.KEY = base.load_key()
    if not base.KEY:
        print("没有 Agnes key（tools/agnes.key）")
        return
    force = "--force" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))

    for name, (subject, match_to, contrast) in TEXS2.items():
        if only and name not in only:
            continue
        print("== %s ==" % name)
        if generate(name, subject, force):
            finalize(name, match_to, contrast)
    print("全部完成")


if __name__ == "__main__":
    main()
