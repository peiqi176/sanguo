#!/usr/bin/env python3
"""gen_terrain_tile.py — 生成"可无缝平铺"的地形贴图，并做接缝检测/修复。

用法：
  python tools/gen_terrain_tile.py grass "温带草地，低矮短草，少量泥土斑" 2
  （参数：贴图名  中文内容描述  生成张数）

依赖：requests（或标准库 urllib 兜底）、Pillow、numpy
密钥读取顺序：环境变量 AGNES_API_KEY → 本目录 agnes.key

为什么需要这个脚本：
  地形 shader 会把每张贴图按 world_size 平铺上百次，**任何接缝都会变成规则网格**，
  这是 2.5D/3D 地形最常见的"廉价感"来源。Agnes 生成的图几乎不可能天生 100% 无缝，
  所以这里做两件事：① 生成时用强锚点压制暗角与方向光；② 生成本地做接缝修复 + 量化打分。
"""
import json
import os
import sys
import time
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
OUT_DIR = os.path.join(PROJ, "assets", "terrain", "_gen")
API = "https://apihub.agnes-ai.com/v1/images/generations"
MODEL = "agnes-image-2.5-flash"

# 强锚点：这几个词是"能不能平铺"的关键，缺一个就会出现可见缝或暗角
ANCHOR = (
    "无缝可平铺贴图 seamless tileable texture，正交俯视正投影 top-down orthographic，"
    "无方向性光源，正上方均匀漫射光照，四角与四边亮度一致，无暗角 vignette，无渐变，无边框，"
    "画面四周与中心密度一致，左右边缘与上下边缘可完美拼接，"
    "游戏地形地表材质 albedo map，平铺无重复感，高细节写实"
)


def load_key() -> str:
    k = os.environ.get("AGNES_API_KEY", "").strip()
    if k:
        return k
    p = os.path.join(HERE, "agnes.key")
    if os.path.exists(p):
        return open(p, encoding="utf-8").read().strip()
    raise SystemExit("找不到 API Key：设置 AGNES_API_KEY 或写入 tools/agnes.key")


def api_post(payload: dict, key: str) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        API, data=data,
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
        method="POST",
    )
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")[:300]
            if e.code in (429, 503):
                wait = 8 * (attempt + 1)
                print(f"  [{e.code}] 限流/队列满，{wait}s 后重试… {body}")
                time.sleep(wait)
                continue
            raise SystemExit(f"HTTP {e.code}: {body}")
    raise SystemExit("重试次数用尽")


def download(url: str, dst: str) -> None:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=180) as r:
        open(dst, "wb").write(r.read())


def seam_score(path: str) -> float:
    """左右/上下边缘的像素差均值；越小越接近无缝。经验：<8 基本看不出，>15 会有网格感。"""
    from PIL import Image
    import numpy as np
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    lr = float(np.abs(a[:, 0, :] - a[:, -1, :]).mean())
    tb = float(np.abs(a[0, :, :] - a[-1, :, :]).mean())
    return max(lr, tb)


def heal_seams(path: str, band_ratio: float = 0.05) -> str:
    """把任意图变成真正可平铺的贴图（标准"偏移过滤"法）。

    原理：
      ① 把图循环滚动半张 —— 原来的左右/上下边界被移到画面中央，
         新的四边来自图片内部相邻像素，天然连续（接缝差值降到自然噪声级）。
      ② 再对中央那个"十字缝"做窄带对称混合，把断裂处揉开。
         因为只动画面中心，四边的无缝性不受影响。

    这比"直接淡化四边"正确得多：淡化四边只改边缘像素，对"整图有暗角/渐变"这种
    真正的病根毫无作用，而滚动之后暗角也被切成两半、不再贴在边界上。
    """
    from PIL import Image
    import numpy as np

    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    h, w, _ = a.shape
    out = np.roll(a, (h // 2, w // 2), axis=(0, 1))     # ① 错位半图
    b = max(2, int(min(w, h) * band_ratio))
    cx, cy = w // 2, h // 2

    # ② 修中央竖缝
    for i in range(b):
        t = i / float(b)                     # 0 = 紧贴缝，1 = 带外
        lx, rx = cx - 1 - i, cx + i
        if lx < 0 or rx >= w:
            break
        avg = (out[:, lx, :] + out[:, rx, :]) * 0.5
        k = (1.0 - t) * 0.85                 # 越靠缝混合越强
        out[:, lx, :] = out[:, lx, :] * (1.0 - k) + avg * k
        out[:, rx, :] = out[:, rx, :] * (1.0 - k) + avg * k

    # ③ 修中央横缝
    for i in range(b):
        t = i / float(b)
        uy, dy = cy - 1 - i, cy + i
        if uy < 0 or dy >= h:
            break
        avg = (out[uy, :, :] + out[dy, :, :]) * 0.5
        k = (1.0 - t) * 0.85
        out[uy, :, :] = out[uy, :, :] * (1.0 - k) + avg * k
        out[dy, :, :] = out[dy, :, :] * (1.0 - k) + avg * k

    healed = path.replace(".png", "_seamless.png")
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(healed)
    return healed


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        return
    name = sys.argv[1]
    desc = sys.argv[2] if len(sys.argv) > 2 else name
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 1

    key = load_key()
    prompt = f"{desc}。{ANCHOR}。"
    print(f"[{name}] prompt = {prompt}")

    for i in range(count):
        print(f"  生成第 {i + 1}/{count} 张 …")
        res = api_post({"model": MODEL, "prompt": prompt, "size": "1K", "ratio": "1:1"}, key)
        items = res.get("data") or []
        if not items:
            print("  没有返回图片：", json.dumps(res, ensure_ascii=False)[:300])
            continue
        url = items[0].get("url")
        dst = os.path.join(OUT_DIR, f"{name}_v{i + 1}.png")
        download(url, dst)
        s0 = seam_score(dst)
        healed = heal_seams(dst)
        s1 = seam_score(healed)
        print(f"    {os.path.basename(dst)}  原始接缝={s0:.1f}  修复后={s1:.1f}")
        time.sleep(2)
    print("完成，候选图在", OUT_DIR)


if __name__ == "__main__":
    main()
