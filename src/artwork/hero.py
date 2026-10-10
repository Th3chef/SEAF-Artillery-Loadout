"""SEAF Artillery Loadout release art: the hero scene, a flat illustration. A SEAF artillery gun on its concrete pad at
dusk, the barrel raised and just fired (muzzle flash, smoke, a shell's glowing trail climbing away), on a dark ridge
with distant strikes along the horizon. hero(W, H, gx, gy, s) -> RGB image, the gun's pad centered at (gx, gy) with
size s (the pad is 1.5 s wide). The HUD row and the text are added by the HTML cards (cards.py). Drawn at 2x and
scaled down."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter

STEEL, STEEL_D, STEEL_L = (62, 68, 66), (38, 42, 42), (96, 104, 100)
CONC, CONC_D = (92, 90, 84), (60, 58, 54)
FLASH = (255, 200, 90)


def noise(w, h, sigma, seed):
    rnd = np.random.default_rng(seed)
    a = gaussian_filter(rnd.standard_normal((h, w)), sigma)
    return (a - a.min()) / (a.max() - a.min() + 1e-9)


def screen(base, layer, radius, strength=1.0):
    """Screen-blend a blurred copy of an RGB layer (black = nothing) onto base."""
    g = np.asarray(layer.filter(ImageFilter.GaussianBlur(radius)), float) * strength
    b = np.asarray(base, float)
    out = 255 - (255 - b) * (255 - np.clip(g, 0, 255)) / 255
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def rot(points, ox, oy, a):
    c, s_ = math.cos(a), math.sin(a)
    return [(ox + x * c - y * s_, oy + x * s_ + y * c) for x, y in points]


def hero(W, H, gx, gy, s, seed=7, flip=False):
    k = 2                                       # supersampling
    W2, H2, gx, gy, s = W * k, H * k, gx * k, gy * k, s * k
    rnd = np.random.default_rng(seed)
    horizon = gy - 0.10 * s

    # sky: deep blue-gray overhead to a burnt orange glow at the horizon
    yy = np.arange(H2)[:, None] / max(horizon, 1)
    t = np.clip(yy, 0, 1)[..., None]
    top, mid, hz = np.array([16, 22, 32]), np.array([46, 44, 52]), np.array([196, 104, 52])
    sky = np.where(t < 0.6, top + (mid - top) * (t / 0.6), mid + (hz - mid) * (np.clip(t - 0.6, 0, None) / 0.4) ** 1.6)
    sky = np.broadcast_to(sky, (H2, W2, 3)).copy()
    clouds = noise(W2 // 8, H2 // 8, 5, seed)
    clouds = np.asarray(Image.fromarray((clouds * 255).astype(np.uint8)).resize((W2, H2), Image.BICUBIC), float) / 255
    sky *= (0.82 + 0.3 * clouds[..., None])
    img = Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)

    # distant strikes on the horizon: glowing domes under soft smoke plumes
    glow = Image.new('RGB', (W2, H2), 0)
    gd = ImageDraw.Draw(glow)
    plume = Image.new('L', (W2, H2), 0)
    pd = ImageDraw.Draw(plume)
    for _ in range(int(W2 / s * 1.6) + 2):
        x = rnd.uniform(0, W2)
        if abs(x - gx) < 0.9 * s:
            continue
        r = s * rnd.uniform(0.05, 0.12)
        y = horizon - 0.10 * s
        for j in range(9):                       # puffs rising and widening
            t = j / 8
            px, py, pr = x + r * 0.8 * t * rnd.uniform(-1, 1), y - r * 5.0 * t, r * (0.5 + 1.1 * t)
            pd.ellipse((px - pr, py - pr, px + pr, py + pr), fill=int(150 * (1 - 0.6 * t)))
        gd.ellipse((x - r * 1.6, y - r * 1.0, x + r * 1.6, y + r * 1.0), fill=(255, 150, 60))
    plume = plume.filter(ImageFilter.GaussianBlur(0.03 * s))
    img = Image.composite(Image.new('RGB', (W2, H2), (66, 56, 58)), img, plume)
    img = screen(img, glow, 0.06 * s, 0.9)
    d = ImageDraw.Draw(img)

    # two ridges: a far hazy one and the near dark one the gun stands on
    for col, base, amp, step in [((54, 44, 46), 0.10, 0.10, 0.22), ((22, 22, 26), -0.04, 0.05, 0.16)]:
        pts = [(0, H2)]
        x = -0.1 * s
        while x < W2 + 0.3 * s:
            y = horizon - base * s - rnd.uniform(0, amp) * s
            if col[0] == 22 and abs(x - gx) < 1.2 * s:
                y = gy + 0.02 * s                # flat around the pad
            pts.append((x, y))
            x += step * s * rnd.uniform(0.7, 1.3)
        pts.append((W2, H2))
        d.polygon(pts, fill=col)
    # ground below the near ridge, darker toward the viewer
    arr = np.asarray(img, float)
    gyv = np.clip((np.arange(H2)[:, None] - gy) / max(H2 - gy, 1), 0, 1)[..., None]
    g = noise(W2 // 6, H2 // 6, 3.0, seed + 5)
    g = np.asarray(Image.fromarray((g * 255).astype(np.uint8)).resize((W2, H2), Image.BICUBIC), float)[..., None] / 255
    ground = np.array([40, 36, 34]) * (0.85 + 0.3 * g) * (1 - 0.55 * gyv)
    arr = np.where((np.arange(H2)[:, None] >= gy + 0.02 * s)[..., None], ground, arr)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)

    # the gun: concrete pad, turntable, carriage, a long barrel raised 38 degrees
    sgn = -1 if flip else 1
    pad = [(gx - 0.75 * s, gy + 0.04 * s), (gx + 0.75 * s, gy + 0.04 * s), (gx + 0.66 * s, gy - 0.06 * s), (gx - 0.66 * s, gy - 0.06 * s)]
    d.polygon(pad, fill=CONC)
    d.rectangle((gx - 0.75 * s, gy + 0.04 * s, gx + 0.75 * s, gy + 0.09 * s), fill=CONC_D)
    for i in range(-5, 6):                       # hazard marks along the pad's edge
        x = gx + i * 0.13 * s
        d.polygon([(x, gy + 0.04 * s), (x + 0.05 * s, gy + 0.04 * s), (x + 0.08 * s, gy + 0.09 * s), (x + 0.03 * s, gy + 0.09 * s)],
                  fill=(206, 170, 40))
    d.ellipse((gx - 0.42 * s, gy - 0.12 * s, gx + 0.42 * s, gy + 0.0 * s), fill=STEEL_D)
    d.rectangle((gx - 0.42 * s, gy - 0.10 * s, gx + 0.42 * s, gy - 0.06 * s), fill=STEEL_D)
    body = [(-0.36, -0.08), (0.36, -0.08), (0.30, -0.36), (0.10, -0.46), (-0.22, -0.46), (-0.34, -0.30)]
    d.polygon([(gx + sgn * x * s, gy + y * s) for x, y in body], fill=STEEL)
    d.polygon([(gx + sgn * x * s, gy + y * s) for x, y in [(-0.22, -0.46), (0.10, -0.46), (0.06, -0.42), (-0.19, -0.42)]], fill=STEEL_L)
    for x in (-0.25, -0.05, 0.15):              # rivets / panel lines
        d.line([(gx + sgn * x * s, gy - 0.40 * s), (gx + sgn * x * s, gy - 0.12 * s)], fill=STEEL_D, width=max(2, int(0.01 * s)))
    pivot = (gx + sgn * 0.0 * s, gy - 0.34 * s)
    a = -math.radians(38) if not flip else math.radians(180 + 38)
    barrel = [(-0.20 * s, -0.06 * s), (1.30 * s, -0.035 * s), (1.30 * s, 0.035 * s), (-0.20 * s, 0.06 * s)]
    d.polygon(rot(barrel, pivot[0], pivot[1], a), fill=STEEL_L)
    d.polygon(rot([(-0.20 * s, 0.0), (1.30 * s, 0.0), (1.30 * s, 0.035 * s), (-0.20 * s, 0.06 * s)], pivot[0], pivot[1], a), fill=STEEL)
    brake = [(1.22 * s, -0.06 * s), (1.40 * s, -0.06 * s), (1.40 * s, 0.06 * s), (1.22 * s, 0.06 * s)]
    d.polygon(rot(brake, pivot[0], pivot[1], a), fill=STEEL_D)
    sleeve = [(-0.26 * s, -0.10 * s), (0.36 * s, -0.09 * s), (0.36 * s, 0.09 * s), (-0.26 * s, 0.10 * s)]
    d.polygon(rot(sleeve, pivot[0], pivot[1], a), fill=STEEL)
    d.line(rot([(-0.26 * s, -0.10 * s), (0.36 * s, -0.09 * s)], pivot[0], pivot[1], a), fill=STEEL_L, width=max(2, int(0.012 * s)))
    # a SEAF stripe on the carriage
    d.polygon([(gx + sgn * x * s, gy + y * s) for x, y in [(-0.33, -0.20), (0.33, -0.20), (0.33, -0.16), (-0.33, -0.16)]],
              fill=(206, 170, 40))

    # the shot: muzzle flash, smoke puffs, the shell's trail climbing out of the picture
    tip = rot([(1.42 * s, 0.0)], pivot[0], pivot[1], a)[0]
    ang = a
    vx, vy = math.cos(ang), math.sin(ang)
    smoke = Image.new('L', (W2, H2), 0)
    sd = ImageDraw.Draw(smoke)
    for i in range(14):
        t = rnd.uniform(0.1, 1.0)
        cx = tip[0] - vx * 0.12 * s + rnd.normal(0, 0.18) * s * t
        cy = tip[1] + rnd.uniform(-0.05, 0.25) * s * t
        rr = s * (0.06 + 0.12 * t)
        sd.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=int(190 * (1 - 0.5 * t)))
    smoke = smoke.filter(ImageFilter.GaussianBlur(0.04 * s))
    sm = Image.new('RGB', (W2, H2), (120, 112, 108))
    img = Image.composite(sm, img, smoke)

    d = ImageDraw.Draw(img)
    fl = Image.new('RGB', (W2, H2), 0)
    fd = ImageDraw.Draw(fl)
    r = 0.07 * s
    fd.ellipse((tip[0] - r, tip[1] - r, tip[0] + r, tip[1] + r), fill=FLASH)
    for j in range(12):                          # a star of flame, longest along the barrel
        b = ang + j * math.pi / 6
        L = s * (0.40 if j == 0 else 0.22 if j in (1, 11) else 0.13) * rnd.uniform(0.8, 1.15)
        fd.polygon(rot([(0, -0.025 * s), (L, 0), (0, 0.025 * s)], tip[0], tip[1], b), fill=(255, 210, 110))
    # the trail: a thin glowing curve from the muzzle up and away
    pts = []
    vx, vy = math.cos(ang), math.sin(ang)
    x, y = tip
    for i in range(160):
        pts.append((x, y))
        x += vx * 0.03 * s; y += vy * 0.03 * s
        vy += 0.0016
    fd.line(pts, fill=(255, 190, 110), width=max(2, int(0.012 * s)))
    img = screen(img, fl, 0.08 * s, 0.8)
    img = screen(img, fl, 0.004 * s, 1.0)
    d = ImageDraw.Draw(img)
    # embers and dust in the air
    d = ImageDraw.Draw(img)
    for _ in range(int(W2 * H2 / (s * s) * 6)):
        x, y = rnd.uniform(0, W2), rnd.uniform(0, H2)
        rr = rnd.uniform(0.6, 1.8) * k
        c = (255, int(rnd.uniform(120, 200)), 80) if rnd.uniform() < 0.5 else (150, 140, 130)
        d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=c)

    # vignette
    arr = np.asarray(img, float)
    yv, xv = np.mgrid[0:H2, 0:W2]
    v = ((xv - W2 / 2) / (W2 / 2)) ** 2 + ((yv - H2 / 2) / (H2 / 2)) ** 2
    arr *= np.clip(1.08 - 0.32 * v, 0.45, 1)[..., None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    return img.resize((W2 // k, H2 // k), Image.LANCZOS)


if __name__ == '__main__':
    hero(1920, 1080, 1350, 820, 420).save('hero_preview.png')
