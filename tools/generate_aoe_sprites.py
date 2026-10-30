# -*- coding: utf-8 -*-
"""
AoE 风格（中世纪 RTS）程序化精灵生成器
=====================================
读取 config/asset_map.json，为每一个实体 ID 生成一张透明背景的 AoE 风格 PNG，
覆盖 assets/sprites/ 下 asset_map 指向的编号文件（映射表不变）。

风格：石墙 + 木构 + 茅草/红瓦顶 + 阵营色旗；建筑有可辨识剪影；单位是小人+武器；
武将有羽饰披风。引擎会对贴图做 30% 阵营色微调，因此配色偏中性、靠引擎上色。

只依赖 Pillow + numpy（离线、纯本地，零网络）。
用法：python tools/generate_aoe_sprites.py
"""
import json
import os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_MAP = os.path.join(ROOT, "config", "asset_map.json")
SPRITES_DIR = os.path.join(ROOT, "assets", "sprites")

PAL = {
    "stone": (150, 148, 140), "stone_dk": (104, 102, 96), "stone_lt": (198, 196, 188),
    "timber": (112, 76, 46), "timber_dk": (78, 52, 30),
    "plaster": (224, 212, 182), "plaster_dk": (188, 174, 142),
    "thatch": (201, 166, 88), "thatch_dk": (150, 118, 56),
    "tile": (124, 72, 56), "tile_dk": (92, 50, 40),
    "banner": (206, 178, 78), "banner_dk": (168, 140, 56),
    "glass": (96, 124, 146), "door": (92, 62, 36),
    "gold": (214, 184, 92), "gold_dk": (160, 130, 60),
    "leaf": (76, 120, 58), "leaf_dk": (54, 92, 42), "trunk": (96, 66, 40),
    "rock": (150, 148, 142), "wheat": (200, 170, 84),
    "skin": (232, 196, 160), "skin_dk": (196, 158, 124),
    "steel": (176, 182, 190), "steel_dk": (120, 126, 134),
    "horse": (150, 110, 74), "horse_dk": (110, 78, 50), "tunic": (206, 198, 184),
}

LIGHT = np.array([1.12, 1.06, 0.92])


def clamp(v, a=0, b=255):
    return int(max(a, min(b, v)))


def shade(c, f):
    return tuple(clamp(c[i] * f) for i in range(3))


def canvas(w, h):
    return np.zeros((h, w, 4), dtype=np.uint8)


def fill_rect(arr, x, y, w, h, color, alpha=255):
    x0, y0 = int(round(x)), int(round(y))
    x1, y1 = x0 + int(round(w)), y0 + int(round(h))
    hh, ww = arr.shape[:2]
    x0c, y0c = max(0, x0), max(0, y0)
    x1c, y1c = min(ww, x1), min(hh, y1)
    if x1c <= x0c or y1c <= y0c:
        return
    arr[y0c:y1c, x0c:x1c, 0:3] = color
    arr[y0c:y1c, x0c:x1c, 3] = np.maximum(arr[y0c:y1c, x0c:x1c, 3], alpha)


def fill_poly(arr, pts, color, alpha=255):
    h, w = arr.shape[:2]
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(float(p[0]), float(p[1])) for p in pts], fill=(color[0], color[1], color[2], alpha))
    pim = np.array(im)
    m = pim[:, :, 3] > 0
    arr[m] = pim[m]


def ellipse(arr, cx, cy, rx, ry, color, alpha=255):
    h, w = arr.shape[:2]
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(color[0], color[1], color[2], alpha))
    pim = np.array(im)
    m = pim[:, :, 3] > 0
    arr[m] = pim[m]


def contact_shadow(arr, cx, cy, rx, ry):
    h, w = arr.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    v = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
    a = np.where(v <= 1.0, (1.0 - v) * 95, 0).astype(np.uint8)
    sh = np.zeros((h, w, 4), dtype=np.uint8)
    sh[:, :, 3] = a
    cur = arr[:, :, 3]
    arr[:, :, 0:3] = np.where(a[:, :, None] > cur[:, :, None], sh[:, :, 0:3], arr[:, :, 0:3])
    arr[:, :, 3] = np.maximum(arr[:, :, 3], a)


