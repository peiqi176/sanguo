# -*- coding: utf-8 -*-
"""草地优化：img2img 增强游戏当前 grass.png -> 无缝平铺 -> 备份并替换 assets/terrain/grass.png
用法：python optimize_grass.py [--apply]   # 不带 --apply 时只出预览，不动游戏文件
"""
import os, re, sys, io, json, time, base64
import urllib.request, urllib.error
import numpy as np
from PIL import Image

GAME_GRASS = r"C:/Users/shy/桌面/Godot/assets/terrain/grass.png"
BACKUP     = r"C:/Users/shy/桌面/最新素材/旧版与测试/terrain_grass_原版备份.png"
OUT_RAW    = r"C:/Users/shy/桌面/最新素材/旧版与测试/grass_新_原始.png"
OUT_FINAL  = r"C:/Users/shy/桌面/最新素材/旧版与测试/grass_新_无缝.png"
OUT_TILE   = r"C:/Users/shy/桌面/最新素材/旧版与测试/grass_新_2x2平铺预览.png"

API_URL = "https://apihub.agnes-ai.com/v1/images/generations"

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

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

_opener = urllib.request.build_opener(NoRedirect)

def gen_image(prompt, ref_path=None, size="1K", ratio="1:1", tries=4):
    payload = {
        "model": "agnes-image-2.5-flash",
        "prompt": prompt,
        "size": size,
        "ratio": ratio,
        "return_base64": True,
    }
    if ref_path:
        with open(ref_path, "rb") as f:
            b64 = base64.b64encode(f.read()).decode()
        payload["extra_body"] = {
            "image": ["data:image/png;base64," + b64],
            "response_format": "b64_json",
        }
    body = json.dumps(payload).encode("utf-8")
    for attempt in range(tries):
        try:
            req = urllib.request.Request(API_URL, data=body, method="POST")
            req.add_header("Authorization", "Bearer " + load_agnes_key())
            req.add_header("Content-Type", "application/json")
            with _opener.open(req, timeout=180) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            item = (data.get("data") or [{}])[0]
            b64 = item.get("b64_json")
            if b64:
                return base64.b64decode(b64)
            # 有些返回 url
            url = item.get("url")
            if url:
                with urllib.request.urlopen(url, timeout=120) as r:
                    return r.read()
            print(f"    [!] 异常返回: {str(data)[:200]}")
        except urllib.error.HTTPError as e:
            eb = e.read().decode("utf-8", "ignore")[:150]
            if e.code in (400, 401, 403):
                print(f"    [HTTP {e.code}] {eb}"); return None
            wait = 15 * (attempt + 1)
            print(f"    [{e.code}] 瞬时错误，等 {wait}s 重试... ({eb})")
            time.sleep(wait)
        except Exception as ex:
            print(f"    [ERR] {ex}"); time.sleep(10)
    return None

def make_seamless(im, feather_ratio=0.15):
    """环绕混合法：左右边缘交叉渐变、上下边缘交叉渐变，消除平铺接缝。"""
    im = im.convert("RGB")
    w, h = im.size
    arr = np.asarray(im).astype(np.float32)
    F = max(16, int(min(w, h) * feather_ratio))
    out = arr.copy()
    # 水平：右边缘与左边缘交叉渐变
    a = np.linspace(0.0, 1.0, F, dtype=np.float32)[None, :, None]
    out[:, -F:, :] = arr[:, -F:, :] * (1 - a) + arr[:, :F, :] * a
    # 垂直（在已处理水平的基础上）
    arr2 = out
    b = np.linspace(0.0, 1.0, F, dtype=np.float32)[:, None, None]
    out[-F:, :, :] = arr2[-F:, :, :] * (1 - b) + arr2[:F, :, :] * b
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))

def tile_preview(im, n=2, cell=512):
    t = Image.new("RGB", (cell * n, cell * n))
    s = im.resize((cell, cell), Image.LANCZOS)
    for y in range(n):
        for x in range(n):
            t.paste(s, (x * cell, y * cell))
    return t

PROMPT = (
    "Enhance this grass ground texture into a high-quality hand-painted RTS terrain texture "
    "in the style of Age of Empires IV: dense fine grass blades, rich olive-green color with "
    "subtle yellow-green and dark-green patches, small clover variation, painterly brushwork, "
    "even ambient lighting, no shadows, no objects, no trees, no rocks, no border, "
    "uniform seamless tileable texture filling the entire frame."
)

def main():
    apply = "--apply" in sys.argv
    print("[1/4] 读取当前游戏草地作为参考...")
    ref = GAME_GRASS
    print("[2/4] 调 Agnes img2img 增强草地...")
    raw = gen_image(PROMPT, ref_path=ref, size="1K", ratio="1:1")
    if not raw:
        print("[FAIL] 生成失败"); sys.exit(2)
    im = Image.open(io.BytesIO(raw)).convert("RGB")
    im = im.resize((1024, 1024), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT_RAW), exist_ok=True)
    im.save(OUT_RAW)
    print(f"    原始图 -> {OUT_RAW}")

    print("[3/4] 后处理无缝平铺 + 2x2 预览...")
    seamless = make_seamless(im)
    seamless.save(OUT_FINAL)
    tile_preview(seamless).save(OUT_TILE)
    print(f"    无缝图 -> {OUT_FINAL}")
    print(f"    平铺预览 -> {OUT_TILE}")

    if not apply:
        print("[4/4] 预览模式：未替换游戏文件。满意后加 --apply 重跑（会复用已生成的无缝图）。")
        return

    print("[4/4] 备份原版并替换进游戏...")
    os.makedirs(os.path.dirname(BACKUP), exist_ok=True)
    if not os.path.isfile(BACKUP):
        Image.open(GAME_GRASS).save(BACKUP)
        print(f"    原版备份 -> {BACKUP}")
    seamless.save(GAME_GRASS)
    print(f"    已替换 -> {GAME_GRASS} (1024x1024)")
    print("完成。打开 Godot 编辑器会自动重新导入。")

if __name__ == "__main__":
    main()
