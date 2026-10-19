# -*- coding: utf-8 -*-
"""
把所有 ScaffoldMessenger.of(context).showSnackBar(
   SnackBar(content: Text('...'))
) 统一改写成 CenterToast.show(context, '...')

SnackBar 会从底部升起并顶起底部导航 / 中间发布按钮，改成屏幕中间浮层。
只处理单层 SnackBar + Text 的简单形态，复杂的保留原样并打印出来人工处理。
"""
import re
import pathlib

ROOT = pathlib.Path(r"C:\fishing_app\lib")

# 匹配：ScaffoldMessenger.of(context)\n?\s*..showSnackBar( SnackBar(content: Text(X)) )
PATTERN = re.compile(
    r"ScaffoldMessenger\.of\(context\)\s*"
    r"(?:\s*\.\s*\.\s*hideCurrentSnackBar\(\)\s*)?"
    r"(?:\s*\.\s*)?"
    r"showSnackBar\(\s*(?:const\s+)?SnackBar\(\s*content:\s*Text\((?P<arg>.*?)\)\s*,?\s*\)\s*\)",
    re.S,
)

unhandled = []

for path in ROOT.rglob("*.dart"):
    if path.name == "center_toast.dart":
        continue
    src = path.read_text(encoding="utf-8")
    if "showSnackBar" not in src:
        continue

    out = []
    pos = 0
    changed = 0
    for m in PATTERN.finditer(src):
        out.append(src[pos:m.start()])
        arg = m.group("arg").strip()
        # 去掉包裹的 const 影响；保留表达式本体
        out.append(f"CenterToast.show(context, {arg})")
        pos = m.end()
        changed += 1
    out.append(src[pos:])
    new = "".join(out)

    if changed == 0:
        continue

    # 补 import
    if "widgets/center_toast.dart" not in new:
        rel = "widgets/center_toast.dart"
        if path.parent.name == "widgets":
            imp = "import 'center_toast.dart';\n"
        else:
            imp = f"import '../{rel}';\n"
        # 插到最后一条 import 之后
        lines = new.split("\n")
        last = 0
        for i, ln in enumerate(lines):
            if ln.startswith("import "):
                last = i
        lines.insert(last + 1, imp.rstrip("\n"))
        new = "\n".join(lines)

    path.write_text(new, encoding="utf-8")
    print(f"{path.relative_to(ROOT)}: {changed} 处")

# 检查残留
print("\n--- 仍有 showSnackBar 的文件 ---")
for path in ROOT.rglob("*.dart"):
    src = path.read_text(encoding="utf-8")
    if "showSnackBar" in src:
        for i, ln in enumerate(src.split("\n"), 1):
            if "showSnackBar" in ln:
                print(f"{path.relative_to(ROOT)}:{i}: {ln.strip()}")