def apply_light(arr):
    h, w = arr.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    gx = xx / float(w - 1)
    gy = yy / float(h - 1)
    f = LIGHT[0] - 0.20 * gx + 0.05 * gy - 0.05 * (1.0 - gy)
    f = np.clip(f, 0.7, 1.16)
    m = arr[:, :, 3] > 0
    for c in range(3):
        arr[m, c] = np.clip(arr[m, c] * f[m], 0, 255).astype(np.uint8)


def save_png(arr, path):
    Image.fromarray(arr, "RGBA").save(path)


# ---------------- 建筑原型（cx 中心, base_y 地面线）----------------
def b_towncenter(cx=120, base_y=300):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 96, 22)
    # 主体石基
    fill_rect(arr, cx - 78, base_y - 120, 156, 120, PAL["stone"])
    fill_rect(arr, cx - 78, base_y - 120, 156, 8, PAL["stone_lt"])
    fill_rect(arr, cx - 78, base_y - 14, 156, 14, PAL["stone_dk"])
    # 左右塔楼
    for tx in (cx - 70, cx + 56):
        fill_rect(arr, tx, base_y - 170, 14, 170, PAL["stone"])
        fill_poly(arr, [(tx - 3, base_y - 170), (tx + 7, base_y - 200),
                       (tx + 17, base_y - 170)], PAL["tile"])
    # 中央大厅 + 红瓦双坡顶
    fill_rect(arr, cx - 40, base_y - 150, 80, 150, PAL["plaster"])
    fill_poly(arr, [(cx - 48, base_y - 150), (cx, base_y - 196), (cx + 48, base_y - 150)], PAL["tile"])
    fill_poly(arr, [(cx - 48, base_y - 150), (cx, base_y - 196), (cx + 48, base_y - 150)], PAL["tile"])
    # 大门 + 窗
    fill_rect(arr, cx - 12, base_y - 56, 24, 56, PAL["door"])
    draw_window(arr, cx - 30, base_y - 130, 14, 20)
    draw_window(arr, cx + 16, base_y - 130, 14, 20)
    # 旗帜
    draw_banner(arr, cx, base_y - 210, base_y - 150, 22, PAL["banner"])
    # 侧面厚度
    fill_rect(arr, cx + 70, base_y - 120, 8, 120, PAL["stone_dk"])
    return arr


def b_cottage(cx=120, base_y=300, variant="house"):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 70, 16)
    roof_col = PAL["thatch"]
    if variant == "fishery":
        roof_col = PAL["tile"]            # 渔屋红瓦
    fill_rect(arr, cx - 52, base_y - 70, 104, 70, PAL["plaster"])
    # 木框架
    fill_rect(arr, cx - 52, base_y - 70, 6, 70, PAL["timber"])
    fill_rect(arr, cx + 46, base_y - 70, 6, 70, PAL["timber"])
    fill_rect(arr, cx - 52, base_y - 14, 104, 6, PAL["timber"])
    fill_poly(arr, [(cx - 60, base_y - 70), (cx, base_y - 116), (cx + 60, base_y - 70)], roof_col)
    fill_rect(arr, cx - 52, base_y - 12, 104, 12, PAL["timber_dk"])
    fill_rect(arr, cx - 14, base_y - 44, 28, 44, PAL["door"])
    draw_window(arr, cx - 40, base_y - 58, 16, 18)
    draw_window(arr, cx + 24, base_y - 58, 16, 18)
    if variant == "inn":   # 客栈：雨棚 + 招牌
        fill_rect(arr, cx - 56, base_y - 78, 112, 8, PAL["timber_dk"])
        fill_rect(arr, cx - 52, base_y - 70, 104, 0, PAL["banner"])
        draw_banner(arr, cx + 40, base_y - 120, base_y - 96, 14, PAL["gold"])
    if variant == "fishery":  # 小船
        ellipse(arr, cx - 30, base_y - 6, 30, 9, PAL["timber_dk"])
        fill_rect(arr, cx - 30, base_y - 16, 2, 12, PAL["timber"])
    return arr


