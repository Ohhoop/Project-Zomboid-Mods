import os
import random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

random.seed(11)
W = H = 512
S = 2
w, h = W * S, H * S

cx, cy = w // 2, int(h * 0.60)
tw, th, depth = int(w * 0.78), int(w * 0.39), int(h * 0.075)
top = [(cx, cy - th // 2), (cx + tw // 2, cy), (cx, cy + th // 2), (cx - tw // 2, cy)]
left_side = [top[3], top[2], (top[2][0], top[2][1] + depth), (top[3][0], top[3][1] + depth)]
right_side = [top[2], top[1], (top[1][0], top[1][1] + depth), (top[2][0], top[2][1] + depth)]


def background():
    bg = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(14 + 10 * t), int(18 + 12 * t), int(16 + 8 * t)))
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse([cx - 520, cy - 330, cx + 520, cy + 330], fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    bg = Image.composite(Image.new("RGB", (w, h), (60, 120, 70)), bg, glow)
    return bg


def grass_texture():
    tex = Image.new("RGB", (w, h), (72, 118, 52))
    d = ImageDraw.Draw(tex)
    for _ in range(26000):
        x, y = random.randrange(w), random.randrange(h)
        g = random.randint(95, 165)
        c = (random.randint(40, 85), g, random.randint(30, 60))
        ln = random.randint(6, 18)
        d.line([(x, y), (x + random.randint(-4, 4), y - ln)], fill=c, width=2)
    for _ in range(90):
        x, y = random.randrange(w), random.randrange(h)
        r = random.randint(3, 6)
        d.ellipse([x - r, y - r, x + r, y + r], fill=random.choice([(235, 225, 120), (240, 240, 240), (210, 150, 200)]))
    return tex


def dirt_texture(base):
    tex = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(tex)
    for _ in range(9000):
        x, y = random.randrange(w), random.randrange(h)
        k = random.randint(-22, 22)
        d.point((x, y), fill=tuple(max(0, min(255, v + k)) for v in base))
    return tex


def glitch(img):
    small = img.resize((w // 28, h // 28), Image.NEAREST).resize((w, h), Image.NEAREST)
    r, g, b = small.split()
    r = ImageChops.offset(r, 14, 0)
    b = ImageChops.offset(b, -14, 6)
    out = Image.merge("RGB", (r, g, b))
    d = ImageDraw.Draw(out)
    for _ in range(40):
        y = random.randrange(h)
        bh = random.randint(6, 30)
        band = out.crop((0, y, w, y + bh))
        out.paste(band, (random.randint(-80, 80), y))
    cell = 28
    for _ in range(55):
        x = random.randrange(0, w, cell)
        y = random.randrange(0, h, cell)
        for i in range(2):
            for j in range(2):
                col = (255, 0, 220) if (i + j) % 2 == 0 else (10, 10, 10)
                d.rectangle([x + i * cell // 2, y + j * cell // 2, x + (i + 1) * cell // 2, y + (j + 1) * cell // 2], fill=col)
    for _ in range(25):
        x, y = random.randrange(w), random.randrange(h)
        d.rectangle([x, y, x + random.randint(20, 120), y + random.randint(3, 8)], fill=random.choice([(0, 255, 255), (255, 0, 200), (255, 255, 255)]))
    return out


def poly_mask(points):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    return m


def crack_line():
    pts = []
    y = top[0][1] - 40
    end = top[2][1] + depth + 40
    while y < end:
        pts.append((cx + random.randint(-26, 26), y))
        y += random.randint(22, 40)
    pts.append((cx, end))
    return pts


img = background()
crack = crack_line()
left_region = [(0, 0)] + [(x, y) for x, y in [(crack[0][0], 0)] + crack + [(crack[-1][0], h)]] + [(0, h)]
left_mask = poly_mask(left_region)

grass = grass_texture()
dirt_l = dirt_texture((96, 70, 46))
dirt_r = dirt_texture((74, 54, 36))

clean = Image.new("RGB", (w, h))
clean.paste(grass, mask=poly_mask(top))
clean.paste(dirt_l, mask=poly_mask(left_side))
clean.paste(dirt_r, mask=poly_mask(right_side))
tile_mask = ImageChops.lighter(ImageChops.lighter(poly_mask(top), poly_mask(left_side)), poly_mask(right_side))

corrupted = glitch(clean)
tile = Image.composite(corrupted, clean, left_mask)

shadow = Image.new("L", (w, h), 0)
ImageDraw.Draw(shadow).ellipse([cx - tw // 2, cy + th // 2 - 10, cx + tw // 2, cy + th // 2 + depth + 90], fill=150)
shadow = shadow.filter(ImageFilter.GaussianBlur(40))
img = Image.composite(Image.new("RGB", (w, h), (0, 0, 0)), img, shadow)

halo = Image.new("L", (w, h), 0)
ImageDraw.Draw(halo).polygon(top, fill=255)
halo = ImageChops.subtract(halo, left_mask).filter(ImageFilter.GaussianBlur(45))
img = Image.composite(Image.new("RGB", (w, h), (140, 255, 150)), img, halo.point(lambda v: v * 0.55))

img.paste(tile, mask=tile_mask)

d = ImageDraw.Draw(img)
d.line(top + [top[0]], fill=(20, 30, 20), width=4)
d.line([top[3], left_side[3], left_side[2], right_side[2], top[1]], fill=(20, 18, 14), width=4)
d.line([top[2], left_side[2]], fill=(20, 18, 14), width=4)

crack_glow = Image.new("L", (w, h), 0)
ImageDraw.Draw(crack_glow).line(crack, fill=255, width=26)
crack_glow = crack_glow.filter(ImageFilter.GaussianBlur(14))
img = Image.composite(Image.new("RGB", (w, h), (170, 255, 190)), img, crack_glow)
ImageDraw.Draw(img).line(crack, fill=(240, 255, 240), width=6)

for _ in range(30):
    x = cx + random.randint(20, tw // 2 - 40)
    y = cy + random.randint(-th // 2, th // 2) - random.randint(40, 200)
    r = random.randint(4, 9)
    sp = Image.new("L", (w, h), 0)
    ImageDraw.Draw(sp).ellipse([x - r * 3, y - r * 3, x + r * 3, y + r * 3], fill=180)
    sp = sp.filter(ImageFilter.GaussianBlur(r * 1.5))
    img = Image.composite(Image.new("RGB", (w, h), (200, 255, 200)), img, sp)
    ImageDraw.Draw(img).ellipse([x - r // 2, y - r // 2, x + r // 2, y + r // 2], fill=(255, 255, 255))

d = ImageDraw.Draw(img)
font = ImageFont.truetype("C:/Windows/Fonts/impact.ttf", 150)
title = "TILE DOCTOR"
bbox = d.textbbox((0, 0), title, font=font)
tx = (w - (bbox[2] - bbox[0])) // 2
ty = 70
d.text((tx + 6, ty + 8), title, font=font, fill=(0, 0, 0))
d.text((tx, ty), title, font=font, fill=(235, 245, 235))

cs, ct = 64, 22
ccx, ccy = w // 2, ty + 240
d.rectangle([ccx - ct, ccy - cs // 2 - 10, ccx + ct, ccy + cs // 2 + 10], fill=(200, 40, 40))
d.rectangle([ccx - cs // 2 - 10, ccy - ct, ccx + cs // 2 + 10, ccy + ct], fill=(200, 40, 40))

img = img.resize((W, H), Image.LANCZOS)
img.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), "concept11.png"))
