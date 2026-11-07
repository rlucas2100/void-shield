"""Void Shield Lite art: a cartoon void vortex in a rounded frame (calm + supercharged), purple
phoenix wings, purple flame crowns, lightning, sparks, glow, ring. Writes .tga textures for the
addon (media/) and PNG copies (for previews / docs)."""
import math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

MEDIA, PREV = sys.argv[1], sys.argv[2]
os.makedirs(MEDIA, exist_ok=True); os.makedirs(PREV, exist_ok=True)


def C(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = np.asarray(t)[..., None]
    return a * (1 - t) + b * t


class Canvas:
    def __init__(self, w, h, ss=4):
        self.w, self.h, self.ss = w, h, ss
        H, W = h * ss, w * ss
        self.rgb = np.zeros((H, W, 3))
        self.a = np.zeros((H, W))
        ys, xs = np.mgrid[0:H, 0:W]
        self.X = (xs + 0.5) / ss
        self.Y = (ys + 0.5) / ss

    def cov(self, sdf):                      # anti-aliased coverage from a distance field
        return np.clip(0.5 - sdf * self.ss, 0, 1)

    def paint(self, alpha, color):           # normal "over" blend, straight colour
        alpha = np.clip(alpha, 0, 1)[..., None]
        col = np.asarray(color, float)
        if col.ndim == 1:
            col = col[None, None, :]
        self.rgb = col * alpha + self.rgb * (1 - alpha)
        self.a = alpha[..., 0] + self.a * (1 - alpha[..., 0])

    def poly_mask(self, polys):
        ss = self.ss
        im = Image.new('L', (self.w * ss, self.h * ss), 0)
        d = ImageDraw.Draw(im)
        for p in polys:
            d.polygon([(x * ss, y * ss) for x, y in p], fill=255)
        return np.asarray(im, float) / 255

    def image(self):
        ss, h, w = self.ss, self.h, self.w
        rgb = self.rgb.reshape(h, ss, w, ss, 3).mean((1, 3))
        a = self.a.reshape(h, ss, w, ss).mean((1, 3))
        straight = np.where(a[..., None] > 1e-5, rgb / np.maximum(a[..., None], 1e-5), 0)
        arr = np.dstack([np.clip(straight, 0, 1), np.clip(a, 0, 1)])
        return Image.fromarray((arr * 255 + 0.5).astype(np.uint8), 'RGBA')


def sd_rrect(X, Y, cx, cy, hw, hh, r):
    qx = np.abs(X - cx) - (hw - r)
    qy = np.abs(Y - cy) - (hh - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def sd_circle(X, Y, cx, cy, r):
    return np.hypot(X - cx, Y - cy) - r


def inside_dist(mask, ss):
    return ndimage.distance_transform_edt(mask > 0.5) / ss


def outside_dist(mask, ss):
    return ndimage.distance_transform_edt(mask <= 0.5) / ss


def tongue(x0, y0, ang, L, W, curl=0.0, wob=0.0, phase=0.0, n=48, tip=1.0, base=0.18):
    """a tapered flame / feather polygon. ang in degrees (0 right, 90 up), curl bends it."""
    a0, c = math.radians(ang), math.radians(curl)
    x, y, dl = x0, y0, L / n
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        a = a0 + c * t * t + math.radians(wob) * math.sin(2 * math.pi * (t * 1.3) + phase)
        w = W * 0.5 * (1 - t) ** (0.8 * tip) * min(1, (t + base) / (base + 0.3)) ** 0.5
        nx, ny = math.sin(a), math.cos(a)
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
        x += math.cos(a) * dl
        y -= math.sin(a) * dl
    return left + right[::-1]


# purple phoenix fire: ink outline -> deep violet -> violet -> orchid -> lilac -> white-hot
FIRE = [(0.0, '#1a0533'), (2.2, '#5c18c8'), (4.5, '#8c36ff'), (8.0, '#b96bff'), (12.5, '#e2a2ff'), (18.0, '#f9edff')]


def fire_colour(D, heat):
    v = D + heat
    col = np.zeros(D.shape + (3,))
    col[:] = C(FIRE[0][1])
    for lim, c in FIRE[1:]:
        k = smooth(lim - 0.5, lim + 0.5, v)[..., None]
        col = col * (1 - k) + C(c) * k
    return col


def save(img, name):
    img.save(os.path.join(MEDIA, name + '.tga'))
    img.save(os.path.join(PREV, name + '.png'))


# ---------------------------------------------------------------------------------------------
# The box frame: rounded cartoon bevel around a dark cosmic window (the vortex sits on top)
# ---------------------------------------------------------------------------------------------
FRAME = {
    'calm': dict(ink='#14062b', rim_hi='#dcc6ff', rim_mid='#9466ff', rim_lo='#3a1384',
                 bg_in='#2a0d5c', bg_out='#07021a', star='#ffffff'),
    'max': dict(ink='#1a0533', rim_hi='#fff2ff', rim_mid='#d77bff', rim_lo='#6a1cc8',
                bg_in='#43128c', bg_out='#0d0326', star='#f3d6ff'),
}


def make_frame(kind, size=256, ss=4):
    p = FRAME[kind]
    cv = Canvas(size, size, ss)
    X, Y = cv.X, cv.Y
    k, c = size / 256, size / 2
    outer = sd_rrect(X, Y, c, c, c - 2 * k, c - 2 * k, 46 * k)
    cv.paint(cv.cov(outer), C(p['ink']))
    rim = outer + 11 * k
    t = np.clip(((X - c) + (Y - c)) / (2 * c) * 0.5 + 0.5, 0, 1)          # 0 top-left .. 1 bottom-right
    rimcol = np.where((t < 0.5)[..., None], mix(C(p['rim_hi']), C(p['rim_mid']), t * 2),
                      mix(C(p['rim_mid']), C(p['rim_lo']), t * 2 - 1))
    cv.paint(cv.cov(rim), rimcol)
    shine = np.abs(rim + 6 * k) - 1.6 * k                               # cartoon shine stripe
    cv.paint(cv.cov(shine) * smooth(0.55, 0.25, t) * 0.8, C('#ffffff'))
    cv.paint(cv.cov(outer + 24 * k), C(p['ink']))
    inner = outer + 28 * k
    d = np.clip(np.hypot(X - c, Y - c) / (c * 1.05), 0, 1)
    cv.paint(cv.cov(inner), mix(C(p['bg_in']), C(p['bg_out']), d))
    rnd = random.Random(7)
    for _ in range(40):                                                 # stars in the corners
        sx, sy = rnd.uniform(34, 222) * k, rnd.uniform(34, 222) * k
        r = rnd.uniform(0.7, 1.7) * k
        cv.paint(cv.cov(sd_circle(X, Y, sx, sy, r)) * cv.cov(inner) * rnd.uniform(0.5, 0.95), C(p['star']))
    return cv.image()


def make_gloss(size=256, ss=4):
    """static cartoon glass shine laid over the spinning vortex"""
    cv = Canvas(size, size, ss)
    X, Y = cv.X, cv.Y
    k, c = size / 256, size / 2
    dist = np.hypot(X - c, Y - c)
    ang = np.arctan2(Y - c, X - c)
    da = np.angle(np.exp(1j * (ang - math.radians(-135))))
    wg = np.clip(1 - (da / 0.8) ** 2, 0, 1)
    arc = np.abs(dist - 84 * k) - 5.5 * k * np.sqrt(wg)
    cv.paint(cv.cov(arc) * (wg > 0) * 0.75, C('#ffffff'))
    cv.paint(cv.cov(sd_circle(X, Y, c - 34 * k, c - 66 * k, 5 * k)) * 0.85, C('#ffffff'))
    cv.paint(cv.cov(sd_circle(X, Y, c - 58 * k, c - 46 * k, 3 * k)) * 0.75, C('#ffffff'))
    return cv.image()


# ---------------------------------------------------------------------------------------------
# The vortex: five cel-shaded energy swirls winding into a dark eye (5-fold symmetric, so a
# 72 degree turn looks identical: the game can hand one spin over to another without a jump)
# ---------------------------------------------------------------------------------------------
ARMS = 5


def arm_polys(c, R, n=90, twist=2.5):
    polys = []
    for i in range(ARMS):
        phi = 2 * math.pi * i / ARMS
        L, Rr = [], []
        for j in range(n + 1):
            s = j / n                                   # 0 = head at the eye, 1 = tail at the rim
            rr = R * (0.26 + 0.70 * s)
            th = phi + twist * s
            w = R * 0.19 * math.sin(math.pi * min(1.0, (s + 0.06) / 1.06)) ** 0.55 * (1 - s) ** 0.35
            x, y = c + rr * math.cos(th), c + rr * math.sin(th)
            tx = 0.70 * R * math.cos(th) - rr * math.sin(th) * twist
            ty = 0.70 * R * math.sin(th) + rr * math.cos(th) * twist
            ln = math.hypot(tx, ty)
            nx, ny = -ty / ln, tx / ln
            L.append((x + nx * w, y + ny * w))
            Rr.append((x - nx * w, y - ny * w))
        polys.append(L + Rr[::-1])
    return polys


def make_vortex(kind, size=256, ss=4):
    hot = kind == 'max'
    cv = Canvas(size, size, ss)
    X, Y = cv.X, cv.Y
    c, R = size / 2, size * 0.48
    r = np.hypot(X - c, Y - c)
    ang = np.arctan2(Y - c, X - c)
    # backdrop: a deep violet disk with faint spiral streaks, fading into the frame's window
    disk = smooth(R, R * 0.72, r)
    cv.paint(disk * 0.92, mix(C('#3b0f88' if not hot else '#5a17b8'), C('#12042e'), np.clip((r / R - 0.35) / 0.65, 0, 1)))
    u = (ang - 2.4 * np.log(np.maximum(r, 1) / R)) * 7
    streak = (0.5 + 0.5 * np.cos(u)) ** 8 * smooth(0.25 * R, 0.5 * R, r) * smooth(R, 0.7 * R, r)
    cv.paint(streak * (0.35 if not hot else 0.5), C('#9a5cff' if not hot else '#c98bff'))
    # the five swirl arms, each with a cartoon ink outline, banded like a glowing tube
    ink = C('#12042a')
    bands = ([(0, '#4a17b0'), (4.5, '#7a3cf0'), (8.5, '#a878ff'), (12.5, '#e3d2ff')] if not hot else
             [(0, '#6a1ad6'), (3.5, '#a046ff'), (7.0, '#d27cff'), (10.5, '#ffeaff')])
    for poly in arm_polys(c, R):
        m = cv.poly_mask([poly])
        sd = outside_dist(m, ss) - inside_dist(m, ss)
        cv.paint(cv.cov(sd - 3.2), ink)
        D = inside_dist(m, ss) + 4 * smooth(0.75 * R, 0.3 * R, r)        # brighter near the eye
        col = np.zeros(D.shape + (3,))
        col[:] = C(bands[0][1])
        for lim, h in bands[1:]:
            col = mix(col, C(h), smooth(lim - 0.5, lim + 0.5, D))
        cv.paint(m, col)
    # the eye: ink ring, glowing rim, dark centre, tiny glint
    er = R * 0.27
    cv.paint(cv.cov(sd_circle(X, Y, c, c, er + 5)), ink)
    rim = np.abs(r - (er + 1)) - 2.6
    cv.paint(cv.cov(rim), C('#f4e4ff' if not hot else '#ffffff'))
    cv.paint(cv.cov(sd_circle(X, Y, c, c, er - 2)), mix(C('#2a0a5e' if not hot else '#4a1290'), C('#030008'),
                                                       np.clip(1 - r / er, 0, 1) ** 0.6))
    cv.paint(cv.cov(sd_circle(X, Y, c - er * 0.35, c - er * 0.4, er * 0.16)) * 0.9, C('#ffffff'))
    # sparkles caught in the swirl
    rnd = random.Random(31)
    for i in range(ARMS * 2):
        a = 2 * math.pi * i / (ARMS * 2) + 0.5
        rr = R * (0.55 + 0.25 * (i % 2))
        sx, sy = c + rr * math.cos(a), c + rr * math.sin(a)
        dx, dy = np.abs(X - sx), np.abs(Y - sy)
        s = 7 if i % 2 else 5
        star = (np.sqrt(dx / s + 1e-9) + np.sqrt(dy / s + 1e-9)) < 1.0
        cv.paint(star * 0.9, C('#ffffff'))
    return cv.image()


def make_vortex_glow(size=256, ss=2):
    """a soft light version of the swirl, laid on top with additive blending (stronger at 10)"""
    cv = Canvas(size, size, ss)
    c, R = size / 2, size * 0.48
    m = cv.poly_mask(arm_polys(c, R))
    blur = ndimage.gaussian_filter(m, 5 * ss)
    r = np.hypot(cv.X - c, cv.Y - c)
    ring = np.exp(-((r - R * 0.28) / 5) ** 2)
    a = np.clip(blur * 0.9 + m * 0.25 + ring * 0.8, 0, 1) * smooth(R, R * 0.8, r)
    cv.paint(a, C('#ffffff'))
    return cv.image()


# ---------------------------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------------------------
def make_mask(size=128):
    cv = Canvas(size, size)
    c = size / 2
    cv.paint(cv.cov(sd_rrect(cv.X, cv.Y, c, c, c - 1, c - 1, 46 * size / 256)), C('#ffffff'))
    return cv.image()


def make_glow(size=128, box_frac=0.5):
    cv = Canvas(size, size, 2)
    c = size / 2
    hb = c * box_frac
    sd = sd_rrect(cv.X, cv.Y, c, c, hb, hb, hb * 0.36)
    fall = np.exp(-np.maximum(sd, 0) / (size * 0.075)) * smooth(c, c * 0.82, np.maximum(np.abs(cv.X - c), np.abs(cv.Y - c)))
    cv.paint(np.clip(fall, 0, 1), C('#ffffff'))
    return cv.image()


def make_ring(size=128):
    cv = Canvas(size, size, 2)
    c = size / 2
    d = np.hypot(cv.X - c, cv.Y - c)
    a = np.exp(-((d - c * 0.8) / (size * 0.035)) ** 2) + 0.45 * np.exp(-((d - c * 0.74) / (size * 0.09)) ** 2)
    cv.paint(np.clip(a, 0, 1) * smooth(c, c * 0.92, d), C('#ffffff'))
    return cv.image()


def make_spark(size=64):
    cv = Canvas(size, size, 4)
    c = size / 2
    dx, dy = np.abs(cv.X - c) / c, np.abs(cv.Y - c) / c
    star = (np.sqrt(dx + 1e-9) + np.sqrt(dy + 1e-9)) < 0.92
    d = np.hypot(cv.X - c, cv.Y - c) / c
    cv.paint(np.exp(-d / 0.22) * 0.8, C('#ffffff'))
    cv.paint(star.astype(float) * smooth(1, 0.2, d * 1.3), C('#ffffff'))
    return cv.image()


def make_bolt(seed, w=256, h=64):
    """a jagged lightning arc across the middle of a square texture (so it can be rotated)"""
    rnd = random.Random(seed)
    pts = [(6, h / 2), (w - 6, h / 2 + rnd.uniform(-6, 6))]
    disp = h * 0.42
    for _ in range(6):                                     # midpoint displacement
        new = [pts[0]]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            mx, my = (x0 + x1) / 2, (y0 + y1) / 2 + rnd.uniform(-disp, disp)
            new += [(mx, max(8, min(h - 8, my))), (x1, y1)]
        pts = new
        disp *= 0.55
    bi = len(pts) // 3
    bx, by = pts[bi]
    branch = [(bx, by)]
    sgn = -1 if by > h / 2 else 1
    for i in range(1, 6):
        branch.append((bx + i * 11 + rnd.uniform(-3, 3), max(4, min(h - 4, by + sgn * i * 4.2 + rnd.uniform(-2.5, 2.5)))))
    cv = Canvas(w, h, 4)
    ss = cv.ss
    im = Image.new('L', (w * ss, h * ss), 0)
    dr = ImageDraw.Draw(im)
    dr.line([(x * ss, y * ss) for x, y in pts], fill=255, width=int(4 * ss), joint='curve')
    dr.line([(x * ss, y * ss) for x, y in branch], fill=255, width=int(2 * ss), joint='curve')
    m = np.asarray(im, float) / 255
    od = outside_dist(m, ss)
    taper = smooth(0, 30, cv.X) * smooth(w, w - 40, cv.X)
    cv.paint(np.exp(-od / 4.5) * 0.75 * taper, C('#ffffff'))
    cv.paint(m * taper, C('#ffffff'))
    sq = Image.new('RGBA', (w, w), (0, 0, 0, 0))
    sq.paste(cv.image(), (0, (w - h) // 2))
    return sq


def make_flame(w=64, h=128):
    cv = Canvas(w, h, 4)
    P = [tongue(w / 2, h - 30, 90, h - 36, 40, curl=0, wob=7, phase=0.4, tip=1.3, base=0.45)]
    m = cv.poly_mask(P)
    m = np.maximum(m, cv.cov(sd_circle(cv.X, cv.Y, w / 2, h - 30, 17)))
    D = inside_dist(m, cv.ss)
    cv.paint(m, fire_colour(D * 1.1, 0))
    return cv.image()


def make_crown(seed, size=256, box_frac=135 / 256):
    """flames licking up around the box (the box covers their roots)"""
    rnd = random.Random(seed)
    cv = Canvas(size, size, 4)
    c = size / 2
    hb = c * box_frac
    P = []
    n_side, n_top = 7, 9
    for i in range(n_top):
        x = c - hb + 8 + (2 * hb - 16) * i / (n_top - 1)
        L = rnd.uniform(34, 48) * (0.82 + 0.18 * math.sin(math.pi * i / (n_top - 1)))
        P.append(tongue(x, c - hb + 14, 90 + rnd.uniform(-10, 10) + (x - c) * -0.08, L + 14, rnd.uniform(20, 28),
                        curl=rnd.uniform(-25, 25), wob=rnd.uniform(6, 12), phase=rnd.uniform(0, 6)))
    for side in (-1, 1):
        for i in range(n_side):
            y = c + hb - 12 - (2 * hb - 30) * i / (n_side - 1)
            frac = i / (n_side - 1)
            ang = 90 + side * -(60 - 40 * frac)
            L = rnd.uniform(22, 32) + 14 * frac
            P.append(tongue(c + side * (hb - 12), y, ang, L + 12, rnd.uniform(18, 24),
                            curl=side * rnd.uniform(15, 35), wob=rnd.uniform(5, 10), phase=rnd.uniform(0, 6)))
    for i in range(5):
        x = c - hb + 20 + (2 * hb - 40) * i / 4
        P.append(tongue(x, c + hb - 10, -90 + rnd.uniform(-20, 20), rnd.uniform(14, 20), 16,
                        curl=rnd.uniform(-40, 40), wob=5, phase=rnd.uniform(0, 6)))
    m = cv.poly_mask(P)
    m = np.maximum(m, cv.cov(sd_rrect(cv.X, cv.Y, c, c, hb - 4, hb - 4, hb * 0.36)))
    D = inside_dist(m, cv.ss)
    boxd = sd_rrect(cv.X, cv.Y, c, c, hb, hb, hb * 0.36)
    heat = 6 * smooth(26, 0, boxd)
    cv.paint(np.exp(-outside_dist(m, cv.ss) / 5) * 0.55, C('#8a2bff'))
    cv.paint(m, fire_colour(D, heat))
    return cv.image()


def fit_polys(build, w, h, margin):
    k = 1.0
    for _ in range(40):
        P = build(k)
        xs = [x for p in P for x, _ in p]
        ys = [y for p in P for _, y in p]
        if min(xs) >= margin and max(xs) <= w - margin and min(ys) >= margin and max(ys) <= h - margin:
            return P, k
        k *= 0.97
    return P, k


def make_wings(w=512, h=256):
    cv = Canvas(w, h, 4)
    c = w / 2
    rootY = h * 0.66
    feathers = [(-6, 168, 34, 30), (12, 200, 38, 32), (28, 212, 40, 32), (44, 204, 40, 28),
                (59, 186, 36, 22), (72, 160, 32, 14), (84, 128, 28, 6)]
    def build(k):
        P = []
        for side in (1, -1):
            for ang, L, W, curl in feathers:
                a = ang if side == 1 else 180 - ang
                P.append(tongue(c + side * 32, rootY, a, L * k, W, curl * side, wob=5, phase=ang * 0.1, tip=1.15))
            a = -30 if side == 1 else 210
            P.append(tongue(c + side * 30, rootY + 6, a, 104 * k, 26, 24 * side, wob=4, tip=1.1))
        return P
    P, k = fit_polys(build, w, h, 16)
    m = cv.poly_mask(P)
    D = inside_dist(m, cv.ss)
    root = np.hypot((cv.X - c) / 1.4, cv.Y - rootY)
    heat = 8 * smooth(150, 30, root)
    cv.paint(np.exp(-outside_dist(m, cv.ss) / 6) * 0.5, C('#7a22ff'))
    cv.paint(m, fire_colour(D * 0.9, heat))
    return cv.image()


# ---------------------------------------------------------------------------------------------
images = {
    'frame': make_frame('calm'), 'frame_max': make_frame('max'), 'gloss': make_gloss(),
    'vortex': make_vortex('calm'), 'vortex_max': make_vortex('max'), 'vortex_glow': make_vortex_glow(),
    'boxmask': make_mask(), 'glow': make_glow(), 'ring': make_ring(), 'spark': make_spark(),
    'bolt1': make_bolt(3), 'bolt2': make_bolt(19), 'flame': make_flame(),
    'flames1': make_crown(5), 'flames2': make_crown(23), 'wings': make_wings(),
}
# the addon-list icon: the supercharged box, flattened to one small picture
icon = images['frame_max'].copy()
v = images['vortex_max'].resize((int(256 * 0.82), int(256 * 0.82)), Image.LANCZOS)
icon.alpha_composite(v, ((256 - v.width) // 2, (256 - v.height) // 2))
icon.alpha_composite(images['gloss'])
images['icon'] = icon.resize((64, 64), Image.LANCZOS)
for k, im in images.items():
    save(im, k)
    print(k, im.size)
