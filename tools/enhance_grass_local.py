# -*- coding: utf-8 -*-
"""草地本地增强（零 API）：细节锐化 + 色彩增饱和 + 高频草叶噪点 + 无缝处理。
输出对比图与成品，确认后替换 assets/terrain/grass.png。"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance, ImageDraw

GAME_GRASS = r"C:/Users/shy/桌面/Godot/assets/terrain/grass.png"
BACKUP     = r"C:/Users/shy/桌面/最新素材/旧版与测试/terrain_grass_原版备份.png"
OUT_DIR    = r"C:/Users/shy/桌面/最新素材/旧版与测试"
OUT_LOCAL  = os.path.join(OUT_DIR, "grass_本地增强_1024.png")
OUT_CMP    = os.path.join(OUT_DIR, "grass_对比_当前_vs_增强.png")

def make_seamless(im, feather_ratio=0.12):
    im = im.convert("RGB")
    w, h = im.size
    arr = np.asarray(im).astype(np.float32)
    F = max(16, int(min(w, h) * feather_ratio))
    out = arr.copy()
    a = np.linspace(0.0, 1.0, F, dtype=np.float32)[None, :, None]
    out[:, -F:, :] = arr[:, -F:, :] * (1 - a) + arr[:, :F, :] * a
    arr2 = out
    b = np.linspace(0.0, 1.0, F, dtype=np.float32)[:, None, None]
    out[-F:, :, :] = arr2[-F:, :, :] * (1 - b) + arr2[:F, :, :] * b
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))

def speckle_layer(size, count, seed=7):
    """生成草叶碎笔触层：随机短椭圆，颜色在草地绿色域内抖动。"""
    rng = np.random.default_rng(seed)
    layer = Image.new("RGB", size, (128, 128, 128))
    d = ImageDraw.Draw(layer)
    w, h = size
    # 草地绿色域（相对当前图的色域）
    for _ in range(count):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        ln = rng.uniform(4, 14)          # 笔触长
        ang = rng.uniform(0, 3.14159)
        dx, dy = ln * np.cos(ang), ln * np.sin(ang) * 0.45
        g = rng.integers(95, 165)        # 绿通道
        r = int(g * rng.uniform(0.55, 0.85))
        b = int(g * rng.uniform(0.35, 0.6))
        col = (int(r), int(g), int(b))
        d.line([(x, y), (x + dx, y + dy)], fill=col, width=rng.integers(1, 2))
    return layer.filter(ImageFilter.GaussianBlur(0.6))

def enhance(im):
    im = im.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    # 1) 先做无缝（后续处理不破坏接缝）
    im = make_seamless(im)
    # 2) 细节锐化
    im = im.filter(ImageFilter.UnsharpMask(radius=2, percent=110, threshold=2))
    # 3) 色彩增强
    im = ImageEnhance.Color(im).enhance(1.16)
    im = ImageEnhance.Contrast(im).enhance(1.05)
    # 4) 草叶碎笔触叠加（柔光式低强度混合）
    sp = speckle_layer(im.size, count=26000)
    arr  = np.asarray(im).astype(np.float32)
    spa  = np.asarray(sp).astype(np.float32)
    lum  = arr.mean(axis=2, keepdims=True) / 255.0
    # 亮度越低的地方笔触越明显（草丛处加密），强度 12%
    strength = 0.12 * (0.5 + 0.5 * (1 - lum))
    out = arr * (1 - strength) + spa * strength
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    # 5) 再轻度锐化一次，把笔触变"草"
    im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    return im

def side_by_side(a, b, cell=512):
    cmp_img = Image.new("RGB", (cell * 2 + 8, cell + 30), (24, 24, 24))
    ra = a.convert("RGB").resize((cell, cell), Image.LANCZOS)
    rb = b.convert("RGB").resize((cell, cell), Image.LANCZOS)
    cmp_img.paste(ra, (0, 30)); cmp_img.paste(rb, (cell + 8, 30))
    d = ImageDraw.Draw(cmp_img)
    d.text((10, 8), "LEFT: current (512)", fill=(255, 255, 255))
    d.text((cell + 18, 8), "RIGHT: enhanced (1024)", fill=(255, 255, 0))
    return cmp_img

def main():
    apply = "--apply" in sys.argv
    os.makedirs(OUT_DIR, exist_ok=True)
    src = Image.open(GAME_GRASS)
    print("增强中...")
    out = enhance(src)
    out.save(OUT_LOCAL)
    print("  成品 ->", OUT_LOCAL)
    side_by_side(src, out).save(OUT_CMP)
    print("  对比图 ->", OUT_CMP)
    if not apply:
        print("预览模式：未替换游戏文件。满意后加 --apply 重跑即替换。")
        return
    if not os.path.isfile(BACKUP):
        src.save(BACKUP)
        print("  原版备份 ->", BACKUP)
    out.save(GAME_GRASS)
    print("  已替换 ->", GAME_GRASS)
    print("完成。打开 Godot 编辑器自动重新导入。")

if __name__ == "__main__":
    main()
