# Generates Assets.xcassets/DesignSystem colour sets (light, dark, Increased Contrast).
# Usage: python3 scripts/design-colors.py Filkollen/Resources/Assets.xcassets/DesignSystem
# Then copy DesignSystem/Fjord.colorset/Contents.json over AccentColor.colorset.
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
colorset("Fjord", "#0D757E", "#45B8C1", "#08565D", "#8FDCE2")
colorset("Success", "#22784A", "#4CC38A", "#17573A", "#8FE3B8")
colorset("Warning", "#8E5F00", "#E5A93B", "#6E4A00", "#F5CB7A")
colorset("Danger", "#C2343A", "#FF6B6B", "#8F1F24", "#FFA3A3")
colorset("Info", "#0B63CE", "#5AA9FF", "#084A9C", "#99CCFF")

# Protection: calm to alert.
colorset("ProtectionSafe", "#3A7555", "#6FBF92", "#2C5C42", "#A3DDBC")
colorset("ProtectionAttention", "#8E5F00", "#E5A93B", "#6E4A00", "#F5CB7A")
colorset("ProtectionThreat", "#B42D33", "#FF6B6B", "#861E23", "#FFA3A3")

# Surfaces. Dark surfaces are white overlays so they sit on any window background.
colorset("Surface", "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF", alpha=(1, 0.05), hc_alpha=(1, 0.10))
colorset("SurfaceRaised", "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF", alpha=(1, 0.09), hc_alpha=(1, 0.16))
colorset("SurfaceSunken", "#000000", "#000000", "#000000", "#000000", alpha=(0.035, 0.18), hc_alpha=(0.07, 0.30))
colorset("Border", "#000000", "#FFFFFF", "#000000", "#FFFFFF", alpha=(0.09, 0.09), hc_alpha=(0.45, 0.50))
colorset("Shadow", "#000000", "#000000", "#000000", "#000000", alpha=(0.10, 0.45), hc_alpha=(0.20, 0.60))

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