def b_farm(cx=120, base_y=300):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 84, 18)
    # 田垄
    for i, col in enumerate([(150, 110, 60), (90, 130, 60), (150, 110, 60), (90, 130, 60)]):
        fill_rect(arr, cx - 80 + i * 40, base_y - 26, 36, 26, col)
    # 谷仓（红瓦小屋）
    fill_rect(arr, cx - 30, base_y - 70, 60, 70, PAL["plaster"])
    fill_poly(arr, [(cx - 38, base_y - 70), (cx, base_y - 104), (cx + 38, base_y - 70)], PAL["tile"])
    fill_rect(arr, cx - 10, base_y - 46, 20, 46, PAL["door"])
    return arr


def b_workshop(cx=120, base_y=300, variant="smithy"):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 78, 18)
    fill_rect(arr, cx - 58, base_y - 78, 116, 78, PAL["stone"])
    fill_poly(arr, [(cx - 66, base_y - 78), (cx, base_y - 120), (cx + 66, base_y - 78)], PAL["tile"])
    fill_rect(arr, cx - 58, base_y - 16, 116, 16, PAL["stone_dk"])
    fill_rect(arr, cx - 12, base_y - 60, 24, 60, PAL["door"])
    if variant == "lumber":                 # 锯木厂：原木堆
        for i in range(4):
            ellipse(arr, cx + 30, base_y - 10 - i * 8, 26, 8, PAL["trunk"])
    elif variant == "quarry":               # 采石场：石块 + 吊臂
        ellipse(arr, cx + 34, base_y - 8, 18, 12, PAL["rock"])
        fill_rect(arr, cx - 40, base_y - 120, 4, 120, PAL["timber_dk"])
        fill_poly(arr, [(cx - 36, base_y - 120), (cx + 10, base_y - 120), (cx + 10, base_y - 114)], PAL["timber"])
    elif variant == "smithy":               # 铁匠：烟囱 + 砧
        fill_rect(arr, cx - 44, base_y - 110, 14, 110, PAL["stone_dk"])
        fill_rect(arr, cx + 24, base_y - 30, 18, 12, PAL["steel_dk"])
    elif variant == "siege":                # 攻城坊：弩/炮剪影
        fill_rect(arr, cx + 26, base_y - 40, 4, 40, PAL["timber_dk"])
        ellipse(arr, cx + 28, base_y - 44, 22, 10, PAL["timber"])
    return arr


def b_barracks(cx=120, base_y=300, variant="barracks"):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 82, 18)
    # 城墙式石基 + 垛口
    fill_rect(arr, cx - 64, base_y - 96, 128, 96, PAL["stone"])
    merlon = PAL["stone"]
    for i in range(7):
        fill_rect(arr, cx - 64 + i * 19, base_y - 110, 12, 14, merlon)
    fill_rect(arr, cx - 64, base_y - 16, 128, 16, PAL["stone_dk"])
    # 拱门
    fill_rect(arr, cx - 14, base_y - 56, 28, 56, PAL["door"])
    # 盾徽（金）
    ellipse(arr, cx, base_y - 70, 16, 18, PAL["gold"])
    # 旗帜
    draw_banner(arr, cx, base_y - 130, base_y - 96, 22, PAL["banner"] if variant != "elite" else PAL["gold"])
    if variant == "elite":
        fill_rect(arr, cx - 64, base_y - 96, 128, 4, PAL["gold"])
    return arr


def b_academy(cx=120, base_y=300):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 80, 18)
    # 台阶
    fill_rect(arr, cx - 72, base_y - 12, 144, 12, PAL["stone_lt"])
    fill_rect(arr, cx - 64, base_y - 24, 128, 12, PAL["stone"])
    # 柱廊
    fill_rect(arr, cx - 60, base_y - 110, 120, 86, PAL["plaster"])
    for i in range(5):
        fill_rect(arr, cx - 56 + i * 28, base_y - 110, 12, 86, PAL["stone_lt"])
    fill_poly(arr, [(cx - 68, base_y - 110), (cx, base_y - 150), (cx + 68, base_y - 110)], PAL["tile"])
    return arr


