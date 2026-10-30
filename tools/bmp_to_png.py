"""
批量 BMP → PNG 转换 + 背景抠图
傲世三国原始 BMP 用纯黑 (0,0,0) 作背景
输出透明背景 PNG 到 assets/sprites/
"""
import os, sys
from PIL import Image

SRC = r"C:\Users\shy\桌面\三国素材"
DST = r"C:\Users\shy\桌面\Godot\assets\sprites"
BLACK = (0, 0, 0)
TOLERANCE = 15  # 允许一点点误差（抗锯齿边缘）

os.makedirs(DST, exist_ok=True)

count = 0
skipped = 0
errors = 0
errors_list = []

for fname in os.listdir(SRC):
    if not fname.lower().endswith(".bmp"):
        continue
    src_path = os.path.join(SRC, fname)
    dst_name = os.path.splitext(fname)[0] + ".png"
    dst_path = os.path.join(DST, dst_name)
    
    # 跳过已存在的（如果之前转过了）
    if os.path.exists(dst_path) and os.path.getsize(dst_path) > 500:
        skipped += 1
        continue
    
    try:
        img = Image.open(src_path).convert("RGBA")
        # 抠黑背景：任何 R/G/B 都 < TOLERANCE 的像素变透明
        data = img.getdata()
        new_data = []
        for px in data:
            r, g, b, a = px
            if r <= TOLERANCE and g <= TOLERANCE and b <= TOLERANCE:
                new_data.append((0, 0, 0, 0))
            else:
                new_data.append(px)
        img.putdata(new_data)
        img.save(dst_path, "PNG")
        count += 1
        if count % 200 == 0:
            print(f"  已转 {count} 个...")
    except Exception as e:
        errors += 1
        errors_list.append((fname, str(e)))

print(f"\n✅ 新转换: {count} 个")
print(f"⏭ 已存在跳过: {skipped} 个")
print(f"❌ 失败: {errors} 个")
if errors_list:
    print("失败文件前10个:")
    for f, e in errors_list[:10]:
        print(f"  {f}: {e}")
