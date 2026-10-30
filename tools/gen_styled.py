#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
按用户指定的五大游戏风格，用「参考图生图（img2img）」重新生成全部素材。

风格映射（用户原话）：
  武将立绘 -> 三国志 (Koei Sangokushi) 风格，背景透明
  兵种     -> 全面战争三国 (Total War: THREE KINGDOMS) 风格
  建筑     -> 帝国时代4 (Age of Empires IV) 风格
  器械/舰船-> 傲世三国之三分天下 风格
  地形/树  -> 帝国时代4 (Age of Empires IV) 风格

流程：
  1) 先为每类生成一张「风格锚点参考图」（tools/gen_references.py，已生成到 ss/references/）。
  2) 本脚本读取清单，对每一条资产构造详细英文提示词，并用对应参考图做 img2img。
  3) 输出到 桌面\\ss\\<category>\\<id>_<style>.png（文件名备注风格名）。
  4) 需要透明底的类别（武将/兵种/建筑/器械/树/岩石/丘陵）先在白底上生图，再做白底抠图；
     地形贴图类（草地/路/水）整幅填充、不透明。

用法：
  python gen_styled.py --category generals units buildings siege terrain trees
  python gen_styled.py all
  python gen_styled.py --test           # 每类仅前 2 条，验证风格/质量
  python gen_styled.py --category generals --limit 5
  python gen_styled.py --category generals --force   # 忽略已存在，强制重生成
