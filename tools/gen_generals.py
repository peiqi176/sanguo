#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
根据《完整视觉资产总清单_v3.md》的武将立绘清单，调用 Agnes 图像 API（agnes-image-2.5-flash）
生成 86 张武将半身立绘，输出到桌面 ss/ 文件夹，缩放对齐 512x768（清单规格）。

用法：
  python gen_generals.py            # 生成全部 86 张（ss/ 中已存在的跳过）
  python gen_generals.py --test     # 仅生成 3 张代表（曹魏/蜀汉/群雄）做风格验证
  python gen_generals.py --limit 5  # 仅生成前 5 张
  python gen_generals.py --force    # 忽略已存在，强制重生成
"""

import os
import re
import sys
import time
import json
import urllib.request
import urllib.error

# ---------- 0. 读取 Agnes API Key（从用户 profile 文件，不打印值）----------
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
    print("[ERROR] 未找到 AGNES_API_KEY，请在 ~/.bash_profile 等配置，或 export AGNES_API_KEY=xxx")
    sys.exit(1)

API_URL = "https://apihub.agnes-ai.com/v1/images/generations"
OUT_DIR = os.path.expanduser("C:/Users/shy/桌面/ss")
os.makedirs(OUT_DIR, exist_ok=True)
TARGET = (512, 768)  # 清单规格

# ---------- 1. 从清单解析武将（id, name, faction, weapon, desc）----------
MANIFEST = os.path.expanduser(
    "C:/Users/shy/OneDrive/文档/Trae-CN/temp_20261013_01/完整视觉资产总清单_v3.md")

FACTION_MAP = {
    "曹魏": "wei", "蜀汉": "shu", "东吴": "wu", "群雄": "qun",
}
FACTION_COLOR = {
    "wei": "暗红（曹魏）主色",
    "shu": "墨绿（蜀汉）主色",
    "wu": "深蓝（东吴）主色",
    "qun": "暗紫（群雄）主色",
}

def parse_generals():
    generals = []
    in_generals = False      # 是否处于「三、武将头像立绘」大节
    cur_faction = None
    with open(MANIFEST, "r", encoding="utf-8") as f:
        lines = f.readlines()
    for line in lines:
        # 大节切换：仅「三、武将头像立绘」内才采集
        if re.match(r"^##\s", line):
            in_generals = ("武将" in line)
            cur_faction = None
            continue
        if not in_generals:
            continue
        # 识别势力分节：### 🏹 曹魏（24 人）/ ### 👑 群雄/前期（16 人）等
        msec = re.search(r"###\s*.*?(曹魏|蜀汉|东吴|群雄)", line)
        if msec:
            cur_faction = FACTION_MAP.get(msec.group(1), "qun")
            continue
        # 文臣默认分节
        if "文臣默认" in line:
            cur_faction = "civil"
            continue
        # 表格数据行：以 | 数字 | 开头
        if not re.match(r"^\s*\|\s*\d+\s*\|", line):
            continue
        if cur_faction is None:
            continue
        cells = [c.strip() for c in line.split("|")]
        cells = [c for c in cells if c != ""]
        if len(cells) < 4:
            continue
        gid = cells[1]
        name = cells[2]
        desc = cells[-1].replace("**", "")
        # 武器：优先含兵器的列（第 3 或第 4 列）
        weapon = ""
        for c in cells[3:5]:
            if re.search(r"(刀|剑|枪|弓|戟|斧|鞭|钺|锤|扇|笏|盾|矛)", c):
                weapon = c.replace("**", "")
                break
        if cur_faction == "civil":
            if "wei" in gid:
                fac = "wei"
            elif "shu" in gid:
                fac = "shu"
            elif "wu" in gid:
                fac = "wu"
            else:
                fac = "wei"
        else:
            fac = cur_faction or "qun"
        generals.append({"id": gid, "name": name, "faction": fac,
                         "weapon": weapon, "desc": desc})
    # 去重（按 id），保留首次出现
    seen = set()
    uniq = []
    for g in generals:
        if g["id"] in seen:
            continue
        seen.add(g["id"])
        uniq.append(g)
    return uniq

# ---------- 2. 构造中文 prompt ----------
def build_prompt(g):
    color = FACTION_COLOR.get(g["faction"], "暗紫主色")
    parts = [g["name"]]
    if g["weapon"]:
        parts.append(g["weapon"])
    # 描述里常含 "/" 分隔，保留
    parts.append(g["desc"])
    subject = "，".join(p for p in parts if p)
    prompt = (
        "三国题材武将半身立绘，中国古典工笔重彩人物画风格，精细面部与甲胄刻画，"
        "游戏立绘质感，居中半身构图，纯色简洁背景，无边框。"
        f"{color}，{subject}。"
    )
    return prompt

# ---------- 3. 调用 Agnes 生成 + 下载 ----------
def generate_one(g, size="2K", ratio="2:3"):
    p = build_prompt(g)
    payload = json.dumps({
        "model": "agnes-image-2.5-flash",
        "prompt": p,
        "size": size,
        "ratio": ratio,
        "return_base64": True,
    }).encode("utf-8")
    req = urllib.request.Request(API_URL, data=payload, method="POST")
    req.add_header("Authorization", "Bearer " + AGNES_KEY)
    req.add_header("Content-Type", "application/json")
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=150) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            item = (data.get("data") or [{}])[0]
            b64 = item.get("b64_json")
            if not b64:
                print(f"  [!] {g['id']} 返回无 b64_json: {data}")
                return False
            import base64
            raw = base64.b64decode(b64)
            img_path = os.path.join(OUT_DIR, g["id"] + ".png")
            with open(img_path, "wb") as f:
                f.write(raw)
            # 缩放对齐 512x768（保持比例，居中贴到画布）
            resize_to_target(img_path)
            print(f"  [OK] {g['id']} ({g['name']}) -> {img_path} ({len(raw)//1024}KB)")
            return True
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")
            if e.code == 429:
                wait = 8 * (attempt + 1)
                print(f"  [429] {g['id']} 限流，等待 {wait}s ...")
                time.sleep(wait)
                continue
            print(f"  [HTTP {e.code}] {g['id']}: {body[:200]}")
            return False
        except Exception as e:
            print(f"  [ERR] {g['id']}: {e}")
            time.sleep(5)
    return False

def resize_to_target(path):
    try:
        from PIL import Image
        im = Image.open(path).convert("RGBA")
        im.thumbnail(TARGET, Image.LANCZOS)
        canvas = Image.new("RGBA", TARGET, (0, 0, 0, 0))
        canvas.paste(im, ((TARGET[0] - im.width) // 2,
                          (TARGET[1] - im.height) // 2))
        canvas.save(path)
    except Exception as e:
        print(f"  [resize warn] {path}: {e}")

# ---------- 4. 主流程 ----------
if __name__ == "__main__":
    generals = parse_generals()
    print(f"清单解析到武将：{len(generals)} 张")
    if len(generals) == 0:
        sys.exit(1)
    force = "--force" in sys.argv
    if "--test" in sys.argv:
        generals = generals[:3]
        print("== TEST 模式：仅生成前 3 张 ==")
    elif "--limit" in sys.argv:
        idx = sys.argv.index("--limit")
        n = int(sys.argv[idx + 1])
        generals = generals[:n]
    for g in generals:
        out = os.path.join(OUT_DIR, g["id"] + ".png")
        if os.path.isfile(out) and not force:
            print(f"  [skip] {g['id']} 已存在")
            continue
        generate_one(g)
        time.sleep(1.5)  # 控制 RPM
    print("完成。输出目录：", OUT_DIR)
