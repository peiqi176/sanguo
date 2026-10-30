#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
重出「资源点 / 村庄」的正面立绘（原来是斜俯视等距图，直立 billboard 后像悬空斜板）。

问题根因不是"画得不好"，而是**投影不匹配**：
  旧图（2168 / 2172 / 2382）是"物件平铺在地面上、镜头从高处往下看"的鸟瞰/高俯角图。
  这种图里几乎全部信息都在水平面上，垂直面（正面）只占几个像素。
  当它被当成一张竖直广告牌立起来时，屏幕上看到的是一块被扳平的"斜板"，
  底边接触线变成一条突兀的横切边 —— 这就是截图里那种"悬空斜板"。

正确做法（与 docs/美术锚点规范_v1.md 第 7 节一致）：
  立绘必须画成「等距俯视 3/4 前视角，俯角 30~35°」，
  即**同时能看到物件的正面立面和顶面**，且不能画落地投影。
  这样配合 Building.gd 的"垂直于相机视线"倾斜，图里的水平面与真实地形投影一致。

输出：先落到 assets/sprites_new/（原图不动），后处理再由 finalize_props_v2.py 合入。

用法：
  python gen_props_v2.py            # 生成 4 张（已存在的跳过）
  python gen_props_v2.py --force    # 强制重生成
  python gen_props_v2.py --only wood,village
