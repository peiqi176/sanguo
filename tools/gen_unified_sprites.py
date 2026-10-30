# -*- coding: utf-8 -*-
"""
统一锚点精灵生成器（Agnes Image 2.5 Flash）
============================================
为什么重写：旧素材是不同时期、不同提示词、不同视角凑出来的，
贴地公式自动化之后，**视角不统一比贴地不准更显眼** —— 一群兵站在一起时
有的像正面、有的像侧面、有的像俯视，怎么调都"歪得很整齐"。

本脚本把"锚点"固定成不可改的一段（BOOK），每个实体只写自己的身份段（SUBJECT），
生成完统一做后处理：抠绿底 → 去溢色 → 裁到内容 → 按同一比例缩放到统一内容高度
→ 脚底对齐画布底边 → 居中。

用法：
  python tools/gen_unified_sprites.py --only sword,peasant,government --out assets/sprites_v2
  python tools/gen_unified_sprites.py --all --out assets/sprites_v2
"""
import argparse
import base64
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_MAP = os.path.join(ROOT, "config", "asset_map.json")
API_URL = "https://apihub.agnes-ai.com/v1/images/generations"
MODEL = "agnes-image-2.5-flash"

# ============================ 锚点（不许改） ============================
# 相机：俯角 45° / 偏航 45°（与 CameraController 的默认视角一致）
# 光 ：左上 45° 入射，右上为暗部
# 底 ：脚底（或建筑地基）贴齐内容底边，不画地面与投影
BOOK_UNIT = (
    "2.5D 即时战略游戏素材，帝国时代4式干净半写实插画风格，三国时期中国古典军制。"
    "单一角色全身完整入画，正面朝向观众，等距视角（相机俯角45度、偏航0度），"
    "双脚并排站立、脚底贴齐画面最底边，头顶不碰画布上沿。"
    "光源来自左上方45度，右侧与下方为暗部，左肩与盔甲上缘有明确高光。"
    "背景必须是完全透明的 PNG alpha 通道：不要画地面、投影、阴影、倒影、边框，"
    "也不要画透明棋盘格图案（那是软件界面，不是素材）。"
    "轮廓边缘锐利干净，色块分明，不糊不虚；画面里只有这一个对象，不要任何文字与装饰。"
)
BOOK_BUILDING = (
    "2.5D 即时战略游戏素材，帝国时代4式干净半写实插画风格，三国时期中国古典木构建筑。"
    "单体建筑完整入画，等距投影（相机俯角45度、偏航45度），能同时看到正面与右侧面，"
    "材质与形制严格按前面的身份描述来定（青瓦或茅草顶、白灰墙或夯土墙或原木，地基贴齐画面最底边）。"
    "光源来自左上方45度，右侧面与下方为暗部。"
    "背景必须是完全透明的 PNG alpha 通道。"
    "画面底部只允许出现建筑自身的台基，绝对不要画草地、泥土、石砖地坪、水面、天空或任何地面铺装；"
    "不要画投影、阴影、倒影、边框、文字，也不要画透明棋盘格图案。"
    "轮廓锐利，瓦当与斗拱细节清晰，画面里只有这一栋建筑。"
)

