# Generates Assets.xcassets/DesignSystem colour sets (light, dark, Increased Contrast).
# Usage: python3 scripts/design-colors.py Filkollen/Resources/Assets.xcassets/DesignSystem
# Then copy DesignSystem/Champagne.colorset/Contents.json over AccentColor.colorset.
import json, os, sys
root = sys.argv[1]
os.makedirs(root, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": True}}, open(f"{root}/Contents.json", "w"), indent=2)

def hx(h):
    h = h.lstrip('#'); return [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
def mix(c, t, f): return [a + (b - a) * f for a, b in zip(c, t)]
def comp(c, a=1.0):
    r, g, b = c
    return {"color-space": "srgb", "components": {"red": f"{r:.3f}", "green": f"{g:.3f}", "blue": f"{b:.3f}", "alpha": f"{a:.3f}"}}

def colorset(name, light, dark, hc_light=None, hc_dark=None, alpha=(1, 1), hc_alpha=None):
    L, D = hx(light) if isinstance(light, str) else light, hx(dark) if isinstance(dark, str) else dark
    HL = hx(hc_light) if isinstance(hc_light, str) else (hc_light or mix(L, [0, 0, 0], 0.22))
    HD = hx(hc_dark) if isinstance(hc_dark, str) else (hc_dark or mix(D, [1, 1, 1], 0.25))
    ha = hc_alpha or alpha
    dark_ap = {"appearance": "luminosity", "value": "dark"}
    hc_ap = {"appearance": "contrast", "value": "high"}
    data = {"colors": [
        {"idiom": "universal", "color": comp(L, alpha[0])},
        {"idiom": "universal", "appearances": [dark_ap], "color": comp(D, alpha[1])},
        {"idiom": "universal", "appearances": [hc_ap], "color": comp(HL, ha[0])},
        {"idiom": "universal", "appearances": [dark_ap, hc_ap], "color": comp(HD, ha[1])},
    ], "info": {"author": "xcode", "version": 1}}
    d = f"{root}/{name}.colorset"; os.makedirs(d, exist_ok=True)
    json.dump(data, open(f"{d}/Contents.json", "w"), indent=2)

# Brand and status. Light values are >= 4.5:1 on the light window background (#ECECEC), dark values on the dark one (#323232) (checked in DesignTokenTests).
# "Noir" direction: champagne gold on onyx. Dark is the default theme.
colorset("Champagne", "#7A5A12", "#D9BA78", "#5C4309", "#F0D9A4")
# Text and glyphs on a champagne fill: white on the deep light-mode gold, ink on the bright dark-mode gold.
colorset("OnAccent", "#FFFFFF", "#17120A", "#FFFFFF", "#000000")
colorset("Success", "#22784A", "#5DC79B", "#17573A", "#A6EBC8")
colorset("Warning", "#8E5F00", "#E6B35E", "#6E4A00", "#F7D79A")
colorset("Danger", "#C2343A", "#F2777C", "#8F1F24", "#FFC2C4")
# Info is a quiet steel in the dark theme, so notes never compete with the champagne accent.
colorset("Info", "#2F5D8A", "#AFC0D3", "#1F4467", "#DCE6F2")

# Canvas: warm ivory in light mode, onyx in dark. The sidebar sits a step deeper.
colorset("Canvas", "#F5F2EC", "#0C0D10", "#FFFFFF", "#000000")
colorset("CanvasSunken", "#ECE8E0", "#08090B", "#E4E0D8", "#000000")

# Protection: calm to alert.
colorset("ProtectionSafe", "#3A7555", "#6FBF92", "#2C5C42", "#A3DDBC")
colorset("ProtectionAttention", "#8E5F00", "#E5A93B", "#6E4A00", "#F5CB7A")
colorset("ProtectionThreat", "#B42D33", "#FF6B6B", "#861E23", "#FFBDBD")

# Surfaces. Dark surfaces are white overlays so they sit on any window background.
colorset("Surface", "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF", alpha=(1, 0.045), hc_alpha=(1, 0.10))
colorset("SurfaceRaised", "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF", alpha=(1, 0.075), hc_alpha=(1, 0.16))
# On onyx a darker well would vanish, so dark "sunken" (tracks, wells, row hover) is a faint white instead.
colorset("SurfaceSunken", "#000000", "#FFFFFF", "#000000", "#FFFFFF", alpha=(0.035, 0.06), hc_alpha=(0.07, 0.16))
colorset("Border", "#3A2E14", "#FFFFFF", "#000000", "#FFFFFF", alpha=(0.10, 0.075), hc_alpha=(0.45, 0.50))
colorset("Shadow", "#000000", "#000000", "#000000", "#000000", alpha=(0.10, 0.60), hc_alpha=(0.20, 0.70))

# Category families: one lightness/chroma band each, white glyphs on top (>= 3:1).
cats = {
    # Regenerates: slate blue
    "CategorySystemJunk": ("#56698F", None),
    "CategoryBrowserCaches": ("#4A759F", "#6593C0"),
    "CategoryDeveloperJunk": ("#5A63A0", "#7480C0"),
    # Left behind: teal / sea green
    "CategoryAppLeftovers": ("#2B7F7D", "#46A5A2"),
    "CategoryOldInstallers": ("#357F6A", "#55A88F"),
    "CategoryIOSBackups": ("#357387", "#5298AD"),
    # Your own files: sand / amber
    "CategoryDuplicatePhotos": ("#9C6A2F", "#C99252"),
    "CategoryDuplicateFiles": ("#985F3C", "#C2845C"),
    "CategoryLargeFiles": ("#8A6B38", "#B6945C"),
}
# Dark mode lifts tiles only slightly so white glyphs keep >= 3:1; Increased Contrast deepens them.
for n, (l, d) in cats.items():
    base = hx(l)
    colorset(n, base, mix(base, [1, 1, 1], 0.06), mix(base, [0, 0, 0], 0.2), mix(base, [0, 0, 0], 0.15))