def b_granary(cx=120, base_y=300):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 46, 14)
    # 圆柱粮仓
    ellipse(arr, cx, base_y - 96, 40, 96, PAL["plaster"])
    fill_poly(arr, [(cx - 44, base_y - 96), (cx, base_y - 140), (cx + 44, base_y - 96)], PAL["thatch"])
    fill_rect(arr, cx - 40, base_y - 20, 80, 20, PAL["timber_dk"])
    for i in range(3):
        fill_rect(arr, cx - 40, base_y - 90 + i * 28, 80, 3, PAL["timber"])
    return arr


def b_tower(cx=120, base_y=300, variant="arrow"):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 44, 14)
    fill_rect(arr, cx - 34, base_y - 200, 68, 200, PAL["stone"])
    for i in range(5):
        fill_rect(arr, cx - 38 + i * 16, base_y - 214, 10, 16, PAL["stone"])   # 垛口
    fill_rect(arr, cx - 34, base_y - 16, 68, 16, PAL["stone_dk"])
    draw_window(arr, cx - 26, base_y - 150, 12, 22)
    draw_window(arr, cx + 14, base_y - 150, 12, 22)
    fill_rect(arr, cx - 4, base_y - 40, 8, 40, PAL["door"])
    # 弓/弩塔加旗
    draw_banner(arr, cx, base_y - 230, base_y - 200, 18, PAL["banner"])
    return arr


def b_wall(cx=120, base_y=300):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 90, 16)
    fill_rect(arr, cx - 86, base_y - 80, 172, 80, PAL["stone"])
    for i in range(9):
        fill_rect(arr, cx - 86 + i * 20, base_y - 94, 12, 16, PAL["stone"])   # 垛口
    fill_rect(arr, cx - 86, base_y - 14, 172, 14, PAL["stone_dk"])
    return arr


def b_gate(cx=120, base_y=300):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 86, 16)
    # 牌坊/凯旋门式石坊
    fill_rect(arr, cx - 80, base_y - 150, 22, 150, PAL["stone"])
    fill_rect(arr, cx + 58, base_y - 150, 22, 150, PAL["stone"])
    fill_rect(arr, cx - 80, base_y - 150, 160, 22, PAL["stone_lt"])
    fill_rect(arr, cx - 40, base_y - 200, 80, 56, PAL["stone"])
    fill_rect(arr, cx - 40, base_y - 200, 80, 10, PAL["gold"])     # 横梁鎏金
    fill_rect(arr, cx - 18, base_y - 110, 36, 110, PAL["door"])
    return arr


def b_platform(cx=120, base_y=300):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 80, 16)
    # 点将台：高台 + 阶梯 + 栏杆 + 大旗
    fill_rect(arr, cx - 70, base_y - 60, 140, 60, PAL["stone"])
    fill_rect(arr, cx - 70, base_y - 60, 140, 8, PAL["stone_lt"])
    fill_rect(arr, cx - 30, base_y - 18, 60, 18, PAL["stone_dk"])    # 阶梯
    for i in range(6):
        fill_rect(arr, cx - 66 + i * 26, base_y - 66, 4, 60, PAL["timber_dk"])  # 栏杆柱
    draw_banner(arr, cx, base_y - 220, base_y - 150, 30, PAL["banner"])
    return arr


def b_tent(cx=120, base_y=300):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 64, 16)
    fill_poly(arr, [(cx - 60, base_y), (cx, base_y - 90), (cx + 60, base_y)], PAL["plaster_dk"])
    fill_rect(arr, cx - 60, base_y - 8, 120, 8, PAL["timber_dk"])
    fill_rect(arr, cx - 10, base_y - 50, 20, 50, PAL["timber_dk"])   # 入口
    draw_banner(arr, cx + 30, base_y - 120, base_y - 80, 16, PAL["banner"])
    return arr


