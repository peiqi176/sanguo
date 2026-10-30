# -*- coding: utf-8 -*-
"""把用户自制的泥土地贴图（AoE4 风格）导入资产管线。
原图 1920x1080 → 中心裁方 → 环绕混合无缝化 → 1024² → assets/terrain/dirt.png
旧贴图备份为 dirt_classic.png（shader 缺图兜底不受影响）。
"""
import os, shutil
import numpy as np
from PIL import Image

SRC = r"C:/Users/shy/.workbuddy/clipboard-images/clipboard-2026-10-27T03-31-35-537Z-7eee1e41.jpg"
OUT_DIR = r"C:/Users/shy/桌面/Godot/assets/terrain"
OUT = os.path.join(OUT_DIR, "dirt.png")
BACKUP = os.path.join(OUT_DIR, "dirt_classic.png")


def make_seamless(im, feather_ratio=0.15):
    """环绕混合法：左右/上下边缘交叉渐变，消除平铺接缝（与 optimize_grass.py 同款）。"""
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


def main() -> None:
    im = Image.open(SRC)
    w, h = im.size
    s = min(w, h)
    im = im.crop(((w - s) // 2, (h - s) // 2, (w + s) // 2, (h + s) // 2))
    im = make_seamless(im, 0.15)
    im = im.resize((1024, 1024), Image.LANCZOS)

    if os.path.isfile(OUT) and not os.path.isfile(BACKUP):
        shutil.copy2(OUT, BACKUP)
        print("旧泥土贴图已备份 ->", BACKUP)
    im.save(OUT)
    print("已写入", OUT, im.size)


if __name__ == "__main__":
    main()
