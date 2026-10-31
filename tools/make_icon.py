"""Draws the Pasr app icon: three fanned cards (mint, iris, coral) on ink. Output: 1024 px PNG."""
import math, sys
from PIL import Image, ImageDraw, ImageFilter

S = 4096
INK_TOP, INK_BOTTOM = (24, 26, 38), (8, 9, 14)
CARDS = [((46, 211, 166), -16, (-480, 60)), ((106, 92, 255), -4, (-40, -20)), ((255, 107, 87), 9, (380, -90))]

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def background():
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(INK_TOP, INK_BOTTOM, y / S))
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse([S*0.15, S*0.18, S*0.85, S*0.88], fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(420))
    img.paste(Image.new("RGB", (S, S), (90, 70, 230)), (0, 0), glow)
    return img

def card(color, show_code):
    w, h = 2300, int(2300 / 1.586)
    c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    grad = Image.new("RGBA", (w, h))
    gd = ImageDraw.Draw(grad)
    light = lerp(color, (255, 255, 255), 0.18); dark = lerp(color, (0, 0, 0), 0.22)
    for x in range(w):
        gd.line([(x, 0), (x, h)], fill=lerp(light, dark, x / w) + (255,))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=190, fill=255)
    c.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(c)
    d.rounded_rectangle([170, 170, 170 + 560, 170 + 110], radius=55, fill=(255, 255, 255, 150))
    if show_code:
        x, widths = 170, [44, 18, 30, 14, 44, 26, 18, 36, 14, 22, 44, 18, 30, 14, 26, 40, 18, 30]
        for i, bw in enumerate(widths * 2):
            if x + bw > w - 170: break
            if i % 2 == 0:
                d.rectangle([x, h - 520, x + bw, h - 170], fill=(255, 255, 255, 235))
            x += bw + 24
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=190, outline=(255, 255, 255, 60), width=10)
    return c

def main(out):
    img = background().convert("RGBA")
    for i, (color, angle, (dx, dy)) in enumerate(CARDS):
        c = card(color, i == len(CARDS) - 1).rotate(-angle, expand=True, resample=Image.BICUBIC)
        pad = 400
        alpha = Image.new("L", (c.width + 2 * pad, c.height + 2 * pad), 0)
        alpha.paste(c.split()[3].point(lambda a: int(a * 0.6)), (pad, pad))
        shadow = Image.new("RGBA", alpha.size, (0, 0, 0, 0))
        shadow.putalpha(alpha.filter(ImageFilter.GaussianBlur(90)))
        x = S // 2 - c.width // 2 + dx; y = S // 2 - c.height // 2 + dy
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        layer.paste(shadow, (x - pad + 30, y - pad + 140))
        img = Image.alpha_composite(img, layer)
        img.alpha_composite(c, (x, y))
    img.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(out)

if __name__ == "__main__":
    main(sys.argv[1])
