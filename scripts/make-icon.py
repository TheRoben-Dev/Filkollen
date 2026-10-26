# Draws Filkollen's app icon (matte onyx with a brushed-champagne accent) and
# writes every size into AppIcon.appiconset.
# Usage: python3 scripts/make-icon.py ring-halo Filkollen/Resources/Assets.xcassets/AppIcon.appiconset
# ring-halo is the shipped icon; the other variants are the alternatives Roben compared.
# Needs Pillow and NumPy. The monogram uses Liberation Serif (fonts-liberation).
import sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

S = 2048; k = S / 1024
def B(*v): return [int(x * k) for x in v]

def lin(size, stops, angle=90):
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = math.radians(angle)
    t = (xx / w) * math.cos(a) + (yy / h) * math.sin(a)
    t = (t - t.min()) / (t.max() - t.min())
    out = np.zeros((h, w, 3), np.float32)
    pos = [p for p, _ in stops]; cols = [np.array(c, np.float32) for _, c in stops]
    for ch in range(3):
        out[..., ch] = np.interp(t, pos, [c[ch] for c in cols])
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGB")

def radial(size, center, radius, inner, outer):
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / radius
    t = np.clip(d, 0, 1)[..., None]
    out = np.array(inner, np.float32) * (1 - t) + np.array(outer, np.float32) * t
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGB")

GOLD = [(0, (247, 233, 196)), (0.32, (214, 182, 118)), (0.52, (150, 116, 58)), (0.72, (228, 203, 146)), (1, (160, 124, 64))]

def layer(fill, mask, opacity=1.0):
    m = mask if opacity == 1 else mask.point(lambda v: int(v * opacity))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0)); out.paste(fill, (0, 0), m); return out

def squircle_mask(inset=0):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(B(100 + inset, 100 + inset, 924 - inset, 924 - inset), radius=int((185 - inset) * k), fill=255)
    return m

def base(material="onyx"):
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sh).rounded_rectangle(B(110, 130, 914, 950), radius=int(185 * k), fill=120)
    icon.paste((0, 0, 0, 255), (0, 0), sh.filter(ImageFilter.GaussianBlur(24 * k)))
    body = squircle_mask()
    fill = lin((S, S), [(0, (38, 38, 44)), (0.55, (17, 17, 21)), (1, (9, 9, 11))], 90)
    icon.alpha_composite(layer(fill, body))
    # soft top reflection
    refl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(refl).ellipse(B(60, -420, 964, 430), fill=255)
    refl = ImageChops.multiply(refl.filter(ImageFilter.GaussianBlur(60 * k)), body)
    icon.alpha_composite(layer(Image.new("RGB", (S, S), (255, 255, 255)), refl, 0.06))
    # hairline edge: light on top, fading
    edge = ImageChops.subtract(body, squircle_mask(2.5))
    icon.alpha_composite(layer(lin((S, S), [(0, (255, 255, 255)), (0.4, (90, 90, 96)), (1, (40, 40, 44))], 90), edge, 0.35))
    return icon

def star(cx, cy, r, waist):
    m = Image.new("L", (S, S), 0); pts = []
    for i in range(8):
        a = math.pi / 4 * i - math.pi / 2; rr = r if i % 2 == 0 else waist
        pts.append(((cx + rr * math.cos(a)) * k, (cy + rr * math.sin(a)) * k))
    ImageDraw.Draw(m).polygon(pts, fill=255); return m

def ring_variant():
    icon = base()
    gold = lin((S, S), GOLD, 50)
    # glow behind ring
    g = Image.new("L", (S, S), 0); ImageDraw.Draw(g).ellipse(B(262, 262, 762, 762), outline=255, width=int(40 * k))
    icon.alpha_composite(layer(Image.new("RGB", (S, S), (217, 186, 120)), g.filter(ImageFilter.GaussianBlur(40 * k)), 0.18))
    # track
    t = Image.new("L", (S, S), 0); ImageDraw.Draw(t).ellipse(B(272, 272, 752, 752), outline=255, width=int(26 * k))
    icon.alpha_composite(layer(Image.new("RGB", (S, S), (255, 255, 255)), t, 0.06))
    # gold arc, open at the top right where the star sits
    r = Image.new("L", (S, S), 0); d = ImageDraw.Draw(r)
    d.arc(B(272, 272, 752, 752), start=-30, end=270 - 8, fill=255, width=int(26 * k))
    # round caps
    for ang in (-30, 262):
        a = math.radians(ang); cx = 512 + 227 * math.cos(a); cy = 512 + 227 * math.sin(a)
        d.ellipse(B(cx - 13, cy - 13, cx + 13, cy + 13), fill=255)
    icon.alpha_composite(layer(gold, r))
    icon.alpha_composite(layer(gold, star(668, 318, 54, 11)))
    return icon

def monogram_variant():
    icon = base()
    gold = lin((S, S), GOLD, 60)
    frame = Image.new("L", (S, S), 0); d = ImageDraw.Draw(frame)
    d.rounded_rectangle(B(176, 176, 848, 848), radius=int(118 * k), outline=255, width=int(5 * k))
    icon.alpha_composite(layer(gold, frame, 0.75))
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf", int(470 * k))
    m = Image.new("L", (S, S), 0); d = ImageDraw.Draw(m)
    bbox = d.textbbox((0, 0), "F", font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((S - w) / 2 - bbox[0], (S - h) / 2 - bbox[1] - 6 * k), "F", font=font, fill=255)
    # engraved: dark offset shadow then gold
    icon.alpha_composite(layer(Image.new("RGB", (S, S), (0, 0, 0)), ImageChops.offset(m, 0, int(4 * k)).filter(ImageFilter.GaussianBlur(3 * k)), 0.8))
    icon.alpha_composite(layer(gold, m))
    return icon