# ---------------- 单位原型 ----------------
def _person(arr, cx, feet_y, tunic, opt=None):
    opt = opt or {}
    h = arr.shape[0]
    # 腿
    fill_rect(arr, cx - 9, feet_y - 30, 7, 30, PAL["timber_dk"])
    fill_rect(arr, cx + 2, feet_y - 30, 7, 30, PAL["timber_dk"])
    # 躯干（束腰短衣）
    fill_rect(arr, cx - 11, feet_y - 64, 22, 36, tunic)
    fill_rect(arr, cx - 11, feet_y - 34, 22, 6, shade(tunic, 0.8))
    # 头
    ellipse(arr, cx, feet_y - 74, 10, 11, PAL["skin"])
    ellipse(arr, cx, feet_y - 80, 10, 6, PAL["skin_dk"])   # 发
    return feet_y - 64


def u_peasant(cx=100, base_y=250):
    w, h = 200, 280
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 22, 8)
    top = _person(arr, cx, base_y, PAL["tunic"])
    # 草帽
    ellipse(arr, cx, base_y - 82, 16, 6, PAL["thatch"])
    # 锄头
    fill_rect(arr, cx + 14, base_y - 80, 3, 60, PAL["timber"])
    fill_poly(arr, [(cx + 14, base_y - 82), (cx + 26, base_y - 86), (cx + 26, base_y - 78)], PAL["steel"])
    return arr


def u_infantry(cx=100, base_y=250, weapon="sword"):
    w, h = 200, 280
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 22, 8)
    _person(arr, cx, base_y, PAL["tunic"])
    # 头盔
    fill_rect(arr, cx - 9, base_y - 86, 18, 8, PAL["steel"])
    ellipse(arr, cx, base_y - 86, 9, 5, PAL["steel_dk"])
    # 圆盾
    ellipse(arr, cx - 16, base_y - 50, 11, 13, PAL["banner"])
    ellipse(arr, cx - 16, base_y - 50, 4, 5, PAL["gold"])
    # 武器
    if weapon == "sword":
        fill_rect(arr, cx + 13, base_y - 96, 3, 70, PAL["steel"])
    elif weapon == "axe":
        fill_rect(arr, cx + 14, base_y - 80, 3, 46, PAL["timber"])
        fill_poly(arr, [(cx + 17, base_y - 84), (cx + 30, base_y - 80), (cx + 17, base_y - 72)], PAL["steel"])
    elif weapon == "spear":
        fill_rect(arr, cx + 13, base_y - 110, 3, 96, PAL["timber"])
        fill_poly(arr, [(cx + 14, base_y - 114), (cx + 19, base_y - 104), (cx + 14, base_y - 100)], PAL["steel"])
    elif weapon == "bow":
        fill_poly(arr, [(cx + 16, base_y - 86), (cx + 28, base_y - 58), (cx + 16, base_y - 30)], PAL["timber"])
        fill_rect(arr, cx + 20, base_y - 58, 2, 28, PAL["steel"])
    return arr


def u_cavalry(cx=100, base_y=250, weapon="lance", color=None):
    w, h = 200, 280
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 34, 10)
    hc = color or PAL["horse"]
    # 马身
    ellipse(arr, cx, base_y - 18, 30, 16, hc)
    fill_rect(arr, cx - 4, base_y - 30, 34, 16, hc)
    # 马腿
    for dx in (-22, -10, 12, 24):
        fill_rect(arr, cx + dx, base_y - 6, 5, 6, PAL["horse_dk"])
    # 马头/颈
    fill_poly(arr, [(cx + 26, base_y - 30), (cx + 40, base_y - 54), (cx + 34, base_y - 26)], hc)
    # 骑手
    _person(arr, cx + 2, base_y - 30, PAL["tunic"])
    ellipse(arr, cx + 2, base_y - 114, 9, 5, PAL["steel"])
    if weapon == "lance":
        fill_rect(arr, cx + 22, base_y - 140, 3, 120, PAL["timber"])
    else:
        fill_rect(arr, cx + 14, base_y - 96, 3, 70, PAL["steel"])
    return arr