"""

import os
import re
import sys
import json
import time
import base64
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
OUT_DIR = os.path.join(PROJ, "assets", "sprites_new")
os.makedirs(OUT_DIR, exist_ok=True)

API_URL = "https://apihub.agnes-ai.com/v1/images/generations"
MODEL = "agnes-image-2.5-flash"


# ---------------------------------------------------------------- key
def load_key() -> str:
    key = os.environ.get("AGNES_API_KEY", "")
    if key:
        return key
    kp = os.path.join(HERE, "agnes.key")
    if os.path.isfile(kp):
        with open(kp, "r", encoding="utf-8") as f:
            return f.read().strip()
    return ""


# ---------------------------------------------------------------- 风格锚点
# 六段式固定结构：身份锚点 + 材质装备 + 姿态/视角 + 透明底无场景 + 风格锚点 + 光照与像素纪律
# 视角那一段是本次重做的核心，四张图都必须一字不差地带上。
VIEW_ANCHOR = (
    "视角：等距俯视 3/4 前视角（isometric three-quarter front view），"
    "摄像机俯角 32 度，必须同时清晰看到物件的**正面立面**与**顶面**；"
    "正立面占画面主要比重，顶面明显向后压缩；"
    "**绝对不是鸟瞰正俯视（not a top-down bird's eye view），不是平铺在地面上的俯拍**"
)

STYLE_ANCHOR = (
    "风格：帝国时代4 / 傲世三国 那种干净的半写实游戏美术插画，"
    "柔和色阶、材质写实、细节丰富但不脏不碎，"
    "和中国汉末三国时代的美术调性一致"
)

LIGHT_ANCHOR = (
    "光照：左上 45 度柔和主光，受光面明亮通透、背光面自然过渡，"
    "**不要画地面阴影、不要画落地投影、不要画环境反光**"
)

PIXEL_ANCHOR = (
    "输出纪律：纯透明背景（alpha 通道），无场景、无道具摆设、无边框、无文字、无水印；"
    "物件完整不裁切、居中放置、底边只留极少空隙；"
    "边缘干净清晰，无白色描边、无光晕、无半透明脏边；"
    "游戏资产级高细节，1024x1024"
)

ASSETS = {
    "wood": {
        "file": "2168-1.png",
        "title": "伐木场资源点（原木垛）",
        "subject": (
            "一堆伐木场刚砍伐、整齐码放的圆形原木垛：上百根带皮松木与橡木原木，"
            "横向一层层交错堆叠成一座约一人高的方垛，原木截面全部朝外，"
            "堆垛正面是一整片整齐的圆形木截面（能看到浅黄木质部的年轮），"
            "堆顶面同样是原木截面并向后延伸，树皮粗糙带纵向裂纹与深褐色节疤，"
            "垛脚散落三四根单根原木，一把铁斧斜靠在垛边、斧刃插在一截木墩上"
        ),
    },
    "stone": {
        "file": "2170-1.png",
        "title": "采石场资源点（料石垛）",
        "subject": (
            "一处采石场的料石堆垛：十几块开采出来的方形毛石与条石，大小不一，"
            "层层叠放成一座半人高的锥形矮垛，石块正面与顶面都清晰可见，"
            "石面**呈深青灰色与灰褐色**、不是白色也不是米色，有密集凿痕与錾点、"
            "砂岩粗糙断口、表面带少量泥土与青苔，"
            "垛脚散落碎石屑与两块待运的方石，旁边靠一把长柄石锤和一根铁钎"
        ),
    },
    "food": {
        "file": "2172-1.png",
        "title": "农田资源点（粮袋与谷堆）",
        "subject": (
            "一处农田收成的粮堆：五六个粗麻布粮袋（袋口卷边、布纹可见）与两只木桶堆靠在一起，"
            "最上面两袋敞开、露出饱满的金黄谷粒，"
            "正前方地上堆着一座半人高的圆锥形谷堆、谷物颗粒清晰可辨，"
            "谷堆上斜插几束带秆的麦穗，旁边放一只木制量斗"
        ),
    },
    "village": {
        "file": "2382-1.png",
        "title": "村庄（汉末农舍院落）",
        "subject": (
            "一处小型汉末村落，**低机位**：前排两间夯土墙农舍（一间青瓦顶、一间茅草顶）"
            "完整露出正立面 —— 木门、窗洞、夯土墙面、屋檐下的木构都清晰可见；"
            "后排两间农舍被前排部分遮挡，只露出屋顶与半截山墙；"
            "两排之间是踩实的土路与一小块夯土空地，空地上一口带辘轳木架的石砌水井，"
            "屋前有低矮竹篱笆、柴堆、石磨与几只陶罐"
        ),
    },
}


def build_prompt(key: str) -> str:
    a = ASSETS[key]
    return (
        "游戏美术资产，单件独立物件，无人物。"
        + a["subject"] + "。"
        + VIEW_ANCHOR + "。"
        + "透明背景，无场景。"          # 透明底锚点
        + STYLE_ANCHOR + "。"
        + LIGHT_ANCHOR + "。"
        + PIXEL_ANCHOR + "。"
    )


def generate(key: str, force: bool = False) -> bool:
    a = ASSETS[key]
    path = os.path.join(OUT_DIR, a["file"])
    if os.path.isfile(path) and not force:
        print(f"  [skip] {key} 已存在 -> {path}")
        return True

    prompt = build_prompt(key)
    payload = json.dumps({
        "model": MODEL,
        "prompt": prompt,
        "size": "2K",
        "ratio": "1:1",
        "return_base64": True,
    }).encode("utf-8")

    for attempt in range(5):
        req = urllib.request.Request(API_URL, data=payload, method="POST")
        req.add_header("Authorization", "Bearer " + KEY)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=240) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            item = (data.get("data") or [{}])[0]
            b64 = item.get("b64_json")
            if not b64:
                print(f"  [!] {key} 无 b64_json: {str(data)[:300]}")
                return False
            raw = base64.b64decode(b64)
            with open(path, "wb") as f:
                f.write(raw)
            print(f"  [OK] {key} ({a['title']}) -> {path}  ({len(raw)//1024} KB)")
            return True
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")
            if e.code in (429, 503):
                wait = 10 * (attempt + 1)
                print(f"  [{e.code}] {key} 队列忙，等 {wait}s 重试 ({attempt+1}/5)")
                time.sleep(wait)
                continue
            print(f"  [HTTP {e.code}] {key}: {body[:300]}")
            return False
        except Exception as e:
            print(f"  [ERR] {key}: {e}")
            time.sleep(6)
    return False


if __name__ == "__main__":
    KEY = load_key()
    if not KEY:
        print("[ERROR] 没有 Agnes key（tools/agnes.key 或 AGNES_API_KEY）")
        sys.exit(1)

    argv = sys.argv[1:]
    force = "--force" in argv
    only = None
    for i, s in enumerate(argv):
        if s == "--only" and i + 1 < len(argv):
            only = [x.strip() for x in argv[i + 1].split(",") if x.strip()]

    keys = only if only else list(ASSETS.keys())
    print(f"=== 生成 {len(keys)} 张资源立绘（俯角 32° 3/4 前视）===")
    ok = 0
    for k in keys:
        if k not in ASSETS:
            print(f"  [warn] 未知资产 {k}")
            continue
        print(f"[{k}] {ASSETS[k]['title']}")
        print("   prompt:", build_prompt(k)[:120] + " ...")
        if generate(k, force):
            ok += 1
        time.sleep(2)
    print(f"=== 完成 {ok}/{len(keys)} ===")
