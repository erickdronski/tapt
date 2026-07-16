#!/usr/bin/env python3
"""Compose Tapt's App Store screenshot carousel (6.9", 1290x2796).

Input: five raw iPhone 17 Pro captures (1206x2622) named 01_home.png,
02_market.png, 03_beer.png, 04_cellar.png, 05_nearyou.png in RAW_DIR.
Output: the five composed marketing panels in this directory (RGB PNG,
no alpha, exactly 1290x2796 so scripts/asc_upload_screenshots.py accepts
them) plus _contact_sheet.png.

Usage:
  RAW_DIR=/path/to/raws FONT_DIR=/path/to/poppins python3 make_carousel.py

Fonts: Poppins ExtraBold + Medium (OFL). Copy voice: plain, honest, no
em dashes, no hype. Every panel is a real, unedited app capture.
"""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
RAW_DIR = Path(os.environ.get("RAW_DIR", HERE / "raw"))
FONT_DIR = Path(os.environ.get("FONT_DIR", HERE / "fonts"))
REPO_ROOT = HERE.parents[1]

W, H = 1290, 2796
GOLD = (242, 169, 0)
FOAM = (251, 246, 236)
SUB = (201, 191, 169)
BG_TOP = (26, 18, 6)
BG_BOTTOM = (13, 8, 2)

MARGIN = 96
SHOT_W = 1080           # device screenshot display width
SHOT_RADIUS = 64
BEZEL = 16
DEVICE_TOP = 800

SLIDES = [
    {
        "raw": "01_home.png",
        "out": "01_superapp.png",
        "head": [("All of beer,", "foam"), ("one app.", "gold")],
        "sub": "Scan, rate, log, and discover beer.",
    },
    {
        "raw": "02_market.png",
        "out": "02_market.png",
        "head": [("The global", "foam"), ("Beer Market.", "gold")],
        "sub": "Beers rise and fall on real votes.",
    },
    {
        "raw": "03_beer.png",
        "out": "03_beerpage.png",
        "head": [("Every beer,", "foam"), ("one page.", "gold")],
        "sub": "Style, story, ratings, and movement.",
    },
    {
        "raw": "04_cellar.png",
        "out": "04_passport.png",
        "head": [("Your Beer", "foam"), ("Passport.", "gold")],
        "sub": "Stamps for exploring, not for drinking.",
    },
    {
        "raw": "05_nearyou.png",
        "out": "05_nearyou.png",
        "head": [("Find beer", "foam"), ("near you.", "gold")],
        "sub": "Breweries, pubs, and taprooms on the map.",
    },
]


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_DIR / name), size)


def vertical_gradient() -> Image.Image:
    strip = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        strip.putpixel(
            (0, y),
            tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)),
        )
    return strip.resize((W, H))


def gold_glow(canvas: Image.Image) -> None:
    """Soft radial glow behind the device so the panel has light and depth."""
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse((W // 2 - 640, 560, W // 2 + 640, 1900), fill=GOLD + (60,))
    glow = glow.filter(ImageFilter.GaussianBlur(230))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), glow).convert("RGB"))


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0) + size, radius=radius, fill=255)
    return mask


def compose(slide: dict) -> Image.Image:
    canvas = vertical_gradient()
    gold_glow(canvas)
    draw = ImageDraw.Draw(canvas)

    # Header lockup: app icon + wordmark
    icon = Image.open(REPO_ROOT / "landing" / "icon-192.png").convert("RGBA")
    icon = icon.resize((96, 96), Image.LANCZOS)
    canvas.paste(icon, (MARGIN, 104), icon)
    draw.text(
        (MARGIN + 120, 112),
        "Tapt",
        font=font("Poppins-SemiBold.ttf", 66),
        fill=FOAM,
    )

    # Headline: two lines, one gold
    head_font = font("Poppins-ExtraBold.ttf", 124)
    y = 330
    for text, color in slide["head"]:
        while draw.textlength(text, font=head_font) > W - 2 * MARGIN:
            head_font = font("Poppins-ExtraBold.ttf", head_font.size - 4)
        draw.text(
            (MARGIN, y),
            text,
            font=head_font,
            fill=GOLD if color == "gold" else FOAM,
        )
        y += int(head_font.size * 1.16)

    # Subline
    draw.text((MARGIN, y + 26), slide["sub"], font=font("Poppins-Medium.ttf", 55), fill=SUB)

    # Device: shadow, bezel, gold hairline, rounded screenshot, bottom bleed
    shot = Image.open(RAW_DIR / slide["raw"]).convert("RGB")
    scale = SHOT_W / shot.width
    shot = shot.resize((SHOT_W, int(shot.height * scale)), Image.LANCZOS)
    x0 = (W - SHOT_W) // 2

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x0 - BEZEL, DEVICE_TOP - BEZEL + 50, x0 + SHOT_W + BEZEL, H + 200),
        radius=SHOT_RADIUS + BEZEL,
        fill=(0, 0, 0, 175),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(55))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB"))
    draw = ImageDraw.Draw(canvas)

    draw.rounded_rectangle(
        (x0 - BEZEL, DEVICE_TOP - BEZEL, x0 + SHOT_W + BEZEL, H + 200),
        radius=SHOT_RADIUS + BEZEL,
        fill=(9, 6, 3),
        outline=(146, 104, 16),
        width=3,
    )
    canvas.paste(
        shot,
        (x0, DEVICE_TOP),
        rounded_mask(shot.size, SHOT_RADIUS),
    )
    return canvas


def main() -> None:
    outputs = []
    for slide in SLIDES:
        panel = compose(slide)
        assert panel.size == (W, H)
        out = HERE / slide["out"]
        panel.convert("RGB").save(out, "PNG")
        outputs.append(out)
        print("wrote", out.name)

    thumb_w = 316
    sheet = Image.new("RGB", (thumb_w * 5 + 6 * 12, int(thumb_w * H / W) + 24), (20, 14, 6))
    for i, out in enumerate(outputs):
        thumb = Image.open(out).resize((thumb_w, int(thumb_w * H / W)), Image.LANCZOS)
        sheet.paste(thumb, (12 + i * (thumb_w + 12), 12))
    sheet.save(HERE / "_contact_sheet.png", "PNG")
    print("wrote _contact_sheet.png")


if __name__ == "__main__":
    main()
