"""Mock-ups of the square as the game layers it (docs/preview.png) plus the CurseForge logo
(docs/logo.png), built from the PNG copies that art.py writes."""
import math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

PREV, DOCS = sys.argv[1], sys.argv[2]
os.makedirs(DOCS, exist_ok=True)
T = {n[:-4]: Image.open(os.path.join(PREV, n)).convert('RGBA') for n in os.listdir(PREV)
     if n.endswith('.png') and not n.startswith(('sheet', 'scene', 'logo', 'preview'))}
FONT = 'C:/Windows/Fonts/arialbd.ttf'


class Scene:
    def __init__(self, w, h, bg):
        self.w, self.h = w, h
        self.px = np.array(bg, float)

    def put(self, name, cx, cy, w, h, blend='BLEND', tint=(1, 1, 1), alpha=1.0, rot=0.0):
        im = T[name].resize((max(1, int(w)), max(1, int(h))), Image.LANCZOS)
        if rot:
            im = im.rotate(math.degrees(rot), resample=Image.BICUBIC, expand=True)
        a = np.asarray(im, float) / 255
        rgb, al = a[..., :3] * np.array(tint), a[..., 3] * alpha
        x0, y0 = int(round(cx - im.width / 2)), int(round(cy - im.height / 2))
        sx0, sy0 = max(0, -x0), max(0, -y0)
        dx0, dy0 = max(0, x0), max(0, y0)
        dx1, dy1 = min(self.w, x0 + im.width), min(self.h, y0 + im.height)
        if dx1 <= dx0 or dy1 <= dy0:
            return
        r = rgb[sy0:sy0 + dy1 - dy0, sx0:sx0 + dx1 - dx0]
        k = al[sy0:sy0 + dy1 - dy0, sx0:sx0 + dx1 - dx0][..., None]
        dst = self.px[dy0:dy1, dx0:dx1]
        self.px[dy0:dy1, dx0:dx1] = np.clip(dst + r * k, 0, 1) if blend == 'ADD' else r * k + dst * (1 - k)

    def text(self, s, x, y, size, color=(255, 230, 102)):
        im = Image.fromarray((np.clip(self.px, 0, 1) * 255).astype(np.uint8))
        d = ImageDraw.Draw(im)
        d.text((x, y), s, font=ImageFont.truetype(FONT, int(size)), fill=color, anchor='rm',
               stroke_width=max(2, int(size * 0.11)), stroke_fill=(0, 0, 0))
        self.px = np.asarray(im, float) / 255

    def image(self):
        return Image.fromarray((np.clip(self.px, 0, 1) * 255).astype(np.uint8))


def game_bg(w, h, seed=1):
    rnd = np.random.default_rng(seed)
    y, x = np.mgrid[0:h, 0:w] / max(w, h)
    base = np.dstack([0.16 + 0.10 * y, 0.20 + 0.08 * y, 0.17 + 0.03 * x])
    n = rnd.random((h // 16 + 2, w // 16 + 2))
    n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), float) / 255
    return np.clip(base + (n[..., None] - 0.5) * 0.08, 0, 1)


# in-game layout (sizes relative to the box B), mirrored by the Lua
VORTEX = 0.82
BOLTS = [(28, 1.05, 'bolt1'), (152, 0.95, 'bolt2'), (208, 1.0, 'bolt1'), (334, 0.9, 'bolt2')]
SPARKS = [(15, 0.95), (62, 0.82), (118, 1.0), (170, 0.78), (238, 0.9), (292, 0.8), (322, 0.98)]
NUM_SIZE, NUM_X = 30 / 56, 3 / 56          # stack number: font size and how far it tucks into the box


def number(sc, cx, cy, B, num, hot):
    sc.put('glow', cx - B / 2 - 0.2 * B, cy, 0.95 * B, 0.78 * B, 'BLEND', (0, 0, 0), 0.65 if hot else 0.45)
    sc.text(num, cx - B / 2 + NUM_X * B, cy + 0.02 * B, NUM_SIZE * B * 1.05)


def box(sc, cx, cy, B, hot, spin=0.0):
    sc.put('frame_max' if hot else 'frame', cx, cy, B, B)
    sc.put('vortex_max' if hot else 'vortex', cx, cy, VORTEX * B, VORTEX * B, rot=spin)
    sc.put('vortex_glow', cx, cy, VORTEX * B, VORTEX * B, 'ADD', (0.7, 0.45, 1.0), 0.55 if hot else 0.25, rot=spin)
    sc.put('gloss', cx, cy, B, B)


