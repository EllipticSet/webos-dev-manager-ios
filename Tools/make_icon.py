#!/usr/bin/env python3
"""Draws the app icon: a TV showing a terminal prompt. Requires Pillow. Usage: make_icon.py ICON.png LOGO.png

ICON.png is the opaque app icon; LOGO.png is the same artwork on transparency for the launch screen."""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4  # Supersampling factor.
SIZE = 1024 * S
BACKGROUND = (165, 0, 52)
PANEL = (255, 255, 255, 46)
WHITE = (255, 255, 255, 255)


def scaled(*values):
    return [v * S for v in values]


def layer():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def draw_artwork(canvas):
    d = ImageDraw.Draw(canvas)
    # Screen.
    d.rounded_rectangle(scaled(172, 212, 852, 700), radius=86 * S, fill=PANEL)
    d.rounded_rectangle(scaled(172, 212, 852, 700), radius=86 * S, outline=WHITE, width=46 * S)
    # Stand.
    d.rounded_rectangle(scaled(486, 680, 538, 800), radius=8 * S, fill=WHITE)
    d.rounded_rectangle(scaled(340, 778, 684, 826), radius=24 * S, fill=WHITE)
    # Prompt.
    d.line(scaled(292, 354, 402, 456, 292, 558), fill=WHITE, width=46 * S, joint="curve")
    for x, y in ((292, 354), (402, 456), (292, 558)):
        d.ellipse(scaled(x - 23, y - 23, x + 23, y + 23), fill=WHITE)
    d.rounded_rectangle(scaled(456, 514, 616, 560), radius=23 * S, fill=WHITE)
    # Signal dots.
    for x, y, r, alpha in ((688, 340, 38, 255), (610, 318, 20, 170), (722, 440, 24, 130)):
        d.ellipse(scaled(x - r, y - r, x + r, y + r), fill=(255, 255, 255, alpha))


def main(path, logo_path):
    icon = Image.new("RGBA", (SIZE, SIZE), BACKGROUND + (255,))
    art = layer()
    draw_artwork(art)
    shadow = Image.new("RGBA", (SIZE, SIZE), (40, 0, 10, 0))
    shadow.putalpha(art.getchannel("A").point(lambda v: v * 45 // 255))
    shadow = shadow.filter(ImageFilter.GaussianBlur(16 * S))
    icon.alpha_composite(shadow, (0, 10 * S))
    icon.alpha_composite(art)
    icon.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(path, "PNG")
    art.resize((600, 600), Image.LANCZOS).save(logo_path, "PNG")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