def u_general(cx=100, base_y=250, accent=None):
    w, h = 200, 280
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 24, 9)
    _person(arr, cx, base_y, PAL["tunic"])
    # 羽饰头盔
    fill_rect(arr, cx - 9, base_y - 88, 18, 10, PAL["steel"])
    fill_poly(arr, [(cx - 4, base_y - 98), (cx + 4, base_y - 110), (cx + 4, base_y - 96)], accent or PAL["gold"])
    ellipse(arr, cx, base_y - 88, 9, 5, PAL["steel_dk"])
    # 披风
    fill_poly(arr, [(cx - 11, base_y - 64), (cx - 20, base_y - 20), (cx - 4, base_y - 20), (cx - 4, base_y - 60)], accent or PAL["banner"])
    # 剑
    fill_rect(arr, cx + 13, base_y - 96, 3, 70, PAL["steel"])
    # 战靴（金）
    fill_rect(arr, cx - 9, base_y - 2, 8, 4, PAL["gold"])
    fill_rect(arr, cx + 2, base_y - 2, 8, 4, PAL["gold"])
    return arr


def u_siege(cx=100, base_y=250, kind="trebuchet"):
    w, h = 200, 280
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 56, 14)
    if kind == "trebuchet":
        fill_rect(arr, cx - 50, base_y - 10, 100, 10, PAL["timber_dk"])   # 底架
        fill_rect(arr, cx - 6, base_y - 110, 12, 110, PAL["timber"])     # 主臂
        fill_rect(arr, cx - 40, base_y - 56, 80, 8, PAL["timber"])
        ellipse(arr, cx + 30, base_y - 130, 8, 8, PAL["stone"])          # 配重
    elif kind == "ballista":
        fill_rect(arr, cx - 30, base_y - 20, 60, 12, PAL["timber_dk"])
        fill_rect(arr, cx - 24, base_y - 34, 48, 8, PAL["timber"])
        fill_rect(arr, cx - 4, base_y - 44, 60, 4, PAL["steel"])        # 弩臂
    elif kind == "ram":
        fill_rect(arr, cx - 44, base_y - 30, 88, 14, PAL["timber"])
        fill_rect(arr, cx - 44, base_y - 16, 88, 14, PAL["timber_dk"])
        ellipse(arr, cx + 44, base_y - 23, 10, 10, PAL["steel_dk"])     # 撞头
    else:  # ladder / 云梯
        fill_rect(arr, cx - 6, base_y - 120, 12, 120, PAL["timber"])
        for i in range(7):
            fill_rect(arr, cx - 14, base_y - 110 + i * 16, 28, 4, PAL["timber"])
    return arr


# ---------------- 道具 ----------------
def p_tree(cx=100, base_y=250):
    w, h = 200, 280
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 26, 9)
    fill_rect(arr, cx - 6, base_y - 56, 12, 56, PAL["trunk"])
    ellipse(arr, cx, base_y - 78, 40, 38, PAL["leaf"])
    ellipse(arr, cx - 22, base_y - 60, 24, 22, PAL["leaf_dk"])
    ellipse(arr, cx + 22, base_y - 64, 24, 22, shade(PAL["leaf"], 1.1))
    return arr


def p_rock(cx=100, base_y=250):
    w, h = 200, 280
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 30, 10)
    for dx, dy, r in [(-16, -8, 20), (14, -6, 22), (0, -22, 18), (24, -20, 14)]:
        ellipse(arr, cx + dx, base_y + dy, r, r * 0.8, PAL["rock"])
    return arr


def p_wheat(cx=100, base_y=250):
    w, h = 200, 280
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 28, 9)
    for dx in range(-24, 26, 8):
        fill_rect(arr, cx + dx, base_y - 40, 3, 40, PAL["wheat"])
        ellipse(arr, cx + dx, base_y - 44, 6, 8, shade(PAL["wheat"], 1.05))
    return arr