# ============================ 每个实体的身份段 ============================
# 这一段是"不雷同"的来源：装备、姿态、标志物必须各不相同
SUBJECT = {
    # ---- 单位 ----
    "peasant": "农夫，粗麻短褐与草鞋，头缠青布巾，赤手空拳，肩上搭一条白粗布汗巾，微微前倾的劳作站姿",
    "sword": "刀兵，蜀汉墨绿战袍配皮甲，头戴铁盔，右手持环首直刀斜指地面，左臂挎一面小圆木盾",
    "spear": "枪兵，灰色札甲，头戴顶盔，双手握一杆长枪竖立于身侧，枪尖朝上，腰间挂短剑",
    "archer": "弓手，深褐轻甲，头戴软帽，左手持单体弓垂下，背后斜挂箭袋，右手自然垂放在箭袋旁",
    "sentinel": "郎勇，赤红战袄配黑色胸甲，头裹红巾，手持一柄长柯斧，斧刃宽大，站姿沉稳",
    "axeman": "刀斧手，褐色皮甲外披一小块兽皮护肩，双手握一柄双刃大斧斜扛在右肩，臂膀粗壮，站姿开阔",
    "crossbow": "弩手，青灰布甲，头戴窄檐帽，双手平端一具木托弩，弩臂朝前，腰侧挂弩箭筒",
    "zhuge_nu": "诸葛弩手，深绿军服，背一只方形连弩箭匣，手持可连发的木弩，弩身有弦槽",
    "xiliang_tieqi": "西凉铁骑，全身玄色重铠，骑一匹披马铠的黑马，手持长矛，马首朝前",
    "tujiang_qi": "突将骑，赤色披风，身披鳞甲，骑一匹枣红马，右手举长刀，马匹前蹄微抬",
    "trebuchet": "投石车，木构配重式投石机，粗大木臂与石弹筐，四轮木架，整体朝右前方",
    "ram": "冲车，木架尖顶盖铁皮，前端一根包铁撞木，四轮，两侧挂生牛皮",
    "ladder": "攻城云梯，一架极长的木梯斜靠在双轮木底盘上，梯身有密集横档、梯顶有两只铁挂钩；画面里不要出现任何士兵",
    "supply_cart": "辎重车，一辆双轮木车，车上高高堆满麻袋粮草与一捆捆箭矢并用麻绳捆扎，车头伸出一根牵引横木；不要拉车的牲畜与人",
    "straw_boat": "草船，小型木船，船身覆满草束，竖一根简单桅杆，船头略翘",
    "warship": "战船，中等楼船，两层甲板，船首有撞角，侧面有射孔与盾牌",
    # ---- 建筑 ----
    "government": "官府，三开间重檐木构大堂，青瓦屋顶带正脊鸱吻，朱红廊柱，石砌台基与台阶，门前一对石狮",
    "house": "民居，单层夯土墙小屋，茅草顶，木门木窗，屋角堆着柴垛",
    "paifang": "牌楼，四柱三间木牌坊，飞檐青瓦顶，横匾无字，柱脚有石鼓",
    "warehouse": "仓廪，长方形木构仓房，高台基防潮，双坡瓦顶，正面两扇厚重木门",
    "farm": "农田地块，一块方形田地被土埂分成长条田垄，垄上种着成行的嫩绿秧苗，地块边缘用泥土垒起矮埂；地块只保留这一块田地本身的边界，四周不要延展成大片草地",
    "fishery": "捕鱼屋，一座架在木桩上的小木屋，屋前挂着一张晾晒的渔网与两只竹篓，屋下只有几根木桩；不要画河水与岸边的地",
    "ranch": "牧场，一段矮木栅栏围出的小块场地，场地内左侧一座茅草顶小草棚，旁边一堆干草垛；只保留栅栏围出的那一小块地，四周不要扩散成草原",
    "workshop": "作坊，开敞式木工棚，一面墙挂着工具，屋前一张工作台与木料堆",
    "mine": "矿洞，一段被凿开的岩壁断面，中间一个幽深洞口用原木支架加固，洞口右侧堆着一小堆矿石与一辆木矿车；只保留岩壁这一块，四周不要草地与树木",
    "stable": "马厩，长条木棚，正面开敞可见分隔马栏，屋顶为瓦顶，门前有草料槽",
    "barracks_sword": "刀兵营，一座长方形木构营房，正面开门，门楣上挂一块刻着刀形的木牌，门前立着一座插满环首刀的兵器架",
    "barracks_spear": "枪兵营，一座长方形木构营房，正门门楣挂一块刻着枪形的木牌，门前一座插满长枪的木架与几面靠在墙上的木盾",
    "barracks_archer": "弓兵营，一座木构营房，门前立着两只草编箭靶与一座挂弓的木架，屋檐下挂着一排箭囊",
    "shipyard": "造船厂，一座敞开式木构大棚，棚内横着一艘未完工的船肋骨骨架，棚外堆着木料与几支船桨；不要画水面与沙滩",
    "temple": "寺庙，单檐歇山式殿宇，青瓦屋顶带脊兽与正脊，朱红墙身，殿前三阶石台与一只铜香炉；不要画寺院围墙与地面铺装",
    "market": "市场，三座并排的带布篷木摊台，摊上堆着粮袋、布匹与陶罐，摊边立一根拴马桩；不要画地面与人群",
    "inn": "客栈，两层木楼，二层带挑廊与灯笼，一层门面挂酒旗",
    "arrow_tower": "箭塔，方形夯土塔身配木构望楼，塔顶有女墙与射孔，四角立柱",
    "wall_stone": "一段石砌城墙，不是房屋：条石垒砌的长条墙体，顶面有连续凹凸的垛口与一条巡道，墙身自上而下微微收分，墙面能看出石块接缝；不要屋顶、不要门窗",
    "gate_stone": "一座石砌城门，不是房屋：厚重条石城墙中间开一个半圆拱门洞，两扇包铁钉的木门半掩，门洞上方是带垛口的墙顶与一小段城楼；不要大殿屋顶",
    "wall_wood": "一段木寨墙，不是房屋：原木一根根并排竖立埋入土中，顶端削成尖头，墙中部钉有两道横向加固木梁；不要屋顶、不要门窗",
    "gate_wood": "一座木寨门，不是房屋：两侧原木寨墙之间两扇厚重的双开木门，门面横钉三道铁条，门楣上方一个小型坡顶雨棚；不要大殿屋顶",
}

