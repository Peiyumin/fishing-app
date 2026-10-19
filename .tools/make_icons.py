# -*- coding: utf-8 -*-
"""
把设计稿方图（白色底 + 圆角 + 外阴影）做成 Android 启动图标。

产出：
  1. mipmap-*/ic_launcher.png      旧式方图图标（各密度）
  2. mipmap-*/ic_launcher_fore.png 自适应图标前景（透明底，内容缩到 66% 安全区）
  3. values/ic_launcher_background.xml  自适应图标底色（取自图中央像素）
  4. ic_launcher_round / 自适应 xml 由调用方生成

关键点：原图本身画了圆角和投影，直接塞进 launcher 会被系统再裁一次，
边缘出现白圈。所以先做「去白边 + 外阴影抹平」，把画布还给纯内容。
"""
from PIL import Image, ImageDraw
import os, sys, json

SRC = r"C:\Users\Administrator\.workbuddy\clipboard-images\clipboard-2026-10-19T04-17-33-857Z-9314c324.jpg"
RES = r"C:\fishing_app\android\app\src\main\res"

# 每个密度对应的旧式图标边长（dp 48 / 自适应 108）
DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}


def find_art_box(im):
    """找到圆角方图的实际边界：从四边向内扫描，跳过接近纯白的像素。"""
    w, h = im.size
    px = im.load()

    def is_white(c, tol=18):
        return c[0] > 255 - tol and c[1] > 255 - tol and c[2] > 255 - tol

    def row_colored(y):
        # 一行里超过 40% 不是白色，才算内容行
        n = sum(0 if is_white(px[x, y]) else 1 for x in range(0, w, 2))
        return n > (w // 2) * 0.4

    def col_colored(x):
        n = sum(0 if is_white(px[x, y]) else 1 for y in range(0, h, 2))
        return n > (h // 2) * 0.4

    top = next((y for y in range(h) if row_colored(y)), 0)
    bottom = next((y for y in range(h - 1, -1, -1) if row_colored(y)), h - 1)
    left = next((x for x in range(w) if col_colored(x)), 0)
    right = next((x for x in range(w - 1, -1, -1) if col_colored(x)), w - 1)
    return left, top, right + 1, bottom + 1


def square_crop(im, box):
    """在 box 基础上取正方形，居中。"""
    l, t, r, b = box
    cw, ch = r - l, b - t
    side = max(cw, ch)
    cx, cy = (l + r) / 2, (t + b) / 2
    l = int(round(cx - side / 2))
    t = int(round(cy - side / 2))
    r, b = l + side, t + side
    # 越界时向画布内平移
    if l < 0:
        r -= l
        l = 0
    if t < 0:
        b -= t
        t = 0
    if r > im.width:
        l -= (r - im.width)
        r = im.width
    if b > im.height:
        t -= (b - im.height)
        b = im.height
    return im.crop((l, t, r, b))


def main():
    im = Image.open(SRC).convert("RGB")
    print("src", im.size)
    box = find_art_box(im)
    print("art box", box)
    art = square_crop(im, box)
    print("art square", art.size)

    # 自适应图标的前景安全区：108dp 里只有中间 66dp 会被保证可见
    # 内容本身已占满方块，所以整体缩到 78% 留一点呼吸，避免圆角遮掉字
    for dpi, (legacy, adaptive) in DENSITIES.items():
        out_dir = os.path.join(RES, f"mipmap-{dpi}")
        os.makedirs(out_dir, exist_ok=True)

        # 旧式图标：满幅
        art.resize((legacy, legacy), Image.LANCZOS).save(
            os.path.join(out_dir, "ic_launcher.png"), optimize=True)

        # 自适应前景：透明底 + 内容居中缩到 78%
        fg = Image.new("RGBA", (adaptive * 2, adaptive * 2), (0, 0, 0, 0))
        inner = int(adaptive * 2 * 0.68)
        resized = art.resize((inner, inner), Image.LANCZOS).convert("RGBA")
        # 把正方形的外圈做成圆角，避免直角怼到系统圆形遮罩外
        mask = Image.new("L", (inner, inner), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, inner - 1, inner - 1], radius=int(inner * 0.22), fill=255)
        fg.paste(resized, ((adaptive * 2 - inner) // 2, (adaptive * 2 - inner) // 2), mask)
        fg.resize((adaptive, adaptive), Image.LANCZOS).save(
            os.path.join(out_dir, "ic_launcher_fore.png"), optimize=True)

    # 自适应图标底色：取原图中央偏上的像素（纯蓝渐变区）
    bg = im.getpixel((im.width // 2, int(im.height * 0.18)))
    print("bg", bg)

    # 预览大图，方便人工检查
    prev = art.resize((512, 512), Image.LANCZOS)
    prev.save(os.path.join(r"C:\fishing_app\.tools", "icon_preview.png"))

    with open(os.path.join(r"C:\fishing_app\.tools", "icon_meta.json"), "w", encoding="utf-8") as f:
        json.dump({"bg": "#%02X%02X%02X" % bg, "art_box": box}, f)


if __name__ == "__main__":
    main()
