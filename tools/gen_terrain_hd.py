#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AoE4 式手绘地形贴图：Agnes 文生图 → 可平铺化 → 色彩校正 → 2048² 落盘。

为什么换贴图是画质提升最大的一步：
  旧贴图是 gen_aoe4_terrain.py 用噪声"算"出来的，本质是程序纹理——匀质、没有
  人工痕迹。AoE4 地面的质感来自**手绘**内容：土路的车辙、草地的修剪纹与斑驳
  磨损、石板的错缝。这些只能"画"，生成式模型恰好擅长。

管线：
  1. Agnes 2K 1:1 文生图（每张贴图固定风格锚点：正俯视、均匀光、无物体、可平铺）
  2. 缩到 1024 做可平铺化（offset 半幅 + 中心十字带混合，把接缝特征换掉）
  3. 色彩校正：均值向旧贴图对齐（clip 0.80~1.25），保证 biome 配色体系不变
  4. LANCZOS 放大到 2048 存 assets/terrain_hd/<name>.png
     （检查满意后由 finalize 步骤覆盖 assets/terrain/，同名无需改任何代码）

用法：
  python gen_terrain_hd.py            # 生成缺失的
  python gen_terrain_hd.py --force    # 全部重生成
  python gen_terrain_hd.py --only grass,dirt