# 内容高度目标（像素）。同一类别内必须一致 —— 这就是"统一锚点"的量化部分。
TARGET = {
    "unit": (256, 256, 200),      # 画布宽, 画布高, 内容高
    "building": (512, 512, 400),
}


def load_key() -> str:
    key = os.environ.get("AGNES_API_KEY", "")
    if key:
        return key
    for prof in ("~/.bash_profile", "~/.profile", "~/.zshrc", "~/.bashrc",
                 os.path.expanduser("~/.workbuddy/.env")):
        path = os.path.expanduser(prof)
        if not os.path.isfile(path):
            continue
        for line in io.open(path, encoding="utf-8", errors="ignore"):
            m = re.search(r"AGNES_API_KEY\s*=\s*['\"]?([^'\"\n]+)", line)
            if m:
                return m.group(1).strip()
    return ""


def key_out(img: Image.Image) -> Image.Image:
    """抠掉 #00FF00 绿底并去溢色。返回 RGBA。"""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            other = max(r, b)
            # 绿得明显超过红/蓝 → 背景
            if g > 90 and g > other * 1.35 and (g - other) > 28:
                px[x, y] = (0, 0, 0, 0)
            elif g > other:
                # 边缘半绿：压掉溢出的绿，保留原亮度感
                px[x, y] = (r, min(g, int(other * 1.08) + 6), b, a)
    return img



WHITE_KEY = 236         # 判定"卡片白"的亮度下限
WHITE_KEY_SAT = 14      # 同时要求接近中性灰（防止把米白衣服当背景）

def strip_card_bg(img: Image.Image) -> Image.Image:
    """去掉模型自带的浅色卡片底。

    Agnes 常把"透明背景"画成一张浅灰/白的卡片（有时是从灰到白的渐变），
    alpha 只留在卡片外面，于是素材带一个白框。

    做法：把"很亮 + 很中性"的像素标成可扩散区，从四边做连通域扩散，
    只清理**与画面边缘连通**的白 —— 所以盔甲高光、白袍都不会被误伤
    （它们被深色轮廓包住，连不到边）。
    """
    from collections import deque
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    open_mask = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                open_mask[y][x] = True
            elif max(r, g, b) <= 12:
                # 纯黑底板：模型有时会先铺一块黑底再画建筑（农场那张就是），
                # 阈值压到 12 是为了不误伤建筑自身的描边与暗部。
                open_mask[y][x] = True
            elif min(r, g, b) >= WHITE_KEY and (max(r, g, b) - min(r, g, b)) <= WHITE_KEY_SAT:
                open_mask[y][x] = True
    q = deque()
    for x in range(w):
        if open_mask[0][x]:
            q.append((x, 0))
        if open_mask[h - 1][x]:
            q.append((x, h - 1))
    for y in range(h):
        if open_mask[y][0]:
            q.append((0, y))
        if open_mask[y][w - 1]:
            q.append((w - 1, y))
    seen = [[False] * w for _ in range(h)]
    while q:
        x, y = q.popleft()
        if seen[y][x]:
            continue
        seen[y][x] = True
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and open_mask[ny][nx]:
                q.append((nx, ny))
    for y in range(h):
        row = seen[y]
        for x in range(w):
            if row[x]:
                px[x, y] = (0, 0, 0, 0)
    return img