def p_village(cx=100, base_y=250):
    w, h = 240, 340
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 70, 14)
    a = b_cottage(cx - 34, base_y)
    b = b_cottage(cx + 34, base_y)
    arr = np.maximum(arr, a)
    arr = np.maximum(arr, b)
    return arr


def p_horse(cx=100, base_y=250, color=None):
    w, h = 200, 280
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 32, 10)
    hc = color or PAL["horse"]
    ellipse(arr, cx, base_y - 18, 28, 15, hc)
    fill_rect(arr, cx - 4, base_y - 30, 30, 16, hc)
    for dx in (-20, -8, 10, 22):
        fill_rect(arr, cx + dx, base_y - 6, 5, 6, PAL["horse_dk"])
    fill_poly(arr, [(cx + 24, base_y - 30), (cx + 38, base_y - 52), (cx + 32, base_y - 26)], hc)
    return arr


def p_cart(cx=100, base_y=250):
    w, h = 200, 280
    arr = canvas(w, h)
    contact_shadow(arr, cx, base_y + 6, 40, 12)
    fill_rect(arr, cx - 34, base_y - 44, 68, 30, PAL["timber"])
    for dx in (-26, 22):
        ellipse(arr, cx + dx, base_y - 8, 16, 16, PAL["timber_dk"])
        ellipse(arr, cx + dx, base_y - 8, 6, 6, PAL["steel_dk"])
    # 拉车的马
    ellipse(arr, cx + 38, base_y - 16, 18, 10, PAL["horse"])
    return arr


# 小工具：建筑里的窗口/门/旗（需要作用在 arr 上）
def draw_window(arr, x, y, w, h):
    fill_rect(arr, x, y, w, h, PAL["glass"])
    fill_rect(arr, x, y, w, 1, PAL["timber_dk"])
    fill_rect(arr, x, y + h / 2 - 0.5, w, 1, PAL["timber_dk"])


def draw_banner(arr, x, top_y, bot_y, width, color):
    fill_rect(arr, x, top_y, 2, bot_y - top_y, PAL["timber_dk"])
    fill_poly(arr, [(x + 2, top_y), (x + 2 + width, top_y + 4),
                   (x + 2 + width, top_y + 18), (x + 2, top_y + 14)], color)


# ---------------- ID -> 原型 映射 ----------------
BUILDING_MAP = {
    "government": (b_towncenter, {}),
    "paifang": (b_gate, {}),
    "house": (b_cottage, {"variant": "house"}),
    "farm": (b_farm, {}),
    "fishery": (b_cottage, {"variant": "fishery"}),
    "lumber": (b_workshop, {"variant": "lumber"}),
    "quarry": (b_workshop, {"variant": "quarry"}),
    "workshop": (b_workshop, {"variant": "smithy"}),
    "siege_workshop": (b_workshop, {"variant": "siege"}),
    "barracks_sword": (b_barracks, {"variant": "barracks"}),
    "barracks_spear": (b_barracks, {"variant": "barracks"}),
    "barracks_archer": (b_barracks, {"variant": "barracks"}),
    "barracks_special": (b_barracks, {"variant": "elite"}),
    "training_camp": (b_barracks, {"variant": "barracks"}),
    "training_camp_t2": (b_barracks, {"variant": "barracks"}),
    "elite_camp": (b_barracks, {"variant": "elite"}),
    "military_camp": (b_tent, {}),
    "hanlinyuan": (b_academy, {}),
    "granary": (b_granary, {}),
    "stable": (b_workshop, {"variant": "smithy"}),
    "inn": (b_cottage, {"variant": "inn"}),
    "arrow_tower": (b_tower, {"variant": "arrow"}),
    "crossbow_tower": (b_tower, {"variant": "crossbow"}),
    "wall_inner": (b_wall, {}),
    "wall_outer": (b_wall, {}),
    "wall_stone": (b_wall, {}),
    "general_stage": (b_platform, {}),
}

