# Draws the Noir app icon (champagne folder-with-check and sparkles on onyx) and
# writes every size into AppIcon.appiconset.
# Usage: python3 scripts/make-icon.py Filkollen/Resources/Assets.xcassets/AppIcon.appiconset
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # draw at 4x 1024, then downsample for smooth edges
k = S / 1024

def box(x0, y0, x1, y1): return [int(x0 * k), int(y0 * k), int(x1 * k), int(y1 * k)]

def vgradient(size, top, bottom):
    w, h = size
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        g.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return g.resize((w, h))

def masked(fill, mask):
    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    out.paste(fill, (0, 0), mask)
    return out

icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Soft drop shadow under the squircle.
shadow = Image.new("L", (S, S), 0)
ImageDraw.Draw(shadow).rounded_rectangle(box(100, 116, 924, 940), radius=int(185 * k), fill=150)
shadow = shadow.filter(ImageFilter.GaussianBlur(28 * k))
icon.paste((0, 0, 0, 255), (0, 0), shadow)

# Onyx body with a warm glow from the top.
body = Image.new("L", (S, S), 0)
ImageDraw.Draw(body).rounded_rectangle(box(100, 100, 924, 924), radius=int(185 * k), fill=255)
onyx = vgradient((S, S), (30, 30, 36), (8, 9, 11))
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse(box(180, -260, 844, 420), fill=70)
glow = glow.filter(ImageFilter.GaussianBlur(90 * k))
onyx.paste((217, 186, 120), (0, 0), glow)
icon.alpha_composite(masked(onyx, body))

# Champagne rim.
rim = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(rim)
d.rounded_rectangle(box(100, 100, 924, 924), radius=int(185 * k), fill=255)
d.rounded_rectangle(box(106, 106, 918, 918), radius=int(179 * k), fill=0)
icon.alpha_composite(masked(vgradient((S, S), (240, 217, 164), (90, 70, 30)), rim))

gold = vgradient((S, S), (246, 226, 174), (176, 134, 62))

# Folder with a check cut out of it.
folder = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(folder)
d.rounded_rectangle(box(282, 300, 520, 470), radius=int(48 * k), fill=255)
d.rounded_rectangle(box(282, 360, 772, 820), radius=int(70 * k), fill=255)
w = int(78 * k)
pts = [(int(392 * k), int(596 * k)), (int(500 * k), int(702 * k)), (int(676 * k), int(500 * k))]
d.line(pts, fill=0, width=w, joint="curve")
for x, y in (pts[0], pts[-1]):
    d.ellipse([x - w // 2, y - w // 2, x + w // 2, y + w // 2], fill=0)
icon.alpha_composite(masked(gold, folder))

def sparkle(cx, cy, r, waist):
    m = Image.new("L", (S, S), 0)
    pts = []
    for i in range(8):
        import math
        a = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else waist
        pts.append((int((cx + rr * math.cos(a)) * k), int((cy + rr * math.sin(a)) * k)))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m

icon.alpha_composite(masked(gold, sparkle(772, 262, 92, 20)))
icon.alpha_composite(masked(gold, sparkle(860, 400, 46, 11)))

out = sys.argv[1]
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        icon.resize((px, px), Image.LANCZOS).save(f"{out}/{name}")
