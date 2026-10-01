# Generates icon/AppIcon.icns (and AppIcon.png) for asmmesh: a small mesh of
# nodes on a deep blue-to-teal squircle. Needs Pillow.
from PIL import Image, ImageDraw, ImageFilter
import math, os

S = 2048                       # draw at 2x, downsample for smooth edges
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# body: macOS icon grid, 824/1024 of the canvas, rounded
m, r = int(S * 100 / 1024), int(S * 185 / 1024)
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
top, bot = (12, 28, 64), (10, 120, 132)
for y in range(S):
    t = y / S
    gd.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bot)) + (255,))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([m, m, S - m, S - m], r, fill=255)
img.paste(grad, (0, 0), mask)

# nodes (fractions of the body) and links between them
nodes = [(0.50, 0.50), (0.24, 0.30), (0.74, 0.24), (0.80, 0.62),
         (0.56, 0.82), (0.22, 0.70), (0.44, 0.22)]
links = [(0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (1, 6), (6, 2), (2, 3),
         (3, 4), (4, 5), (5, 1)]
body = S - 2 * m
P = [(m + x * body, m + y * body) for x, y in nodes]

glow = Image.new("RGBA", (S, S), (80, 230, 255, 0))
g = ImageDraw.Draw(glow)
lines = Image.new("RGBA", (S, S), (170, 240, 255, 0))
l = ImageDraw.Draw(lines)
for a, b in links:
    l.line([P[a], P[b]], fill=(170, 240, 255, 150), width=int(S * 0.012))
for i, (x, y) in enumerate(P):
    rr = S * (0.075 if i == 0 else 0.045)
    g.ellipse([x - rr * 1.9, y - rr * 1.9, x + rr * 1.9, y + rr * 1.9], fill=(80, 230, 255, 150))
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.02))

layer = Image.alpha_composite(glow, lines)
d = ImageDraw.Draw(layer)
# ripples around the centre node: a message spreading
cx, cy = P[0]
for k, a in ((1.9, 200), (2.7, 130)):
    rr = S * 0.075 * k
    d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(200, 250, 255, a), width=int(S * 0.006))
for i, (x, y) in enumerate(P):
    rr = S * (0.075 if i == 0 else 0.045)
    d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(255, 255, 255, 255))
    ir = rr * 0.45
    d.ellipse([x - ir, y - ir, x + ir, y + ir], fill=(20, 150, 170, 255) if i else (12, 60, 110, 255))

clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(layer, (0, 0), mask)
img = Image.alpha_composite(img, clipped)

out = img.resize((1024, 1024), Image.LANCZOS)
here = os.path.dirname(os.path.abspath(__file__))
out.save(os.path.join(here, "AppIcon.png"))
out.save(os.path.join(here, "AppIcon.icns"),
         sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
print("wrote AppIcon.icns")
