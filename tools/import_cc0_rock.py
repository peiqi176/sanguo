# -*- coding: utf-8 -*-
"""把 ambientCG CC0 岩石贴图导入资产管线。

用法:
  python import_cc0_rock.py <Color.jpg 路径> <槽位: rock|rock2|rock3> [目标亮度]
步骤: 原生无缝(不做 feather，ambientCG 本身无缝) -> 亮度对齐场景口径 -> 2048² LANCZOS
     -> 旧图备份到 _backup/cc0_20261028_<槽位>.png -> 覆盖 assets/terrain/<槽位>.png
协议: ambientCG 全站 CC0，免费商用、无需署名。
"""
import os, shutil, sys
import numpy as np
from PIL import Image

OUT_DIR = r"C:/Users/shy/桌面/Godot/assets/terrain"
BACKUP_DIR = os.path.join(OUT_DIR, "_backup")
DEFAULT_LUM = 97.0  # 当前 rock.png 场景验证过的平均亮度口径


def lum(im: Image.Image) -> float:
    a = np.asarray(im.convert("RGB").resize((64, 64))).astype(np.float32)
    return float((0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]).mean())


def main() -> None:
    src, slot = sys.argv[1], sys.argv[2]
    target = float(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_LUM

    im = Image.open(src).convert("RGB")

    # 非正方形源图先居中裁方（ambientCG 有 512x1024 / 1024x512 的包），
    # 否则 resize 到 2048² 会把石板横向/纵向拉变形
    w, h = im.size
    if w != h:
        s = min(w, h)
        im = im.crop(((w - s) // 2, (h - s) // 2, (w + s) // 2, (h + s) // 2))
        print(f"非正方形 {w}x{h} -> 居中裁方 {s}x{s}")

    # 亮度对齐：整体乘法缩放，保留色相与饱和度；系数限幅防漂白
    cur = lum(im)
    factor = max(0.6, min(1.8, target / max(cur, 1.0)))
    arr = np.asarray(im).astype(np.float32) * factor
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    print(f"亮度对齐: {cur:.0f} -> {lum(im):.0f} (factor {factor:.3f})")

    im = im.resize((2048, 2048), Image.LANCZOS)

    out_path = os.path.join(OUT_DIR, f"{slot}.png")
    backup = os.path.join(BACKUP_DIR, f"cc0_20261028_{slot}.png")
    if os.path.isfile(out_path) and not os.path.isfile(backup):
        shutil.copy2(out_path, backup)
        print("旧图已备份 ->", backup)
    im.save(out_path)
    print("已写入", out_path, im.size)


if __name__ == "__main__":
    main()
