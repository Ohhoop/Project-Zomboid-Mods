import os
from PIL import Image, ImageDraw

OUT = r"D:\2 - Projet Perso\Mods PZ\Tile Doctor\Tile Doctor-Dev\Contents\mods\Tile Doctor-Dev\42\media\ui\TileDoctor"
SIZE = 32
S = 8
W = SIZE * S

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
margin = 1 * S
d.ellipse([margin, margin, W - margin, W - margin], fill=(60, 0, 0, 255))
inner = 3 * S
d.ellipse([inner, inner, W - inner, W - inner], fill=(220, 35, 35, 255))
bar_w = int(W * 0.13)
cx = W // 2
d.rounded_rectangle([cx - bar_w // 2, int(W * 0.22), cx + bar_w // 2, int(W * 0.62)], radius=bar_w // 2, fill=(255, 255, 255, 255))
dot = int(W * 0.08)
dy = int(W * 0.74)
d.ellipse([cx - dot, dy - dot, cx + dot, dy + dot], fill=(255, 255, 255, 255))
img.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, "Alert.png"))

preview = Image.new("RGBA", (48, 48), (45, 45, 45, 255))
preview.alpha_composite(Image.open(os.path.join(OUT, "Alert.png")), (8, 8))
preview.resize((192, 192), Image.NEAREST).save(os.path.join(os.path.dirname(__file__), "alert_preview.png"))