def calm_scene(sc, cx, cy, B, num='7'):
    sc.put('glow', cx, cy, 1.9 * B, 1.9 * B, 'ADD', (0.55, 0.3, 1.0), 0.45)
    box(sc, cx, cy, B, False)
    sc.put('spark', cx - 0.30 * B, cy - 0.32 * B, 0.24 * B, 0.24 * B, 'ADD', (1, 1, 1), 0.9)
    if num:
        number(sc, cx, cy, B, num, False)


def max_scene(sc, cx, cy, B, num='10', t=0.6):
    sc.put('glow', cx, cy, 2.1 * B, 2.1 * B, 'ADD', (0.62, 0.3, 1.0), 1.0)
    sc.put('wings', cx, cy - 0.04 * B, 3.3 * B, 1.65 * B)
    sc.put('flames1', cx, cy - 0.02 * B, 1.9 * B, 1.9 * B)
    box(sc, cx, cy, B, True, spin=0.4)
    for ang, d, name in BOLTS:
        a = math.radians(ang)
        r = B * (0.5 + 0.42 * d)
        sc.put(name, cx + math.cos(a) * r, cy - math.sin(a) * r, 0.95 * B * d, 0.95 * B * d, 'ADD', (0.82, 0.72, 1.0), 0.95, rot=a)
    for i, (ang, d) in enumerate(SPARKS):
        a = math.radians(ang)
        ph = (t + i * 0.37) % 1
        r, s = B * (0.55 + 0.55 * ph), B * 0.30 * (1.1 - ph * 0.6)
        sc.put('spark', cx + math.cos(a) * r, cy - math.sin(a) * r, s, s, 'ADD', (0.92, 0.82, 1) if i % 3 else (1, 0.75, 1), 1.0)
    for ex, ey, s in ((-0.30, -0.78, 0.9), (0.08, -0.95, 1.1), (0.36, -0.72, 0.8)):
        sc.put('flame', cx + ex * B, cy + ey * B, 0.18 * B * s, 0.36 * B * s, 'BLEND', (1, 1, 1), 0.9)
    sc.put('spark', cx - 0.30 * B, cy - 0.32 * B, 0.28 * B, 0.28 * B, 'ADD', (1, 1, 1), 1.0)
    if num:
        number(sc, cx, cy, B, num, True)


if __name__ == '__main__':
    # 1. README preview: 7 stacks next to 10 stacks, at 3x in-game size
    B = 168
    W, H = 1180, 520
    sc = Scene(W, H, game_bg(W, H))
    calm_scene(sc, 300, 270, B)
    max_scene(sc, 820, 280, B)
    img = sc.image()
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, 26)
    d.text((270, 470), 'proc + 7 stacks', font=f, fill=(225, 210, 255), anchor='mm', stroke_width=3, stroke_fill=(0, 0, 0))
    d.text((800, 470), 'proc + 10 stacks', font=f, fill=(240, 200, 255), anchor='mm', stroke_width=3, stroke_fill=(0, 0, 0))
    img.save(os.path.join(DOCS, 'preview.png'))

    # 2. actual size (scale 1 = 56 px) to check it still reads
    sc = Scene(460, 200, game_bg(460, 200, 3))
    calm_scene(sc, 110, 105, 56)
    max_scene(sc, 320, 105, 56)
    sc.image().save(os.path.join(PREV, 'scene_actual.png'))

    # 3. CurseForge logo 512x512: cosmic backdrop, the supercharged vortex with purple phoenix wings
    S = 512
    y, x = np.mgrid[0:S, 0:S]
    r = np.hypot(x - S / 2, y - S * 0.5) / (S * 0.72)
    bg = np.clip(np.dstack([0.16 - 0.14 * r, 0.04 - 0.035 * r, 0.30 - 0.25 * r]), 0, 1)
    rnd = random.Random(4)
    sc = Scene(S, S, bg)
    for _ in range(120):
        s = rnd.uniform(4, 14)
        sc.put('spark', rnd.uniform(0, S), rnd.uniform(0, S), s, s, 'ADD', (0.85, 0.75, 1.0), rnd.uniform(0.25, 0.8))
    sc.put('glow', S / 2, S / 2, 520, 520, 'ADD', (0.45, 0.2, 1.0), 0.5)
    max_scene(sc, S / 2, S / 2 + 18, 196, num=None, t=0.15)
    logo = sc.image()
    logo.save(os.path.join(DOCS, 'logo.png'))
    logo.save(os.path.join(PREV, 'scene_logo.png'))
    print('ok')