"""

import os
import re
import sys
import io
import time
import json
import base64
import urllib.request
import urllib.error

import numpy as np
from PIL import Image

# ---------- 0. 读取 Agnes API Key（从用户 profile，不打印值）----------
def load_agnes_key() -> str:
    key = os.environ.get("AGNES_API_KEY", "")
    if key:
        return key
    for prof in (os.path.expanduser("~/.bash_profile"),
                 os.path.expanduser("~/.profile"),
                 os.path.expanduser("~/.zshrc"),
                 os.path.expanduser("~/.bashrc")):
        if not os.path.isfile(prof):
            continue
        with open(prof, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                m = re.search(r"AGNES_API_KEY\s*=\s*['\"]?([^'\"\n]+)['\"]?", line)
                if m:
                    return m.group(1).strip()
    return ""

AGNES_KEY = load_agnes_key()
if not AGNES_KEY:
    print("[ERROR] 未找到 AGNES_API_KEY")
    sys.exit(1)

API_URL = "https://apihub.agnes-ai.com/v1/images/generations"
SS_DIR = os.path.expanduser("C:/Users/shy/桌面/ss")
REF_DIR = os.path.join(SS_DIR, "references")
MANIFEST = os.path.expanduser(
    "C:/Users/shy/OneDrive/文档/Trae-CN/temp_20261013_01/完整视觉资产总清单_v3.md")

# ---------- 1. 清单解析 ----------
SECTION_TITLES = {
    "buildings": "一、建筑模型",
    "units": "二、兵种模型",
    "generals": "三、武将头像立绘",
    "trees": "四、树木",
    "terrain": "五、地形元素",
}

SIEGE_IDS = {"trebuchet", "bed_bow", "thunder_car", "yunliang", "supply_cart",
             "straw_boat", "transport_ship", "warship"}
GROUND_PREFIXES = ("grass_", "road_", "water_")
FAC_COLOR = {"曹魏": "dark red (Cao Wei)", "蜀汉": "dark green (Shu Han)",
             "东吴": "deep blue (Wu)", "群雄": "dark purple (warlords)",
             "civil": "imperial gold"}

def parse_manifest():
    items = {k: [] for k in SECTION_TITLES}
    cur = None
    in_generals = False
    faction = None
    with open(MANIFEST, "r", encoding="utf-8") as f:
        lines = f.readlines()
    for line in lines:
        if line.startswith("## "):
            cur = None
            in_generals = False
            for k, t in SECTION_TITLES.items():
                if t in line:
                    cur = k
                    if k == "generals":
                        in_generals = True
            continue
        if cur is None:
            continue
        # 武将势力分节
        if in_generals:
            msec = re.search(r"###\s*.*?(曹魏|蜀汉|东吴|群雄)", line)
            if msec:
                faction = msec.group(1)
                continue
            if "文臣默认" in line:
                faction = "civil"
                continue
        row = line.strip()
        if not row.startswith("|"):
            continue
        cells = [c.strip() for c in row.split("|")]
        cells = [c for c in cells if c != ""]
        if len(cells) < 3:
            continue
        if not cells[0].isdigit():
            continue
        cand = cells[1]
        if not re.match(r"^[a-z][a-z0-9_]*$", cand):
            continue
        rid = cand
        name = cells[2]
        desc = " | ".join(cells[3:6]) if len(cells) > 3 else ""
        rec = {"id": rid, "name": name, "desc": desc}
        if in_generals:
            rec["faction"] = faction or "qun"
        items[cur].append(rec)
    # 去重（按 id）
    for k in items:
        seen = set(); uniq = []
        for r in items[k]:
            if r["id"] in seen:
                continue
            seen.add(r["id"]); uniq.append(r)
        items[k] = uniq
    return items

# ---------- 2. 类别配置 ----------
CATS = {
    "generals":  {"ref": "general_sangokushi", "style": "sangokushi",
                  "out_sub": "generals",  "ratio": "2:3", "size": "2K", "transparent": True},
    "units":     {"ref": "unit_totalwar3k",   "style": "totalwar3k",
                  "out_sub": "units",     "ratio": "3:4", "size": "2K", "transparent": True},
    "buildings": {"ref": "building_aoe4",     "style": "aoe4",
                  "out_sub": "buildings", "ratio": "1:1", "size": "2K", "transparent": True},
    "siege":     {"ref": "siege_aoshi",       "style": "aoshi",
                  "out_sub": "siege",     "ratio": "3:4", "size": "2K", "transparent": True},
    "terrain":   {"ref": "terrain_aoe4",      "style": "aoe4",
                  "out_sub": "terrain",   "ratio": "1:1", "size": "2K", "transparent": False},
    "trees":     {"ref": "terrain_aoe4",      "style": "aoe4",
                  "out_sub": "trees",     "ratio": "1:1", "size": "2K", "transparent": True},
}

# ---------- 3. 提示词构造 ----------
def subj(it):
    return f"{it['name']}（{it['desc']}）" if it.get("desc") else it["name"]

def prompt_generals(g):
    color = FAC_COLOR.get(g.get("faction", ""), "neutral")
    return ("Reference the art style of this image: Koei Tecmo's Romance of the Three Kingdoms "
            "(Sangokushi) series — semi-realistic painterly anime rendering, refined ink-line "
            "shading, jewel-toned ceremonial armor, dramatic heroic composition, premium game "
            f"splash art. Create a character portrait of {subj(g)}. Faction color theme: {color}. "
            "Waist-up or full-body, centered, on a plain solid WHITE background, clean studio "
            "cutout, no frame, transparent-ready.")

def prompt_units(u):
    if u["id"].startswith("horse_"):
        return ("Reference the art style of this image: Total War: THREE KINGDOMS — realistic 3D "
                "game-engine render of mounts, weathered tack and detailed coat. "
                f"Create a 3D game-asset render of a warhorse: {subj(u)}. Full body, centered, on a "
                "plain solid WHITE background, neutral studio lighting, clean cutout, game asset.")
    return ("Reference the art style of this image: Total War: THREE KINGDOMS — realistic 3D "
            "game-engine render, weathered lamellar and scale armor, gritty detailed textures, "
            f"dynamic battlefield lighting. Create a 3D game-asset render of an ancient Chinese "
            f"soldier: {subj(u)}. Full body, centered, on a plain solid WHITE background, neutral "
            "studio lighting, clean cutout, game asset.")

def prompt_buildings(b):
    return ("Reference the art style of this image: Age of Empires IV — stylized realistic 3D RTS "
            "building, clean timber-frame and grey-tile roofs, warm wood and stone materials, soft "
            f"ambient lighting. Create a 3D game-asset render of a Chinese building/structure: "
            f"{subj(b)}. Centered, on a plain solid WHITE background, clean cutout, game asset.")

def prompt_siege(s):
    return ("Reference the art style of this image: the RTS game 傲世三国·三分天下 — detailed "
            "historical Chinese siege weapons and warships, realistic game render. Create a 3D "
            f"game-asset render of: {subj(s)}. Centered, on a plain solid WHITE background, clean "
            "cutout, game asset.")

def prompt_trees(t):
    return ("Reference the art style of this image: Age of Empires IV — stylized realistic 3D "
            "environment props, soft lighting, clean readable silhouette. Create a 3D game-asset "
            f"render of a tree: {subj(t)}. Centered, on a plain solid WHITE background, clean "
            "cutout, game asset.")

def prompt_terrain_obj(t):
    return ("Reference the art style of this image: Age of Empires IV — stylized realistic 3D "
            f"environment props. Create a 3D game-asset render of a terrain feature: {subj(t)}. "
            "Centered, on a plain solid WHITE background, clean cutout, game asset.")

def prompt_terrain_ground(t):
    return ("Reference the art style of this image: Age of Empires IV — stylized realistic 3D "
            f"terrain. Create a top-down ground texture tile of: {subj(t)}. Fills the entire "
            "frame, tileable and seamless, soft natural lighting, game environment texture.")

def build_prompt(cat, it):
    if cat == "generals":  return prompt_generals(it)
    if cat == "units":     return prompt_units(it)
    if cat == "buildings": return prompt_buildings(it)
    if cat == "siege":     return prompt_siege(it)
    if cat == "trees":     return prompt_trees(it)
    if cat == "terrain":
        return prompt_terrain_ground(it) if it["id"].startswith(GROUND_PREFIXES) else prompt_terrain_obj(it)
    return subj(it)

def should_key(cat, it):
    if cat in ("generals", "units", "buildings", "siege", "trees"):
        return True
    if cat == "terrain":
        return not it["id"].startswith(GROUND_PREFIXES)
    return False

# ---------- 4. img2img 调用 ----------
def load_ref_b64(name):
    """读参考图，降采样到最长边 640 并转 JPEG——风格锚点不需要 2K，
    小负载请求更快、服务器队列压力更小。返回 (mime, b64)。"""
    p = os.path.join(REF_DIR, name + ".png")
    im = Image.open(p).convert("RGB")
    im.thumbnail((640, 640), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, format="JPEG", quality=88)
    return "image/jpeg", base64.b64encode(buf.getvalue()).decode("ascii")

class NoRedirect(urllib.request.HTTPRedirectHandler):
    """禁止 urllib 把 301/302 的 POST 降级成 GET（会 404）；改为手动重 POST。"""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

_opener = urllib.request.build_opener(NoRedirect)

def img2img(ref_mime, ref_b64, prompt, size, ratio):
    data_uri = f"data:{ref_mime};base64," + ref_b64
    body = json.dumps({
        "model": "agnes-image-2.5-flash",
        "prompt": prompt,
        "size": size,
        "ratio": ratio,
        "return_base64": True,
        "extra_body": {
            "image": [data_uri],
            "response_format": "b64_json",
        },
    }).encode("utf-8")
    url = API_URL
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, data=body, method="POST")
            req.add_header("Authorization", "Bearer " + AGNES_KEY)
            req.add_header("Content-Type", "application/json")
            with _opener.open(req, timeout=180) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            item = (data.get("data") or [{}])[0]
            b64 = item.get("b64_json")
            if not b64:
                print(f"    [!] 无 b64_json: {data}")
                return None
            return b64
        except urllib.error.HTTPError as e:
            # 负载均衡器在拥堵时返回 301/302/307：跟随 Location 重发 POST（不降级 GET）
            if e.code in (301, 302, 303, 307, 308):
                loc = e.headers.get("Location")
                if loc:
                    url = urllib.request.urljoin(url, loc)
                    print(f"    [{e.code}] 重定向，改 POST -> {url}")
                    continue
            body_txt = e.read().decode("utf-8", "ignore")
            # 400/401/403 属永久错误，不重试；其余(429/404/5xx)为瞬时错误
            if e.code in (400, 401, 403):
                print(f"    [HTTP {e.code}] {body_txt[:200]}"); return None
            wait = 15 * (attempt + 1)
            print(f"    [{e.code}] 瞬时错误，等待 {wait}s 重试 ...")
            time.sleep(wait); continue
        except Exception as ex:
            wait = 15 * (attempt + 1)
            print(f"    [ERR] {ex}，等待 {wait}s 重试 ...")
            time.sleep(wait)
    return None

def remove_white_bg(im):
    im = im.convert("RGBA")
    arr = np.array(im)
    r, g, b = arr[:, :, 0].astype(np.int16), arr[:, :, 1].astype(np.int16), arr[:, :, 2].astype(np.int16)
    # 接近纯白 -> 透明；用三通道都很高且彼此接近判断为白底
    near_white = (r > 238) & (g > 238) & (b > 238)
    arr[near_white, 3] = 0
    return Image.fromarray(arr)

# ---------- 5. 主流程 ----------
def main():
    args = sys.argv[1:]
    force = "--force" in args
    test = "--test" in args
    limit = None
    if "--limit" in args:
        i = args.index("--limit"); limit = int(args[i + 1])
    cats = [a for a in args if a in CATS]
    if not cats:
        cats = list(CATS.keys())
    # 自愈循环轮数：跑完一轮后若仍有缺失，等 90s 再来一轮，直到全齐
    max_passes = 12
    if "--passes" in args:
        i = args.index("--passes"); max_passes = int(args[i + 1])

    all_items = parse_manifest()
    siege_items = [x for x in all_items["units"] if x["id"] in SIEGE_IDS]
    unit_items = [x for x in all_items["units"] if x["id"] not in SIEGE_IDS]
    cat_items = {
        "generals": all_items["generals"],
        "units": unit_items,
        "buildings": all_items["buildings"],
        "siege": siege_items,
        "terrain": all_items["terrain"],
        "trees": all_items["trees"],
    }
    for cat in cats:
        assert cat in CATS, f"未知类别: {cat}"
    ref_cache = {}
    total_planned = 0

    for pi in range(1, max_passes + 1):
        done_this_pass = 0
        missing_total = 0
        for cat in cats:
            cfg = CATS[cat]
            if cfg["ref"] not in ref_cache:
                ref_cache[cfg["ref"]] = load_ref_b64(cfg["ref"])
            ref_mime, ref_b64 = ref_cache[cfg["ref"]]
            out_dir = os.path.join(SS_DIR, cfg["out_sub"])
            os.makedirs(out_dir, exist_ok=True)
            items = cat_items[cat]
            if test:
                items = items[:2]
            if limit:
                items = items[:limit]
            for it in items:
                fname = f"{it['id']}_{cfg['style']}.png"
                fpath = os.path.join(out_dir, fname)
                if os.path.isfile(fpath) and not force:
                    continue
                missing_total += 1
                p = build_prompt(cat, it)
                b64 = img2img(ref_mime, ref_b64, p, cfg["size"], cfg["ratio"])
                if not b64:
                    print(f"  [FAIL] {cat}/{fname}（下轮补）")
                    continue
                try:
                    im = Image.open(io.BytesIO(base64.b64decode(b64)))
                    if should_key(cat, it):
                        im = remove_white_bg(im)
                    im.save(fpath)
                    print(f"  [OK] {cat}/{fname} ({im.width}x{im.height})")
                    done_this_pass += 1
                except Exception as e:
                    print(f"  [save-err] {cat}/{fname}: {e}")
                time.sleep(8)
        total_planned += done_this_pass
        print(f"\n-- 第 {pi} 轮结束：本轮新完成 {done_this_pass}，仍缺 {missing_total - done_this_pass} --")
        if missing_total == 0:
            print("全部素材已生成完毕！")
            break
        if pi < max_passes:
            print("等待 90s 后开始下一轮补缺 ...")
            time.sleep(90)
    print("\n结束。输出根目录：", SS_DIR)

if __name__ == "__main__":
    main()