def normalize(img: Image.Image, canvas_w: int, canvas_h: int, content_h: int,
              pad_bottom: int = 3) -> Image.Image:
    """裁到内容 → 等比缩放到统一内容高度 → 脚底对齐底边 → 居中贴到画布。"""
    bbox = img.getbbox()
    if bbox is None:
        return Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    img = img.crop(bbox)
    scale = float(content_h) / float(img.height)
    new_w = max(1, int(round(img.width * scale)))
    new_h = content_h
    # 内容比画布宽时按宽度兜底，避免裁掉手臂/屋檐
    max_w = canvas_w - 8
    if new_w > max_w:
        k = float(max_w) / float(new_w)
        new_w = max_w
        new_h = max(1, int(round(new_h * k)))
    img = img.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    canvas.paste(img, ((canvas_w - new_w) // 2, canvas_h - new_h - pad_bottom), img)
    return canvas


def call_api(key: str, prompt: str) -> bytes:
    payload = json.dumps({
        "model": MODEL,
        "prompt": prompt,
        "size": "1K",
        "ratio": "1:1",
        "return_base64": True,
    }).encode("utf-8")
    req = urllib.request.Request(API_URL, data=payload, method="POST")
    req.add_header("Authorization", "Bearer " + key)
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    item = (data.get("data") or [{}])[0]
    b64 = item.get("b64_json")
    if not b64:
        raise RuntimeError("返回里没有 b64_json: %s" % str(data)[:200])
    return base64.b64decode(b64)


def gen_one(key: str, kind: str, eid: str, out_dir: str, overwrite: bool) -> bool:
    dst = os.path.join(out_dir, "%s.png" % eid)
    if os.path.isfile(dst) and not overwrite:
        print("  [skip] %s 已存在" % eid)
        return True
    sub = SUBJECT.get(eid)
    if not sub:
        print("  [--] %s 没有写身份段，跳过（避免生成雷同素材）" % eid)
        return False
    book = BOOK_UNIT if kind == "unit" else BOOK_BUILDING
    prompt = sub + "。" + book
    for attempt in range(4):
        try:
            raw = call_api(key, prompt)
            img = Image.open(io.BytesIO(raw))
            img = strip_card_bg(key_out(img))
            cw, ch, chh = TARGET[kind]
            img = normalize(img, cw, ch, chh)
            img.save(dst)
            print("  [OK] %-16s %s" % (eid, dst))
            return True
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")[:160]
            if e.code in (429, 503):
                wait = 10 * (attempt + 1)
                print("  [%d] %s 限流/排队，等 %ds" % (e.code, eid, wait))
                time.sleep(wait)
                continue
            print("  [HTTP %d] %s %s" % (e.code, eid, body))
            return False
        except Exception as e:
            print("  [ERR] %s %s" % (eid, e))
            time.sleep(5)
    return False



def reprocess_dir(out_dir: str) -> None:
    import glob
    files = sorted(glob.glob(os.path.join(out_dir, "*.png")))
    for f in files:
        eid = os.path.splitext(os.path.basename(f))[0]
        img = Image.open(f)
        was = img.size
        img = strip_card_bg(img.convert("RGBA"))
        kind = "building" if was[0] > 300 else "unit"
        cw, ch, chh = TARGET[kind]
        img = normalize(img, cw, ch, chh)
        img.save(f)
        bbox = img.getbbox()
        print("  [fix] %-16s -> bbox=%s" % (eid, str(bbox)))

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="逗号分隔的实体 id")
    ap.add_argument("--all", action="store_true", help="生成 SUBJECT 里全部条目")
    ap.add_argument("--out", default="assets/sprites_v2")
    ap.add_argument("--overwrite", action="store_true")
    ap.add_argument("--reprocess", action="store_true", help="只对已有文件重跑抠底/归一化")
    ap.add_argument("--jobs", type=int, default=1, help="并发数（3 比较稳）")
    args = ap.parse_args()

    out_dir = os.path.join(ROOT, args.out)
    os.makedirs(out_dir, exist_ok=True)
    if args.reprocess:
        reprocess_dir(out_dir)
        return
    key = load_key()
    if not key:
        print("[ERROR] 没有 AGNES_API_KEY")
        sys.exit(1)

    # ⚠ 类别必须来自 units.json / buildings.json 这两个"游戏真实清单"。
    # 之前用 asset_map.json 反推：凡是没登记的（mine/market/temple/wall_wood...）
    # 就默认当单位 → 用 256 的单位画布去画一栋房子，画面里全是"人站在山洞里"。
    kinds = {}
    for eid in json.load(io.open(os.path.join(ROOT, "config", "units.json"), encoding="utf-8-sig"))["units"]:
        kinds[eid] = "unit"
    for eid in json.load(io.open(os.path.join(ROOT, "config", "buildings.json"), encoding="utf-8-sig"))["buildings"]:
        kinds[eid] = "building"

    if args.all:
        ids = list(SUBJECT.keys())
    else:
        ids = [s.strip() for s in args.only.split(",") if s.strip()]
    if not ids:
        print("没有指定 --only 或 --all")
        sys.exit(1)

    ok = 0
    todo = []
    for eid in ids:
        kind = kinds.get(eid)
        if kind is None:
            print("  [--] %s 在 units.json/buildings.json 里都找不到，跳过" % eid)
            continue
        todo.append((kind, eid))
    if args.jobs > 1:
        # 串行一张要 30~40 秒，几十张就是十几分钟。并发 3 路既快又不容易被限流。
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            futs = [ex.submit(gen_one, key, k, e, out_dir, args.overwrite) for (k, e) in todo]
            for f in futs:
                if f.result():
                    ok += 1
    else:
        for (k, e) in todo:
            print("→ %s (%s)" % (e, k))
            if gen_one(key, k, e, out_dir, args.overwrite):
                ok += 1
    print("\n完成 %d / %d" % (ok, len(todo)))


if __name__ == "__main__":
    main()
