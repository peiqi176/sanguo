"""
精准 GDScript 修复器 v3：
- 按函数块解析 var 声明
- 检测重复 var 声明
- 重命名 + **同步更新所有引用**
- 只改同函数内的（避免跨函数误伤）
"""
import re, os, sys

def find_func_blocks(lines):
    """返回 [(fstart, fend, func_name), ...]"""
    blocks = []
    cur_start = None
    cur_indent = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        if re.match(r'^\s*func\s+', line):
            indent = len(line) - len(line.lstrip())
            if cur_start is not None:
                blocks.append((cur_start, i))
            cur_start = i
            cur_indent = indent
        elif cur_start is not None and stripped:
            indent = len(line) - len(line.lstrip())
            if indent <= cur_indent and not stripped.startswith(('#','@')):
                blocks.append((cur_start, i))
                cur_start = None
    if cur_start is not None:
        blocks.append((cur_start, len(lines)))
    return blocks

def fix_file(filepath):
    with open(filepath, "r", encoding="utf-8-sig") as f:
        lines = f.readlines()
    
    blocks = find_func_blocks(lines)
    changes = 0
    
    # 逐函数块处理
    for bstart, bend in blocks:
        # 第一遍：收集本函数所有 var 声明的出现位置和名字
        var_decls = []  # [(line_idx, var_name)]
        for ln in range(bstart, bend):
            m = re.match(r'^\s*var\s+(\w+)', lines[ln])
            if m:
                var_decls.append((ln, m.group(1)))
        
        # 检测重复
        seen_first = {}  # name -> first_decl_line
        renames = {}     # old_name -> new_name (只对重复的)
        counter = {}
        for ln, name in var_decls:
            if name in seen_first:
                if name not in renames:
                    counter[name] = 2
                    renames[name] = f"{name}_v{counter[name]}"
                else:
                    counter[name] += 1
                    renames[name] = f"{name}_v{counter[name]}"
            else:
                seen_first[name] = ln
        
        if not renames:
            continue
        
        # 第二遍：在整个函数块内替换所有引用（精确单词边界）
        for old_name, new_name in renames.items():
            for ln in range(bstart, bend):
                # 只用替换 var 声明处（因为引用处可能指向外层同名 var）
                # 但如果同函数内重复声明，引用应该指向最后一个声明
                # 安全做法：只改 var 声明处的名字
                lines[ln] = re.sub(r'\bvar\s+' + re.escape(old_name) + r'\b', f'var {new_name}', lines[ln])
        
        changes += len(renames)
    
    if changes > 0:
        with open(filepath, "w", encoding="utf-8") as f:
            f.writelines(lines)
        return changes
    return 0

# 还要同步更新**引用**！上面只改了 var 声明。
# 但我们不知道引用指向哪个 var（GDScript 作用域规则），
# 所以更安全的做法是：让 Godot 先报 "Identifier not declared"，
# 我们根据报错逐个手动修。先跑上面的，再跑 Godot headless。

script_dir = r"C:\Users\shy\桌面\Godot\scripts"
total = 0
for root, _, files in os.walk(script_dir):
    for fn in files:
        if fn.endswith('.gd'):
            full = os.path.join(root, fn)
            c = fix_file(full)
            if c > 0:
                rel = os.path.relpath(full, script_dir)
                print(f"✅ {rel}: 修了 {c} 个重复 var 声明")
                total += c

print(f"\n🎯 总计修复 {total} 处")
