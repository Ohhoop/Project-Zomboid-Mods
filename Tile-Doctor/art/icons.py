import math
import os
from PIL import Image, ImageDraw

OUT = r"D:\2 - Projet Perso\Mods PZ\Tile Doctor\Tile Doctor-Dev\Contents\mods\Tile Doctor-Dev\42\media\ui\TileDoctor"
SIZE = 32
S = 8
W = SIZE * S

os.makedirs(OUT, exist_ok=True)


def save(img, name):
    img.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, name))


def delete_icon():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m, t = int(W * 0.2), int(W * 0.16)
    for width, color in ((t + 5 * S, (40, 0, 0, 255)), (t, (225, 40, 40, 255))):
        d.line([(m, m), (W - m, W - m)], fill=color, width=width)
        d.line([(W - m, m), (m, W - m)], fill=color, width=width)
    save(img, "Delete.png")


def point(cx, cy, r, deg):
    a = math.radians(deg)
    return (cx + r * math.cos(a), cy + r * math.sin(a))


def arc_arrow(d, cx, cy, r, half, start, end, head_deg, head_half, color):
    outer = [point(cx, cy, r + half, t) for t in range(start, end + 1)]
    inner = [point(cx, cy, r - half, t) for t in range(end, start - 1, -1)]
    d.polygon(outer + inner, fill=color)
    tip = point(cx, cy, r, end + head_deg)
    d.polygon([point(cx, cy, r + head_half, end), tip, point(cx, cy, r - head_half, end)], fill=color)


def reset_icon():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = W / 2
    r = W * 0.30
    for grow, color in ((3 * S, (0, 35, 12, 255)), (0, (80, 215, 110, 255))):
        half = W * 0.055 + grow
        head_half = W * 0.13 + grow
        arc_arrow(d, cx, cy, r, half, 195 - grow // S, 300, 38 + grow // S, head_half, color)
        arc_arrow(d, cx, cy, r, half, 15 - grow // S, 120, 38 + grow // S, head_half, color)
    save(img, "Reset.png")


delete_icon()
reset_icon()

preview = Image.new("RGBA", (96, 48), (45, 45, 45, 255))
preview.alpha_composite(Image.open(os.path.join(OUT, "Delete.png")), (8, 8))
preview.alpha_composite(Image.open(os.path.join(OUT, "Reset.png")), (56, 8))
preview.resize((384, 192), Image.NEAREST).save(os.path.join(os.path.dirname(__file__), "icons_preview.png"))
