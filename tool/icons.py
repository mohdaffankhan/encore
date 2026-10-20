# Draws the Encore icon for every platform. The mark matches
# lib/ui/widgets/logo.dart, which uses the same numbers.
import math
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 4  # supersampling
# "Echo play": a play button with two fading echoes behind it ("again").
# (centre x, circumradius, opacity) from back to front, in a unit square;
# all triangles point right and are centred vertically.
LAYERS = [(0.32, 0.15, 0.28), (0.43, 0.195, 0.55), (0.56, 0.24, 1.0)]
CORNER = 0.2  # corner radius, as a fraction of each triangle's circumradius
GAP = 0.03  # transparent gap cut around each nearer triangle
GOLD, CORAL = (255, 196, 102), (255, 84, 72)
TILE_TOP, TILE_BOTTOM = (30, 28, 34), (12, 11, 14)

def linear(size, a, b, diagonal=True):
    img = Image.new('RGB', (64, 64))
    px = img.load()
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126 if diagonal else y / 63
            px[x, y] = tuple(round(p + (q - p) * t) for p, q in zip(a, b))
    return img.resize((size, size), Image.BICUBIC)

def triangle(n, cx, r, grow=0.0):
    """A right-pointing triangle with rounded corners: a smaller triangle
    stroked with round joins. [grow] widens it (for cutting gaps)."""
    m = Image.new('L', (n, n), 0)
    d = ImageDraw.Draw(m)
    cr = CORNER * r
    inner = r - 2 * cr
    pts = [(cx + inner * math.cos(a), 0.5 + inner * math.sin(a))
           for a in (0, 2 * math.pi / 3, 4 * math.pi / 3)]
    pts = [(x * n, y * n) for x, y in pts]
    w = (2 * cr + grow) * n
    d.polygon(pts, fill=255)
    d.line(pts + [pts[0]], fill=255, width=round(w), joint='curve')
    for x, y in pts:
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=255)
    return m

def mark_mask(n, scale=1.0):
    """Alpha mask of the mark, scaled about the centre by [scale]."""
    mask = Image.new('L', (n, n), 0)
    for cx, r, opacity in LAYERS:
        cx, r = 0.5 + (cx - 0.5) * scale, r * scale
        gap = triangle(n, cx, r, grow=GAP * scale * 2)
        mask = Image.composite(Image.new('L', (n, n), 0), mask, gap)
        layer = triangle(n, cx, r).point(lambda v, o=opacity: int(v * o))
        mask = ImageChops.lighter(mask, layer)
    return mask

def mark(size, scale=1.0, glow=True):
    """The gradient mark (with a soft glow) on transparent."""
    n = size * S
    mask = mark_mask(n, scale)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    fill = linear(n, GOLD, CORAL).convert('RGBA')
    if glow:
        halo = mask.filter(ImageFilter.GaussianBlur(n * 0.035)).point(lambda v: int(v * 0.55))
        out.paste(fill, (0, 0), halo)
    out.paste(fill, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)

def icon(size, radius=0.225):
    n = size * S
    tile = linear(n, TILE_TOP, TILE_BOTTOM, diagonal=False).convert('RGBA')
    shape = Image.new('L', (n, n), 0)
    ImageDraw.Draw(shape).rounded_rectangle([0, 0, n - 1, n - 1], radius=radius * n, fill=255)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    out.paste(tile, (0, 0), shape)
    out = out.resize((size, size), Image.LANCZOS)
    out.alpha_composite(mark(size))
    return out

def main(root):
    """Writes every platform's icons. Run from the repo root:
    python tool/icons.py ."""
    import os
    j = lambda *p: os.path.join(root, *p)
    brand = j('assets', 'brand')
    os.makedirs(brand, exist_ok=True)
    full = icon(1024)
    full.save(j(brand, 'icon.png'))
    full.resize((256, 256), Image.LANCZOS).save(j(brand, 'icon_256.png'))

    # Windows: one .ico holding the sizes Explorer and the taskbar use.
    full.save(j('windows', 'runner', 'resources', 'app_icon.ico'),
              sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])

    # Android: legacy icons plus an adaptive icon (foreground + background).
    res = j('android', 'app', 'src', 'main', 'res')
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    fg = mark(1024, scale=0.66)
    for name, k in densities.items():
        d = j(res, f'mipmap-{name}')
        os.makedirs(d, exist_ok=True)
        full.resize((round(48 * k),) * 2, Image.LANCZOS).save(j(d, 'ic_launcher.png'))
        fg.resize((round(108 * k),) * 2, Image.LANCZOS).save(j(d, 'ic_launcher_foreground.png'))
        # Status bar icon: Android shows only the alpha channel.
        d = j(res, f'drawable-{name}')
        os.makedirs(d, exist_ok=True)
        n = round(24 * k)
        white = Image.new('RGBA', (n * S, n * S), (255, 255, 255, 0))
        white.putalpha(mark_mask(n * S, scale=1.15))
        white.resize((n, n), Image.LANCZOS).save(j(d, 'ic_stat_encore.png'))
    os.makedirs(j(res, 'mipmap-anydpi-v26'), exist_ok=True)
    with open(j(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w') as f:
        f.write("""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
""")
    with open(j(res, 'values', 'ic_launcher_background.xml'), 'w') as f:
        f.write("""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#%02X%02X%02X</color>
</resources>
""" % TILE_BOTTOM)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
    print('icons written')