UNIT_MAP = {
    "peasant": (u_peasant, {}),
    "sword": (u_infantry, {"weapon": "sword"}),
    "heavy_blade": (u_infantry, {"weapon": "sword"}),
    "imperial_blade": (u_infantry, {"weapon": "sword"}),
    "baier_soldier": (u_infantry, {"weapon": "sword"}),
    "danyang_soldier": (u_infantry, {"weapon": "sword"}),
    "qingzhou_soldier": (u_infantry, {"weapon": "sword"}),
    "spear": (u_infantry, {"weapon": "spear"}),
    "gold_spear": (u_infantry, {"weapon": "spear"}),
    "iron_spear": (u_infantry, {"weapon": "spear"}),
    "imperial_spear": (u_infantry, {"weapon": "spear"}),
    "sentinel": (u_infantry, {"weapon": "spear"}),
    "archer": (u_infantry, {"weapon": "bow"}),
    "imperial_archer": (u_infantry, {"weapon": "bow"}),
    "hengjiang_archer": (u_infantry, {"weapon": "bow"}),
    "axeman": (u_infantry, {"weapon": "axe"}),
    "crossbow": (u_infantry, {"weapon": "bow"}),
    "heavy_crossbow": (u_infantry, {"weapon": "bow"}),
    "zhuge_nu": (u_infantry, {"weapon": "bow"}),
    "cavalry_light": (u_cavalry, {"weapon": "lance"}),
    "cavalry_archer": (u_cavalry, {"weapon": "sword"}),
    "imperial_cavalry_archer": (u_cavalry, {"weapon": "sword"}),
    "cavalry_heavy": (u_cavalry, {"weapon": "lance"}),
    "tiger_guard": (u_infantry, {"weapon": "sword"}),
    "tiger_leopard": (u_infantry, {"weapon": "sword"}),
    "trebuchet": (u_siege, {"kind": "trebuchet"}),
    "bed_bow": (u_siege, {"kind": "ballista"}),
    "ram": (u_siege, {"kind": "ram"}),
    "ladder": (u_siege, {"kind": "ladder"}),
    "thunder_car": (u_siege, {"kind": "trebuchet"}),
}

GENERAL_MAP = {
    "default": (u_general, {"accent": PAL["gold"]}),
    "cao_cao": (u_general, {"accent": (200, 60, 60)}),
    "liubei": (u_general, {"accent": (220, 190, 90)}),
    "sunquan": (u_general, {"accent": (70, 120, 200)}),
}

PROP_MAP = {
    "wood": (p_tree, {}),
    "stone": (p_rock, {}),
    "food": (p_wheat, {}),
    "village": (p_village, {}),
    "white": (p_horse, {"color": (220, 220, 220)}),
    "red": (p_horse, {"color": (180, 80, 60)}),
    "chitu": (p_horse, {"color": (190, 70, 50)}),
    "dilu": (p_horse, {"color": (150, 140, 130)}),
    "supply_cart": (p_cart, {}),
}


def main():
    with open(ASSET_MAP, "r", encoding="utf-8") as f:
        amap = json.load(f)
    total = 0
    for category, mapping in [("buildings", BUILDING_MAP), ("units", UNIT_MAP),
                              ("generals", GENERAL_MAP), ("resource_nodes", PROP_MAP),
                              ("village", {"village": PROP_MAP["village"]}),
                              ("wild_horse", {k: PROP_MAP[k] for k in ("white", "red", "chitu", "dilu")}),
                              ("supply_cart", {"supply_cart": PROP_MAP["supply_cart"]})]:
        cat_data = amap.get(category, {})
        for eid, spec in cat_data.items():
            sprite_file = spec.get("sprite")
            if not sprite_file or eid not in mapping:
                continue
            fn, kwargs = mapping[eid]
            arr = fn(**kwargs)
            apply_light(arr)
            out = os.path.join(SPRITES_DIR, sprite_file)
            save_png(arr, out)
            total += 1
            print("  ✓ %s/%s -> %s" % (category, eid, sprite_file))
    print("完成：共生成 %d 张 AoE 风格精灵（覆盖 %s）" % (total, SPRITES_DIR))


if __name__ == "__main__":
    main()