"""

import os
import sys
import json
import time
import base64
import urllib.request
import urllib.error

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
OUT_DIR = os.path.join(PROJ, "assets", "terrain_hd")
OLD_DIR = os.path.join(PROJ, "assets", "terrain")
os.makedirs(OUT_DIR, exist_ok=True)

API_URL = "https://apihub.agnes-ai.com/v1/images/generations"
MODEL = "agnes-image-2.5-flash"
WORK = 1024   # 混合工作分辨率
FINAL = 2048  # 输出分辨率


def load_key() -> str:
    key = os.environ.get("AGNES_API_KEY", "")
    if key:
        return key
    kp = os.path.join(HERE, "agnes.key")
    if os.path.isfile(kp):
        with open(kp, encoding="utf-8") as f:
            return f.read().strip()
    return ""


# 风格锚点：地形贴图全部共用，只有 subject 不同
BASE = (
    "无缝可平铺的游戏地表材质贴图（seamless tileable ground texture），"
    "正俯视平铺视角（flat top-down，不是斜视角），"
    "画面只出现地面本身：**没有任何物体、没有树、没有石头高出地面、没有建筑、没有阴影、没有光照方向**，"
    "整图亮度均匀（uniform ambient lighting，四角与中心一样亮），"
    "帝国时代4 手绘风格：笔触松弛但材质写实，色彩饱满、斑驳自然、细节丰富不脏不碎，"
    "边缘与中心密度一致（保证四方连续），无文字、无水印、无边框，1024x1024"
)

TEXS = {
    "grass": (
        "极细密的短草绒毯：均匀的黄绿色草皮，草叶极短极密、完全看不出单根草叶和笔触，"
        "像细绒布一样的细腻颗粒质感，只有大块不规则的深浅色斑（明暗草色差异），"
        "散布小片枯黄草斑，绝不能出现成缕的草叶、草丛或拉丝笔触"
    ),
    "forest": (
        "茂密林地地表：深绿色苔藓与腐殖土为主，散落褐色落叶碎屑、细小枯枝、深浅绿色地衣斑块，"
        "整体比草地暗一档、色彩深沉湿润"
    ),
    "dirt": (
        "被踩实夯平的黄褐色泥土路面：两条浅色车辙印斜向穿过（磨得发白的压实土），"
        "散布细小碎石、干裂纹理、深浅不一的土色斑块，边缘磨损自然"
    ),
    "stone": (
        "人铺的青灰色石板路面：大小不一的方形与多边形石板错缝拼接，"
        "石板面有磨损与色差，缝隙是深色压实的泥土，个别缝里长出小草芽"
    ),
    "rock": (
        "天然青灰色裸露岩石崖面：粗犷的石质颗粒、水平走向的岩层纹理与节理裂块、"
        "深浅灰色的矿物色斑、少量锈黄色风化痕迹，块面感强（这张会被三向投影贴在崖壁上）"
    ),
    "sand": (
        "河滩沙地：浅黄褐色细沙上有水流冲刷的波纹纹理、湿润与干燥沙色交替、"
        "散布小砾石与贝壳碎屑般的浅色点"
    ),
    "snow": (
        "初冬薄雪覆盖的地面：大片白色积雪下隐约透出枯黄的草茎与深色泥土斑块，"
        "雪面有风吹的细纹，不是纯白（要能看到下层地表）"
    ),
}


def generate(name: str, subject: str, force: bool) -> bool:
    raw_dir = os.path.join(OUT_DIR, "_raw")
    os.makedirs(raw_dir, exist_ok=True)
    path = os.path.join(raw_dir, name + ".png")
    if os.path.isfile(path) and not force:
        print("  [skip] %s 已存在（--force 重下）" % name)
        return True

    prompt = "游戏地表材质贴图。" + subject + "。" + BASE
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
                print("  [!] %s 无 b64_json: %s" % (name, str(data)[:200]))
                return False
            with open(path, "wb") as f:
                f.write(base64.b64decode(b64))
            print("  [OK] %s -> %s" % (name, path))
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


# ---------------------------------------------------------------- 可平铺化
def offset_half(im: Image.Image) -> Image.Image:
    """四象限环绕平移半幅（PIL 的 AFFINE 越界填黑，必须用 crop+paste 实现 wrap）。"""
    w, h = im.size
    out = Image.new("RGB", (w, h))
    out.paste(im.crop((w // 2, h // 2, w, h)), (0, 0))
    out.paste(im.crop((0, h // 2, w // 2, h)), (w // 2, 0))
    out.paste(im.crop((w // 2, 0, w, h // 2)), (0, h // 2))
    out.paste(im.crop((0, 0, w // 2, h // 2)), (w // 2, h // 2))
    return out


def make_tileable(im: Image.Image) -> Image.Image:
    """offset 半幅 + 中心十字带混合：接缝被推到画面中央的十字带里，
    再用原图对应区域盖回去 —— 接缝特征消失，代价是中央有一块混合区，
    对噪声型地表完全看不出来。"""
    w, h = im.size
    shifted = offset_half(im)

    # 中心十字带 mask（带宽 ~1/8 边长，余弦过渡）
    import math
    band = max(8, w // 8)
    half = band // 2
    wgt = [int(255 * 0.5 * (1 + math.cos(math.pi * abs(i) / half)))
           for i in range(-half, half + 1)]
    mask = Image.new("L", (w, h), 0)
    px = mask.load()
    for y in range(h):
        for dx in range(-half, half + 1):
            x = (w // 2 + dx) % w
            v = wgt[dx + half]
            if v > px[x, y]:
                px[x, y] = v
    for x in range(w):
        for dy in range(-half, half + 1):
            y = (h // 2 + dy) % h
            v = wgt[dy + half]
            if v > px[x, y]:
                px[x, y] = v
    return Image.composite(im, shifted, mask)


def color_match(new: Image.Image, old_path: str) -> Image.Image:
    """均值向旧贴图对齐（每通道 gain，clip 0.80~1.25），保住 biome 配色体系。"""
    try:
        old = Image.open(old_path).convert("RGB")
        old = old.resize((64, 64))
        new_small = new.convert("RGB").resize((64, 64))
        op, np_ = old.load(), new_small.load()
        gains = []
        for c in range(3):
            om = sum(p[c] for p in (op[x, y] for x in range(64) for y in range(64))) / (64 * 64)
            nm = sum(p[c] for p in (np_[x, y] for x in range(64) for y in range(64))) / (64 * 64)
            g = om / max(nm, 1.0)
            gains.append(max(0.80, min(1.25, g)))
        r, g_, b = gains
        # PIL point() 的 LUT 必须按通道分块：前 256 是 R 映射、中 256 是 G、后 256 是 B
        lut = []
        for ch_gain in (r, g_, b):
            lut += [min(255, int(v * ch_gain)) for v in range(256)]
        return new.convert("RGB").point(lut)
    except Exception as e:
        print("  [warn] 色彩校正失败(%s)，用原图" % e)
        return new


# 每张贴图的对比压缩系数（1.0 = 不动）。Agnes 给 grass 画的大暗斑在 90m 平铺下
# 像一片片"云影"，压 30% 对比后变成自然的草地明暗；其余贴图的对比是细节（车辙/
# 石缝），不能压。
CONTRAST = {"grass": 0.55}


def finalize(name: str) -> None:
    """从 _raw/<name>.png 做可平铺化 + 色彩校正，写成品 <name>.png。
    原图与成品分开存：后处理有 bug 时重跑 finalize 不用重花钱下载。"""
    raw_path = os.path.join(OUT_DIR, "_raw", name + ".png")
    im = Image.open(raw_path).convert("RGB")
    # 出图分辨率不定（2K 档可能是 1536/2048），先统一到工作分辨率做平铺化
    im = im.resize((WORK, WORK), Image.LANCZOS)
    im = make_tileable(im)
    old_path = os.path.join(OLD_DIR, name + ".png")
    im = color_match(im, old_path)

    k = CONTRAST.get(name, 1.0)
    if k != 1.0:
        px = im.load()
        means = [sum(px[x, y][c] for x in range(0, im.width, 16)
                     for y in range(0, im.height, 16)) / 4096.0 for c in range(3)]
        for y in range(im.height):
            for x in range(im.width):
                p = px[x, y]
                px[x, y] = tuple(max(0, min(255, int(means[c] + (p[c] - means[c]) * k)))
                                 for c in range(3))

    im = im.resize((FINAL, FINAL), Image.LANCZOS)
    im.save(os.path.join(OUT_DIR, name + ".png"), optimize=True)
    print("  [final] %s -> %d² 可平铺 + 色彩校正" % (name, FINAL))


if __name__ == "__main__":
    KEY = load_key()
    if not KEY:
        print("[ERROR] 没有 Agnes key（tools/agnes.key 或 AGNES_API_KEY）")
        sys.exit(1)

    only = None
    force = "--force" in sys.argv
    for a in sys.argv:
        if a.startswith("--only="):
            only = set(a.split("=", 1)[1].split(","))

    todo = [k for k in TEXS if only is None or k in only]
    ok = 0
    for name in todo:
        if generate(name, TEXS[name], force):
            finalize(name)
            ok += 1
    print("[DONE] %d/%d 张完成" % (ok, len(todo)))
