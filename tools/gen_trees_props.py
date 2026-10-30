#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
手绘风树木（5）+ 地表道具（5）立绘，替换低多边形球树 / 扩充道具库。

树的用法：双交叉面片（X-cross）——经典 RTS（傲世三国/帝国2代高清版）的标准做法，
一张正面立绘插两片互成 90° 的面片，任意方位角都看得过去，比 billboard 多了"体积"。
道具用法：Sprite3D billboard，与资源点同管线。

视角锚点与建筑/资源点一致（等距俯视 3/4 前视角，俯角 32°，无落地投影），
这样树的明暗面与场景主光（左上 45°）方向一致。

输出：assets/trees/*.png 与 assets/props/*.png
用法：python gen_trees_props.py [--force] [--only pine,oak,...]
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
TREE_DIR = os.path.join(PROJ, "assets", "trees")
PROP_DIR = os.path.join(PROJ, "assets", "props")
os.makedirs(TREE_DIR, exist_ok=True)
os.makedirs(PROP_DIR, exist_ok=True)

API_URL = "https://apihub.agnes-ai.com/v1/images/generations"
MODEL = "agnes-image-2.5-flash"

VIEW = (
    "视角：等距俯视 3/4 前视角，摄像机俯角 32 度，能看到树冠顶面的一点点体积但以正面为主；"
    "**整棵树完整入镜、树干完整可见、底端收在画面底边**，"
    "绝对不是鸟瞰正俯视，不是只有树冠的俯拍"
)
STYLE = (
    "风格：帝国时代4 那种干净的半写实游戏美术插画，柔和色阶、笔触松弛但形态写实，"
    "细节丰富但不脏不碎"
)
LIGHT = (
    "光照：左上 45 度柔和主光，树冠受光面明亮、背光面自然过渡到深色，"
    "**不要画地面阴影、不要画落地投影**"
)
PIXEL = (
    "输出纪律：纯透明背景（alpha 通道），无场景、无草地、无其他物体、无边框、无文字、无水印；"
    "边缘干净清晰，无白色描边、无光晕；游戏资产级高细节，1024x1024"
)

# ---- 树：5 种。name 与 Tree.gd / BorderForest.gd 里的文件名对应 ----
TREES = {
    "pine": (
        "一棵高大的深绿色松树：塔形轮廓，枝叶层层下展、层间自然重叠连成一体，"
        "深墨绿色针叶有丰富的深浅变化，树干粗壮深褐色、下部可见"
    ),
    "oak": (
        "一棵茂盛的阔叶橡树：浓密的大圆树冠占画面上 2/3，绿叶团块之间有天空色透气孔，"
        "粗壮的主干分两三根大枝撑起树冠，绿色饱满偏暖"
    ),
    "birch": (
        "一棵挺拔的白桦：浅灰白色带黑色横纹的树干细而直，"
        "树冠是稀疏一些的嫩绿色小叶团，整体清瘦高挑"
    ),
    "autumn": (
        "一棵秋天的阔叶树：树冠是饱满的橙红与金黄色，间杂少量残绿，"
        "秋叶色彩浓郁像燃烧的火团，深褐色树干"
    ),
    "dead": (
        "一棵枯死的树：没有叶子，灰褐色的主干与扭曲的枯枝向天空伸展，"
        "枝干姿态苍劲，树皮有干裂纹理"
    ),
}

# ---- 道具：5 种，与 GroundDetail 扩容对应 ----
PROPS = {
    "rockpile": "一小堆天然青灰色乱石：五六块大小不一的石头自然堆叠，石面有苔藓斑与风化痕迹，缝隙处有少量泥土",
    "woodpile": "一小堆劈好的柴火：圆木段横竖交错码成半人高的小垛，断面是浅色木纹与年轮，树皮深褐色",
    "flowers": "一丛野花：黄白色的小雏菊与紫色野花混在一丛深浅不一的绿草里，十几朵花头高低错落",
    "stump": "一个新砍的树桩：低矮的圆柱桩，顶面是新鲜的浅色年轮断面，边缘有斧砍裂口，侧面树皮深褐，根部有小草",
    "bush": "一丛茂密的灌木：深绿色叶团三四个挤在一起，圆润蓬松，间杂几点深色浆果",
}


def generate(fname: str, out_dir: str, subject: str, force: bool) -> bool:
    path = os.path.join(out_dir, fname)
    if os.path.isfile(path) and not force:
        print("  [skip] %s 已存在" % fname)
        return True
    prompt = "游戏美术资产，单件独立物件，无人物。" + subject + "。" + VIEW + "。" \
        + STYLE + "。" + LIGHT + "。" + PIXEL
    payload = json.dumps({
        "model": MODEL, "prompt": prompt, "size": "2K", "ratio": "1:1",
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
                print("  [!] %s 无 b64_json: %s" % (fname, str(data)[:200]))
                return False
            with open(path, "wb") as f:
                f.write(base64.b64decode(b64))
            print("  [OK] %s" % fname)
            return True
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")
            if e.code in (429, 503):
                wait = 12 * (attempt + 1)
                print("  [%d] %s 等 %ds 重试 (%d/5)" % (e.code, fname, wait, attempt + 1))
                time.sleep(wait)
                continue
            print("  [HTTP %d] %s: %s" % (e.code, fname, body[:200]))
            return False
        except Exception as e:
            print("  [ERR] %s: %s" % (fname, e))
            time.sleep(6)
    return False


def crop_alpha(path: str) -> None:
    """裁到 alpha 包围盒（留 2% 边距）+ 缩到 1024 —— 省显存，代码里按 bbox 算尺寸。"""
    im = Image.open(path).convert("RGBA")
    bbox = im.getchannel("A").getbbox()
    if bbox:
        pad = int(max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * 0.02)
        bbox = (max(0, bbox[0] - pad), max(0, bbox[1] - pad),
                min(im.width, bbox[2] + pad), min(im.height, bbox[3] + pad))
        im = im.crop(bbox)
    if im.width > 1024:
        im = im.resize((1024, int(im.height * 1024 / im.width)), Image.LANCZOS)
    im.save(path, optimize=True)


if __name__ == "__main__":
    KEY = os.environ.get("AGNES_API_KEY", "")
    if not KEY:
        kp = os.path.join(HERE, "agnes.key")
        if os.path.isfile(kp):
            KEY = open(kp, encoding="utf-8").read().strip()
    if not KEY:
        print("[ERROR] 没有 Agnes key")
        sys.exit(1)

    force = "--force" in sys.argv
    only = None
    for a in sys.argv:
        if a.startswith("--only="):
            only = set(a.split("=", 1)[1].split(","))

    n_ok = 0
    n_all = 0
    for name, subj in TREES.items():
        if only is not None and name not in only:
            continue
        n_all += 1
        f = name + ".png"
        if generate(f, TREE_DIR, subj, force):
            crop_alpha(os.path.join(TREE_DIR, f))
            n_ok += 1
    for name, subj in PROPS.items():
        if only is not None and name not in only:
            continue
        n_all += 1
        f = name + ".png"
        if generate(f, PROP_DIR, subj, force):
            crop_alpha(os.path.join(PROP_DIR, f))
            n_ok += 1
    print("[DONE] %d/%d 张完成" % (n_ok, n_all))
