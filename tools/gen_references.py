#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为五大类素材各生成一张「风格锚点参考图」，供后续图生图(img2img)使用。
风格对照：
  武将立绘 -> 三国志(Koei Sangokushi)
  兵种     -> 全面战争三国(Total War: THREE KINGDOMS)
  建筑     -> 帝国时代4(Age of Empires IV)
  器械     -> 傲世三国之三分天下
  地形     -> 帝国时代4(Age of Empires IV) 环境
"""
import os, re, json, time, base64, sys
import urllib.request, urllib.error

def load_agnes_key():
    key = os.environ.get("AGNES_API_KEY", "")
    if key: return key
    for p in ("~/.bash_profile","~/.profile","~/.zshrc","~/.bashrc"):
        pf = os.path.expanduser(p)
        if os.path.isfile(pf):
            for line in open(pf, encoding="utf-8", errors="ignore"):
                m = re.search(r"AGNES_API_KEY\s*=\s*['\"]?([^'\"\n]+)", line)
                if m: return m.group(1).strip()
    return ""

KEY = load_agnes_key()
assert KEY, "AGNES_API_KEY 未找到"
URL = "https://apihub.agnes-ai.com/v1/images/generations"
REF_DIR = os.path.expanduser("C:/Users/shy/桌面/ss/references")
os.makedirs(REF_DIR, exist_ok=True)

REFS = {
    "general": {  # 武将立绘 -> 三国志
        "name": "general_sangokushi",
        "prompt": (
            "Game character key visual in the visual style of Koei Tecmo's Romance of the "
            "Three Kingdoms (Sangokushi) series. A majestic ancient Chinese general, "
            "semi-realistic painterly anime rendering, intricate golden-red ceremonial armor, "
            "confident heroic pose, dramatic rim lighting, highly detailed face, clean solid "
            "neutral background, no frame, premium game splash art."),
    },
    "unit": {  # 兵种 -> 全面战争三国
        "name": "unit_totalwar3k",
        "prompt": (
            "Ancient Chinese infantry soldier unit render in the visual style of Total War: "
            "THREE KINGDOMS. Realistic 3D game engine look, weathered lamellar armor, spear "
            "and shield, gritty battlefield atmosphere, neutral studio background, full-body, "
            "detailed textures, game asset."),
    },
    "building": {  # 建筑 -> 帝国时代4
        "name": "building_aoe4",
        "prompt": (
            "Ancient Chinese administrative building (imperial court / granary) in the visual "
            "style of Age of Empires IV. Stylized realistic 3D RTS game asset, clean "
            "timber-frame and grey-tile roof, symmetrical architecture, warm wood and stone "
            "materials, soft neutral background, game asset render."),
    },
    "siege": {  # 器械 -> 傲世三国之三分天下
        "name": "siege_aoshi",
        "prompt": (
            "Ancient Chinese siege engine (counterweight trebuchet) in the visual style of the "
            "RTS game 傲世三国·三分天下. Detailed historical wooden siege weapon, realistic "
            "game render, neutral background, game asset."),
    },
    "terrain": {  # 地形 -> 帝国时代4 环境
        "name": "terrain_aoe4",
        "prompt": (
            "Game environment art in the visual style of Age of Empires IV: a small Chinese "
            "landscape diorama with pine trees, grassy meadow, rocky boulders, a dirt path and "
            "stone tiles, stylized realistic 3D, consistent soft lighting, neutral backdrop."),
    },
}

def gen(cat):
    info = REFS[cat]
    payload = json.dumps({
        "model": "agnes-image-2.5-flash",
        "prompt": info["prompt"],
        "size": "1K",
        "ratio": "1:1",
        "return_base64": True,
    }).encode()
    req = urllib.request.Request(URL, data=payload, method="POST")
    req.add_header("Authorization", "Bearer " + KEY)
    req.add_header("Content-Type", "application/json")
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=150) as r:
                data = json.loads(r.read().decode())
            b64 = (data.get("data") or [{}])[0].get("b64_json")
            if not b64:
                print(f"  [!] {cat} 无 b64: {data}"); return None
            path = os.path.join(REF_DIR, info["name"] + ".png")
            with open(path, "wb") as f:
                f.write(base64.b64decode(b64))
            # 同时存 base64 供后续 img2img 复用
            json.dump({cat: b64}, open(os.path.join(REF_DIR, info["name"] + ".b64.json"), "w"))
            print(f"  [OK] {cat} -> {path}")
            return b64
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(8*(attempt+1)); continue
            print(f"  [HTTP {e.code}] {cat}: {e.read().decode()[:150]}"); return None
        except Exception as e:
            print(f"  [ERR] {cat}: {e}"); time.sleep(5)
    return None

if __name__ == "__main__":
    only = [a for a in sys.argv[1:]]
    for cat in REFS:
        if only and cat not in only:
            continue
        out = os.path.join(REF_DIR, REFS[cat]["name"] + ".png")
        if os.path.isfile(out):
            print(f"  [skip] {cat} 已存在 -> {out}")
            continue
        print(f">> 生成风格参考: {cat}")
        gen(cat)
        time.sleep(2)
    print("参考图目录:", REF_DIR)