def folder_variant():
    icon = base()
    gold = lin((S, S), GOLD, 40)
    f = Image.new("L", (S, S), 0); d = ImageDraw.Draw(f)
    d.rounded_rectangle(B(236, 318, 470, 440), radius=int(36 * k), fill=255)
    d.rounded_rectangle(B(236, 370, 788, 742), radius=int(52 * k), fill=255)
    # graphite leather folder
    sh = f.filter(ImageFilter.GaussianBlur(20 * k))
    icon.alpha_composite(layer(Image.new("RGB", (S, S), (0, 0, 0)), ImageChops.offset(sh, 0, int(16 * k)), 0.55))
    icon.alpha_composite(layer(lin((S, S), [(0, (64, 63, 66)), (1, (30, 30, 34))], 90), f))
    # front flap slightly lighter
    flap = Image.new("L", (S, S), 0)
    ImageDraw.Draw(flap).rounded_rectangle(B(236, 420, 788, 742), radius=int(52 * k), fill=255)
    icon.alpha_composite(layer(lin((S, S), [(0, (78, 76, 78)), (1, (36, 35, 39))], 90), flap))
    # gold edge light on the flap's top edge
    eg = ImageChops.subtract(flap, ImageChops.offset(flap, 0, int(4 * k)))
    icon.alpha_composite(layer(gold, eg))
    # engraved check
    c = Image.new("L", (S, S), 0); d = ImageDraw.Draw(c)
    w = int(30 * k); pts = [(420 * k, 586 * k), (488 * k, 650 * k), (606 * k, 520 * k)]
    d.line(pts, fill=255, width=w, joint="curve")
    for x, y in (pts[0], pts[-1]): d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=255)
    icon.alpha_composite(layer(gold, c))
    return icon

def _arc(mask_draw, start, end, r=227, w=26):
    mask_draw.arc(B(512 - r, 512 - r, 512 + r, 512 + r), start=start, end=end, fill=255, width=int(w * k))
    for ang in (start, end):
        a = math.radians(ang); cx = 512 + (r - w / 2) * math.cos(a); cy = 512 + (r - w / 2) * math.sin(a)
        mask_draw.ellipse(B(cx - w / 2, cy - w / 2, cx + w / 2, cy + w / 2), fill=255)

BRIGHT_GOLD = [(0, (252, 240, 206)), (0.28, (226, 196, 134)), (0.5, (158, 122, 60)), (0.7, (238, 214, 160)), (1, (172, 134, 70))]

def _glow(icon, r, w, opacity):
    g = Image.new("L", (S, S), 0)
    ImageDraw.Draw(g).ellipse(B(512 - r, 512 - r, 512 + r, 512 + r), outline=255, width=int(w * k))
    icon.alpha_composite(layer(Image.new("RGB", (S, S), (217, 186, 120)), g.filter(ImageFilter.GaussianBlur(44 * k)), opacity))

def ring_classic():
    """The open ring with a star in the gap, in a brighter polished gold."""
    icon = base(); gold = lin((S, S), BRIGHT_GOLD, 50)
    _glow(icon, 240, 40, 0.22)
    t = Image.new("L", (S, S), 0); ImageDraw.Draw(t).ellipse(B(285, 285, 739, 739), outline=255, width=int(24 * k))
    icon.alpha_composite(layer(Image.new("RGB", (S, S), (255, 255, 255)), t, 0.05))
    r = Image.new("L", (S, S), 0); _arc(ImageDraw.Draw(r), -28, 262, r=227, w=24)
    icon.alpha_composite(layer(gold, r))
    icon.alpha_composite(layer(gold, star(668, 318, 58, 10)))
    return icon

def ring_segments():
    """Three arcs, like Smart Scan's segmented ring: one per kind of junk."""
    icon = base(); _glow(icon, 240, 40, 0.18)
    shades = [BRIGHT_GOLD, [(0, (226, 206, 160)), (1, (150, 124, 78))], [(0, (190, 170, 130)), (1, (110, 92, 60))]]
    for (start, end), stops in zip([(-80, 30), (44, 154), (168, 266)], shades):
        m = Image.new("L", (S, S), 0); _arc(ImageDraw.Draw(m), start, end, r=227, w=26)
        icon.alpha_composite(layer(lin((S, S), stops, 50), m))
    icon.alpha_composite(layer(lin((S, S), BRIGHT_GOLD, 50), star(512, 512, 92, 16)))
    return icon

def ring_halo():
    """A finer closed ring with an inner halo and the star at its centre."""
    icon = base(); gold = lin((S, S), BRIGHT_GOLD, 50)
    inner = Image.new("L", (S, S), 0); ImageDraw.Draw(inner).ellipse(B(300, 300, 724, 724), fill=255)
    icon.alpha_composite(layer(radial((S, S), (512 * k, 470 * k), 240 * k, (90, 74, 44), (16, 16, 19)), inner, 0.85))
    _glow(icon, 236, 30, 0.25)
    r = Image.new("L", (S, S), 0); ImageDraw.Draw(r).ellipse(B(290, 290, 734, 734), outline=255, width=int(14 * k))
    icon.alpha_composite(layer(gold, r))
    icon.alpha_composite(layer(gold, star(512, 512, 120, 18)))
    icon.alpha_composite(layer(gold, star(612, 400, 34, 7), 0.9))
    return icon

VARIANTS = {"ring": ring_variant, "ring-classic": ring_classic, "ring-segments": ring_segments, "ring-halo": ring_halo, "monogram": monogram_variant, "folder": folder_variant}

if __name__ == "__main__":
    variant, out = sys.argv[1], sys.argv[2]
    icon = VARIANTS[variant]()
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            icon.resize((px, px), Image.LANCZOS).save(f"{out}/icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png")
