#!/usr/bin/env python3
"""
TheWindowsLinux – Asset-Generator
=================================

Erzeugt alle Grafiken und Sounds der beiden Stile als Original-Artwork
(keine Microsoft-Dateien):

  theme/styles/retro/   Pixel-Retro-Look (Windows-95-artig, 16-Farben-VGA-Palette,
                        Dithering, Pixel-Icons, Pixel-Cursor, Chiptune-Sounds)
  theme/styles/aero/    Windows-7-Aero-Look (Glas-Rahmen, Orb, Swirl-Wallpaper)

Je Stil entstehen:
  gtk/<Theme>/gtk-3.0/assets/*.png   (nur retro: Dither-Muster, Pfeile, Häkchen)
  xfwm4/<Theme>/*.png                (Fensterrahmen + Titelleisten-Buttons)
  icons/<Theme>/...                  (Start-Button, Computer, Papierkorb, Ordner, ...)
  cursors/<Theme>/                   (nur retro: Xcursor-Theme, benötigt xcursorgen)
  wallpapers/*.png, sounds/*.wav
und docs/preview-<stil>.png (Mockup).

Aufruf:  python3 tools/generate-assets.py [--style retro|aero|all] [--only wallpaper|xfwm|icons|cursors|sounds|preview|gtk]
"""
import argparse
import math
import os
import shutil
import subprocess
import sys
import wave

from PIL import Image, ImageDraw, ImageFilter, ImageFont

try:
    import numpy as np
except ImportError:  # Sounds werden dann übersprungen
    np = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STYLES = os.path.join(ROOT, "theme", "styles")
SS = 4  # Supersampling-Faktor (nur Aero)

FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/TTF", "/usr/share/fonts/dejavu"]
PIXEL_FONTS = [
    "/usr/share/fonts/opentype/unifont/unifont.otf",
    "/usr/share/fonts/truetype/unifont/unifont.ttf",
    "/usr/share/fonts/opentype/terminus/terminus-normal.otb",
]


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def pixel_font(size=16):
    for p in PIXEL_FONTS:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                continue
    return ImageFont.load_default()


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def ensure(path):
    os.makedirs(path, exist_ok=True)
    return path


def downscale(img, size):
    return img.resize(size, Image.LANCZOS)


def upscale(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def vgradient(size, stops, alpha=255):
    """Vertikaler Farbverlauf. stops = [(pos 0..1, (r,g,b)), ...]"""
    w, h = size
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                c = lerp(c0, c1, (t - p0) / max(1e-6, (p1 - p0)))
                break
        else:
            c = stops[-1][1]
        for x in range(w):
            px[x, y] = (*c, alpha)
    return img


# ===========================================================================
#  RETRO  (Windows-95-artig, Pixelgrafik)
# ===========================================================================
VGA = {
    "k": (0, 0, 0), "n": (0, 0, 128), "g": (0, 128, 0), "t": (0, 128, 128),
    "m": (128, 0, 0), "p": (128, 0, 128), "o": (128, 128, 0), "s": (192, 192, 192),
    "a": (128, 128, 128), "b": (0, 0, 255), "l": (0, 255, 0), "c": (0, 255, 255),
    "r": (255, 0, 0), "f": (255, 0, 255), "y": (255, 255, 0), "w": (255, 255, 255),
    "d": (223, 223, 223),  # Win98-Lichtkante
}
BLACK, NAVY, TEAL, SILVER, GRAY, WHITE, LIGHT = VGA["k"], VGA["n"], VGA["t"], VGA["s"], VGA["a"], VGA["w"], VGA["d"]

BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def sprite(rows, scale=1):
    """Pixel-Sprite aus Zeichenketten (Buchstaben = VGA-Palette, '.' = transparent)."""
    h = len(rows)
    w = max(len(r) for r in rows)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != "." and ch != " ":
                px[x, y] = (*VGA[ch], 255)
    return upscale(img, scale) if scale > 1 else img


def rect(d, x0, y0, x1, y1, fill=None, outline=None):
    """Rechteck inkl. Endpunkte, ohne Antialiasing."""
    if fill is not None:
        d.rectangle([x0, y0, x1, y1], fill=fill)
    if outline is not None:
        d.rectangle([x0, y0, x1, y1], outline=outline)


def bevel_raised(d, x0, y0, x1, y1, fill=SILVER, light=WHITE, dark=BLACK, inner_light=None, inner_dark=GRAY):
    """Win95-Erhebung: außen hell oben/links, dunkel unten/rechts; innen zweite Stufe."""
    rect(d, x0, y0, x1, y1, fill=fill)
    d.line([x0, y0, x1 - 1, y0], fill=light)
    d.line([x0, y0, x0, y1 - 1], fill=light)
    d.line([x0, y1, x1, y1], fill=dark)
    d.line([x1, y0, x1, y1], fill=dark)
    if inner_dark:
        d.line([x0 + 1, y1 - 1, x1 - 1, y1 - 1], fill=inner_dark)
        d.line([x1 - 1, y0 + 1, x1 - 1, y1 - 1], fill=inner_dark)
    if inner_light:
        d.line([x0 + 1, y0 + 1, x1 - 2, y0 + 1], fill=inner_light)
        d.line([x0 + 1, y0 + 1, x0 + 1, y1 - 2], fill=inner_light)


def bevel_sunken(d, x0, y0, x1, y1, fill=WHITE):
    rect(d, x0, y0, x1, y1, fill=fill)
    d.line([x0, y0, x1 - 1, y0], fill=GRAY)
    d.line([x0, y0, x0, y1 - 1], fill=GRAY)
    d.line([x0 + 1, y0 + 1, x1 - 2, y0 + 1], fill=BLACK)
    d.line([x0 + 1, y0 + 1, x0 + 1, y1 - 2], fill=BLACK)
    d.line([x0, y1, x1, y1], fill=WHITE)
    d.line([x1, y0, x1, y1], fill=WHITE)
    d.line([x0 + 1, y1 - 1, x1 - 1, y1 - 1], fill=LIGHT)
    d.line([x1 - 1, y0 + 1, x1 - 1, y1 - 1], fill=LIGHT)


def dither_fill(img, box, c0, c1, threshold=0.5):
    """Ordered Dithering (Bayer 4x4) zwischen zwei Farben."""
    px = img.load()
    x0, y0, x1, y1 = box
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            t = (BAYER4[y % 4][x % 4] + 0.5) / 16.0
            px[x, y] = (*(c1 if t < threshold else c0), 255)


def pixel_text(img, xy, text, color, size=16, fnt=None):
    """Text ohne Antialiasing (harte Pixel) zeichnen."""
    fnt = fnt or pixel_font(size)
    mask = fnt.getmask(text, mode="1")
    w, h = mask.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    lp = layer.load()
    for y in range(h):
        for x in range(w):
            if mask.getpixel((x, y)):
                lp[x, y] = (*color, 255)
    img.alpha_composite(layer, (int(xy[0]), int(xy[1])))
    return w, h


# ---------------------------------------------------------------------------
# Retro: Wallpaper (480x270 Basis, 4x hochskaliert → 1920x1080)
# ---------------------------------------------------------------------------
def retro_wallpaper(w=480, h=270, logo=True):
    img = Image.new("RGBA", (w, h))
    px = img.load()
    # Himmel: gedithert von Schwarz (oben) über Navy zu Teal (unten)
    stops = [(0.0, BLACK), (0.45, NAVY), (1.0, TEAL)]
    for y in range(h):
        t = y / (h - 1)
        # Farbe zwischen zwei Palettenfarben mit Bayer-Dithering wählen
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                f = (t - p0) / (p1 - p0)
                break
        for x in range(w):
            thr = (BAYER4[y % 4][x % 4] + 0.5) / 16.0
            px[x, y] = (*(c1 if f > thr else c0), 255)
    d = ImageDraw.Draw(img)
    # Sterne
    import random
    rnd = random.Random(1995)
    for _ in range(90):
        x, y = rnd.randrange(w), rnd.randrange(int(h * 0.55))
        c = WHITE if rnd.random() < 0.3 else SILVER
        px[x, y] = (*c, 255)
        if rnd.random() < 0.15:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < w and 0 <= y + dy < h:
                    px[x + dx, y + dy] = (*SILVER, 255)
    # Pixel-Wolken (zwei Töne) in der unteren Hälfte
    def cloud(cx, cy, r, c_light, c_dark):
        for (ox, oy, rr) in ((0, 0, r), (-r, r // 3, int(r * 0.8)), (r, r // 3, int(r * 0.85)), (-r // 2, -r // 3, int(r * 0.7)), (r // 2, -r // 4, int(r * 0.75))):
            d.ellipse([cx + ox - rr, cy + oy - rr // 2, cx + ox + rr, cy + oy + rr // 2], fill=(*c_dark, 255))
        for (ox, oy, rr) in ((0, -2, r - 3), (-r, r // 3 - 2, int(r * 0.8) - 3), (r, r // 3 - 2, int(r * 0.85) - 3)):
            d.ellipse([cx + ox - rr, cy + oy - rr // 2, cx + ox + rr, cy + oy + rr // 2 - 2], fill=(*c_light, 255))
    for (cx, cy, r) in ((70, 205, 26), (400, 190, 32), (250, 235, 22), (160, 250, 18), (330, 258, 20)):
        cloud(cx, cy, r, SILVER, GRAY)
    # Horizont-Raster (90er-"Cyber"-Boden) unten
    for y in range(int(h * 0.86), h, 6):
        d.line([0, y, w, y], fill=(*VGA["c"], 255))
    for i in range(-10, 11):
        d.line([w // 2 + i * 8, int(h * 0.86), w // 2 + i * 60, h], fill=(*VGA["c"], 255))
    if logo:
        if "win7-start" not in RETRO_SPRITES32:
            build_sprites32()
        lx, ly = w // 2 - 20, h // 2 - 34
        logo_img = upscale(RETRO_SPRITES32["win7-start"], 1)
        img.alpha_composite(logo_img, (lx + 4, ly))
        fnt = pixel_font(16)
        text = "TheWindowsLinux"
        tw = fnt.getmask(text, mode="1").size[0]
        pixel_text(img, (w // 2 - tw // 2 + 1, ly + 37), text, BLACK, fnt=fnt)
        pixel_text(img, (w // 2 - tw // 2, ly + 36), text, WHITE, fnt=fnt)
    return img


def retro_gen_wallpapers(out):
    ensure(out)
    base = retro_wallpaper()
    upscale(base, 4).convert("RGB").save(os.path.join(out, "retro.png"), optimize=True)
    base.convert("RGB").save(os.path.join(out, "retro-480x270.png"), optimize=True)
    # Anmeldebildschirm: ohne Logo, dunkler
    login = retro_wallpaper(logo=False)
    dark = Image.new("RGBA", login.size, (0, 0, 0, 110))
    login = Image.alpha_composite(login, dark)
    upscale(login, 4).convert("RGB").save(os.path.join(out, "retro-login.png"), optimize=True)
    # Klassisch: einfarbig Teal + Dither-Variante
    solid = Image.new("RGB", (1920, 1080), TEAL)
    solid.save(os.path.join(out, "retro-teal.png"), optimize=True)
    print("  retro wallpapers ok")


# ---------------------------------------------------------------------------
# Retro: xfwm4-Rahmen (pixelgenau, Win95-Fensterrahmen)
# ---------------------------------------------------------------------------
R_FRAME = 4        # Rahmenbreite
R_TITLE = 18       # Titelhöhe
R_TH = R_FRAME + R_TITLE  # Höhe der Titel-Bilder (22)
R_BTN_W, R_BTN_H = 16, 14


def retro_top_rows(d, w):
    """Die obersten 4 Rahmenzeilen (hell oben, ohne seitliche Ecken)."""
    rect(d, 0, 0, w - 1, R_FRAME - 1, fill=SILVER)
    d.line([0, 0, w - 1, 0], fill=SILVER)
    d.line([0, 1, w - 1, 1], fill=WHITE)


def retro_frame_piece(kind, active):
    title_bg = NAVY if active else GRAY
    if kind.startswith("title-"):
        img = Image.new("RGBA", (2, R_TH), (*title_bg, 255))
        d = ImageDraw.Draw(img)
        retro_top_rows(d, 2)
        return img
    if kind == "top-left":
        img = Image.new("RGBA", (8, R_TH), (*title_bg, 255))
        d = ImageDraw.Draw(img)
        retro_top_rows(d, 8)
        rect(d, 0, 0, R_FRAME - 1, R_TH - 1, fill=SILVER)
        d.line([0, 0, 0, R_TH - 1], fill=SILVER)
        d.line([1, 1, 1, R_TH - 1], fill=WHITE)
        d.line([0, 0, 7, 0], fill=SILVER)
        d.line([1, 1, 7, 1], fill=WHITE)
        return img
    if kind == "top-right":
        img = Image.new("RGBA", (8, R_TH), (*title_bg, 255))
        d = ImageDraw.Draw(img)
        retro_top_rows(d, 8)
        rect(d, 8 - R_FRAME, 0, 7, R_TH - 1, fill=SILVER)
        d.line([0, 0, 7, 0], fill=SILVER)
        d.line([0, 1, 6, 1], fill=WHITE)
        d.line([7, 0, 7, R_TH - 1], fill=BLACK)
        d.line([6, 1, 6, R_TH - 1], fill=GRAY)
        return img
    if kind == "left":
        img = Image.new("RGBA", (R_FRAME, 1), (*SILVER, 255))
        px = img.load()
        px[0, 0] = (*SILVER, 255); px[1, 0] = (*WHITE, 255)
        return img
    if kind == "right":
        img = Image.new("RGBA", (R_FRAME, 1), (*SILVER, 255))
        px = img.load()
        px[3, 0] = (*BLACK, 255); px[2, 0] = (*GRAY, 255)
        return img
    if kind == "bottom":
        img = Image.new("RGBA", (1, R_FRAME), (*SILVER, 255))
        px = img.load()
        px[0, 3] = (*BLACK, 255); px[0, 2] = (*GRAY, 255)
        return img
    if kind == "bottom-left":
        img = Image.new("RGBA", (8, 8), (*SILVER, 255))
        d = ImageDraw.Draw(img)
        d.line([0, 0, 0, 7], fill=SILVER)
        d.line([1, 0, 1, 6], fill=WHITE)
        d.line([0, 7, 7, 7], fill=BLACK)
        d.line([1, 6, 7, 6], fill=GRAY)
        return img
    if kind == "bottom-right":
        img = Image.new("RGBA", (8, 8), (*SILVER, 255))
        d = ImageDraw.Draw(img)
        d.line([7, 0, 7, 7], fill=BLACK)
        d.line([6, 0, 6, 6], fill=GRAY)
        d.line([0, 7, 7, 7], fill=BLACK)
        d.line([0, 6, 6, 6], fill=GRAY)
        return img
    raise ValueError(kind)


def retro_glyph(d, kind, ox, oy, color=BLACK):
    """Button-Symbol (Ursprung = linke obere Ecke der 16x14-Fläche)."""
    if kind == "hide":
        rect(d, ox + 4, oy + 9, ox + 9, oy + 10, fill=color)
    elif kind == "maximize":
        rect(d, ox + 3, oy + 2, ox + 11, oy + 10, outline=color)
        d.line([ox + 3, oy + 3, ox + 11, oy + 3], fill=color)
    elif kind == "restore":
        rect(d, ox + 5, oy + 2, ox + 11, oy + 7, outline=color)
        d.line([ox + 5, oy + 3, ox + 11, oy + 3], fill=color)
        rect(d, ox + 3, oy + 5, ox + 9, oy + 10, fill=SILVER, outline=color)
        d.line([ox + 3, oy + 6, ox + 9, oy + 6], fill=color)
    elif kind == "close":
        for i in range(7):
            d.point([(ox + 4 + i, oy + 3 + i), (ox + 5 + i, oy + 3 + i), (ox + 10 - i, oy + 3 + i), (ox + 11 - i, oy + 3 + i)], fill=color)
    elif kind == "shade":
        for i in range(4):
            d.line([ox + 4 + i, oy + 8 - i, ox + 10 - i, oy + 8 - i], fill=color)
    elif kind == "unshade":
        for i in range(4):
            d.line([ox + 4 + i, oy + 4 + i, ox + 10 - i, oy + 4 + i], fill=color)
    elif kind == "stick":
        rect(d, ox + 5, oy + 4, ox + 9, oy + 8, outline=color)
    elif kind == "unstick":
        rect(d, ox + 5, oy + 4, ox + 9, oy + 8, fill=color)


def retro_button(kind, state, active, gap_left=0):
    title_bg = NAVY if active else GRAY
    w = R_BTN_W + gap_left
    img = Image.new("RGBA", (w, R_TH), (*title_bg, 255))
    d = ImageDraw.Draw(img)
    retro_top_rows(d, w)
    bx, by = gap_left, R_FRAME + 2
    pressed = state == "pressed"
    if pressed:
        rect(d, bx, by, bx + R_BTN_W - 1, by + R_BTN_H - 1, fill=SILVER)
        d.line([bx, by, bx + R_BTN_W - 1, by], fill=BLACK)
        d.line([bx, by, bx, by + R_BTN_H - 1], fill=BLACK)
        d.line([bx + 1, by + 1, bx + R_BTN_W - 2, by + 1], fill=GRAY)
        d.line([bx + 1, by + 1, bx + 1, by + R_BTN_H - 2], fill=GRAY)
        d.line([bx, by + R_BTN_H - 1, bx + R_BTN_W - 1, by + R_BTN_H - 1], fill=WHITE)
        d.line([bx + R_BTN_W - 1, by, bx + R_BTN_W - 1, by + R_BTN_H - 1], fill=WHITE)
        glyph_off = 1
    else:
        bevel_raised(d, bx, by, bx + R_BTN_W - 1, by + R_BTN_H - 1, inner_light=LIGHT)
        glyph_off = 0
    glyph = {"maximize-toggled": "restore", "shade-toggled": "unshade", "stick-toggled": "unstick"}.get(kind, kind)
    retro_glyph(d, glyph, bx + glyph_off, by + glyph_off)
    if state == "inactive" and glyph == "close":
        pass  # Win95: Buttons sehen inaktiv gleich aus
    return img


def retro_gen_xfwm(out):
    ensure(out)
    for active in (True, False):
        suffix = "active" if active else "inactive"
        for kind in ("top-left", "top-right", "title-1", "title-2", "title-3", "title-4", "title-5",
                     "left", "right", "bottom", "bottom-left", "bottom-right"):
            retro_frame_piece(kind, active).save(os.path.join(out, f"{kind}-{suffix}.png"))
    specs = {"hide": 0, "maximize": 0, "maximize-toggled": 0, "close": 2,
             "shade": 0, "shade-toggled": 0, "stick": 0, "stick-toggled": 0}
    for kind, gap in specs.items():
        for state in ("active", "inactive", "prelight", "pressed"):
            retro_button(kind, state, state != "inactive", gap).save(os.path.join(out, f"{kind}-{state}.png"))
    # Menü-Button (Programm-Icon wird von xfwm4 darüber gezeichnet)
    for state in ("active", "inactive", "pressed"):
        img = Image.new("RGBA", (18, R_TH), (*(NAVY if state != "inactive" else GRAY), 255))
        d = ImageDraw.Draw(img)
        retro_top_rows(d, 18)
        img.save(os.path.join(out, f"menu-{state}.png"))
    print("  retro xfwm4 ok")


# ---------------------------------------------------------------------------
# Retro: Icons (16x16 und 32x32 Pixel-Sprites)
# ---------------------------------------------------------------------------
RETRO_SPRITES16 = {
    "win7-start": [
        "................",
        "..kkkkkkkkkkkk..",
        ".kwwwwwwkccccck.",
        ".kwnnnnwkcnnnck.",
        ".kwnnnnwkcnnnck.",
        ".kwnnnnwkcnnnck.",
        ".kwwwwwwkccccck.",
        ".kkkkkkkkkkkkkk.",
        ".kcccccckwwwwwk.",
        ".kcnnnnckwnnnwk.",
        ".kcnnnnckwnnnwk.",
        ".kcnnnnckwnnnwk.",
        ".kcccccckwwwwwk.",
        "..kkkkkkkkkkkk..",
        "................",
        "................",
    ],
    "computer": [
        "................",
        ".kkkkkkkkkkkkk..",
        ".kssssssssssssk.",
        ".ksknnnnnnnnksk.",
        ".kskncccnnnnksk.",
        ".ksknnnnnnnnksk.",
        ".ksknnnnnnnnksk.",
        ".kskkkkkkkkkksk.",
        ".kssssssssssssk.",
        ".kkkkkkkkkkkkkk.",
        "......kaak......",
        "....kkkaakkk....",
        "...kssssssssk...",
        "...kssklksssk...",
        "...kaaaaaaaak...",
        "...kkkkkkkkkk...",
    ],
    "user-trash": [
        "................",
        "......kkkk......",
        "....kkssssskk...",
        "...kssssssssssk.",
        "...kkkkkkkkkkkk.",
        "....kasasasask..",
        "....kasasasask..",
        "....kasasasask..",
        "....kasasasask..",
        "....kasasasask..",
        "....kasasasask..",
        ".....kasasask...",
        ".....kasasask...",
        ".....kasasask...",
        "......kkkkkk....",
        "................",
    ],
    "user-trash-full": [
        "......kkkk......",
        "..kwwwkssssskk..",
        ".kwkwkssssssssk.",
        ".kwwwkkkkkkkkkk.",
        ".kkkkkasasasask.",
        "....kasasasask..",
        "....kasasasask..",
        "....kasasasask..",
        "....kasasasask..",
        "....kasasasask..",
        "....kasasasask..",
        ".....kasasask...",
        ".....kasasask...",
        ".....kasasask...",
        "......kkkkkk....",
        "................",
    ],
    "network-workgroup": [
        "kkkkkkk.........",
        "kssssssk........",
        "kskccckk........",
        "kskccckk........",
        "kskkkkkk........",
        "kkkkkkkk..kkkkkk",
        "...k......kssssk",
        "...k......kskcck",
        "...kkkkkkkkskcck",
        "..........kskkkk",
        "..........kkkkkk",
        "...kkkkkkk......",
        "...kssssssk.....",
        "...kskccckk.....",
        "...kskccckk.....",
        "...kkkkkkkk.....",
    ],
    "win7-control-panel": [
        "kkkkkkkkkkkkkkkk",
        "kssssssssssssssk",
        "kskkkkkkkkkkkksk",
        "kskaaaawwaaaaksk",
        "kskkkkkwwkkkkksk",
        "kssssssssssssssk",
        "kskkkkkkkkkkkksk",
        "kskaaaaaaawwaksk",
        "kskkkkkkkkwwkksk",
        "kssssssssssssssk",
        "kskkkkkkkkkkkksk",
        "kskawwaaaaaaaksk",
        "kskkwwkkkkkkkksk",
        "kssssssssssssssk",
        "kkkkkkkkkkkkkkkk",
        "................",
    ],
    "win7-cmd": [
        "kkkkkkkkkkkkkkkk",
        "knnnnnnnnnnnnnnk",
        "kkkkkkkkkkkkkkkk",
        "kkkkkkkkkkkkkkkk",
        "kkswwkkkkkkkkkkk",
        "kkwkkkkkwkkkkkkk",
        "kkwkkkkkkkkkkkkk",
        "kkwkkkkkwkkkkkkk",
        "kkswwkkkkkkkkkkk",
        "kkkkkkkkkkkkkkkk",
        "kkkkkkkkkkkkkkkk",
        "kkkkkkwwwwkkkkkk",
        "kkkkkkkkkkkkkkkk",
        "kkkkkkkkkkkkkkkk",
        "kkkkkkkkkkkkkkkk",
        "kkkkkkkkkkkkkkkk",
    ],
    "folder": [
        "................",
        ".kkkkk..........",
        "koooookkkkkkkk..",
        "koyyyyyyyyyyyyk.",
        "koyyyyyyyyyyyyk.",
        "kkkkkkkkkkkkkkkk",
        "koyyyyyyyyyyyyyk",
        "koyyyyyyyyyyyyyk",
        "koyyyyyyyyyyyyyk",
        "koyyyyyyyyyyyyyk",
        "koyyyyyyyyyyyyyk",
        "koyyyyyyyyyyyyyk",
        "koyyyyyyyyyyyyyk",
        "koooooooooooooook",
        "kkkkkkkkkkkkkkkk",
        "................",
    ],
    "user-home": [
        "................",
        ".kkkkk..........",
        "koooookkkkkkkk..",
        "koyyyyyyyyyyyyk.",
        "koyyyykkkyyyyyk.",
        "kkkkkkknnkkkkkkk",
        "koyyyyknnnkyyyyk",
        "koyyyykwwwkyyyyk",
        "koyyyyykwkyyyyyk",
        "koyyyykkkkkyyyyk",
        "koyyykbbbbbkyyyk",
        "koyyykbbbbbkyyyk",
        "koyyykbbbbbkyyyk",
        "koooooooooooooook",
        "kkkkkkkkkkkkkkkk",
        "................",
    ],
    "web-browser": [
        "................",
        ".....kkkkkk.....",
        "...kkccccccckk..",
        "..kcccckkcccack.",
        ".kcccckggkccaack",
        ".kccckgggggkcack",
        "kcccckgggggkccck",
        "kcccckggggkcccck",
        "kccccckkkkcccack",
        "kcccccccccccaack",
        ".kccccckkkcaaak.",
        ".kccccckgkcaaak.",
        "..kcccckkcaaak..",
        "...kkccccaakk...",
        ".....kkkkkk.....",
        "................",
    ],
    "accessories-text-editor": [
        "................",
        ".kkkkkkkkkkk....",
        ".kwwwwwwwwwkk...",
        ".kwwwwwwwwwkwk..",
        ".kwwwwwwwwwkkkk.",
        ".kwkkkkkkwwwwwk.",
        ".kwwwwwwwwwwwwk.",
        ".kwkkkkkkkkkwwk.",
        ".kwwwwwwwwwwwwk.",
        ".kwkkkkkkkkwwwk.",
        ".kwwwwwwwwwwwwk.",
        ".kwkkkkkkkkkkwk.",
        ".kwwwwwwwwwwwwk.",
        ".kwkkkkkkwwwwwk.",
        ".kwwwwwwwwwwwwk.",
        ".kkkkkkkkkkkkkk.",
    ],
    "utilities-system-monitor": [
        "kkkkkkkkkkkkkkkk",
        "knnnnnnnnnnnnnnk",
        "kkkkkkkkkkkkkkkk",
        "kwwwwwwwwwwwwwwk",
        "kwwwwwwwwwwwwwwk",
        "kwwlwwwwwwwwwwwk",
        "kwwlwwwlwwwwwwwk",
        "kwlllwwlwwwlwwwk",
        "kwlllwllwwwlwwwk",
        "kllllwllwllllwwk",
        "kllllllllllllwlk",
        "kllllllllllllllk",
        "kwwwwwwwwwwwwwwk",
        "kkkkkkkkkkkkkkkk",
        "................",
        "................",
    ],
    "system-run": [
        "................",
        "kkkkkkkkkkkkkkkk",
        "knnnnnnnnnnnnnnk",
        "kkkkkkkkkkkkkkkk",
        "kssssssssssssssk",
        "kskkkkkkkkkkkksk",
        "kskwwwwwwwwwwksk",
        "kskwkwkwwwwwwksk",
        "kskwwwwwwwwwwksk",
        "kskkkkkkkkkkkksk",
        "kssssssssssssssk",
        "kssskkkkkkksssak",
        "kssskssssskssaak",
        "kssskkkkkkksaaak",
        "kkkkkkkkkkkkkkkk",
        "................",
    ],
}

RETRO_SPRITES32 = {}


def _draw32(name, fn):
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    fn(img, d)
    RETRO_SPRITES32[name] = img
    return img


def _s32_start(img, d):
    rect(d, 2, 3, 29, 28, fill=BLACK)
    for (x0, y0, c) in ((4, 5, WHITE), (17, 5, VGA["c"]), (4, 17, VGA["c"]), (17, 17, WHITE)):
        rect(d, x0, y0, x0 + 10, y0 + 9, fill=c)
        rect(d, x0 + 2, y0 + 2, x0 + 8, y0 + 7, fill=NAVY)


def _s32_computer(img, d):
    rect(d, 2, 2, 29, 21, fill=SILVER, outline=BLACK)
    rect(d, 4, 4, 27, 19, fill=NAVY, outline=BLACK)
    rect(d, 6, 6, 25, 17, fill=NAVY)
    d.line([7, 7, 12, 7], fill=VGA["c"])
    d.line([7, 9, 18, 9], fill=VGA["c"])
    d.line([7, 11, 10, 11], fill=VGA["c"])
    rect(d, 13, 22, 18, 24, fill=GRAY, outline=BLACK)
    rect(d, 6, 25, 25, 29, fill=SILVER, outline=BLACK)
    rect(d, 20, 26, 23, 27, fill=VGA["l"])
    d.line([8, 27, 17, 27], fill=GRAY)


def _s32_trash(img, d, full=False):
    rect(d, 12, 2, 19, 4, fill=SILVER, outline=BLACK)
    rect(d, 6, 5, 25, 7, fill=SILVER, outline=BLACK)
    d.polygon([(7, 8), (24, 8), (22, 29), (9, 29)], fill=SILVER, outline=BLACK)
    for x in range(10, 22, 3):
        d.line([x, 10, x - 1, 27], fill=GRAY)
    if full:
        rect(d, 4, 0, 13, 9, fill=WHITE, outline=BLACK)
        d.line([6, 3, 11, 3], fill=NAVY); d.line([6, 5, 11, 5], fill=NAVY); d.line([6, 7, 9, 7], fill=NAVY)
        rect(d, 19, 1, 28, 8, fill=WHITE, outline=BLACK)
        d.line([21, 3, 26, 3], fill=NAVY); d.line([21, 5, 26, 5], fill=NAVY)


def _s32_network(img, d):
    for (x, y) in ((1, 1), (17, 15)):
        rect(d, x, y, x + 13, y + 10, fill=SILVER, outline=BLACK)
        rect(d, x + 2, y + 2, x + 11, y + 8, fill=VGA["c"], outline=BLACK)
        rect(d, x + 5, y + 11, x + 8, y + 12, fill=GRAY)
        rect(d, x + 3, y + 13, x + 10, y + 13, fill=BLACK)
    d.line([8, 15, 8, 20], fill=BLACK); d.line([8, 20, 24, 20], fill=BLACK); d.line([24, 20, 24, 15], fill=BLACK)
    rect(d, 14, 18, 18, 22, fill=VGA["l"], outline=BLACK)


def _s32_control(img, d):
    rect(d, 1, 3, 30, 28, fill=SILVER, outline=BLACK)
    d.line([2, 4, 29, 4], fill=WHITE)
    for i, pos in enumerate((0.25, 0.7, 0.45)):
        y = 9 + i * 7
        bevel_sunken(d, 5, y - 1, 26, y + 1, fill=GRAY)
        kx = 5 + int(pos * 20)
        bevel_raised(d, kx - 2, y - 3, kx + 2, y + 3, inner_light=LIGHT)


def _s32_cmd(img, d):
    rect(d, 1, 1, 30, 30, fill=BLACK, outline=SILVER)
    rect(d, 2, 2, 29, 5, fill=NAVY)
    d.line([3, 3, 8, 3], fill=WHITE)
    rect(d, 26, 3, 28, 4, fill=SILVER)
    # "C:\>" in Pixeln
    px = img.load()
    glyph = [
        "..ww.............",
        ".w..w............",
        "w......ww..w.....",
        "w......ww...w....",
        "w............w...",
        "w......ww.....w..",
        ".w..w..ww....w...",
        "..ww........w....",
    ]
    for yy, row in enumerate(glyph):
        for xx, ch in enumerate(row):
            if ch == "w":
                px[4 + xx, 9 + yy] = (*SILVER, 255)
    rect(d, 5, 21, 10, 22, fill=SILVER)


def _s32_folder(img, d, person=False):
    rect(d, 1, 4, 12, 7, fill=VGA["o"], outline=BLACK)
    rect(d, 1, 7, 30, 28, fill=VGA["y"], outline=BLACK)
    rect(d, 2, 8, 29, 11, fill=VGA["o"])
    d.line([1, 11, 30, 11], fill=BLACK)
    rect(d, 3, 13, 28, 26, fill=VGA["y"])
    d.line([2, 27, 29, 27], fill=VGA["o"])
    if person:
        rect(d, 13, 13, 18, 18, fill=NAVY, outline=BLACK)
        rect(d, 14, 15, 17, 16, fill=WHITE)
        rect(d, 10, 19, 21, 25, fill=VGA["b"], outline=BLACK)


def _s32_globe(img, d):
    d.ellipse([2, 2, 29, 29], fill=VGA["c"], outline=BLACK)
    for pts in ([(8, 8), (14, 6), (18, 10), (14, 15), (8, 13)], [(17, 17), (24, 15), (26, 21), (21, 25), (16, 22)], [(5, 19), (10, 18), (11, 23), (6, 24)]):
        d.polygon(pts, fill=VGA["g"], outline=BLACK)
    d.ellipse([2, 2, 29, 29], outline=BLACK)
    d.line([3, 15, 28, 15], fill=BLACK)
    d.arc([8, 2, 23, 29], 0, 360, fill=BLACK)


def _s32_notepad(img, d):
    rect(d, 4, 1, 25, 30, fill=WHITE, outline=BLACK)
    d.polygon([(21, 1), (25, 5), (21, 5)], fill=SILVER, outline=BLACK)
    for i, ln in enumerate((12, 16, 9, 15, 14, 11)):
        d.line([7, 8 + i * 3, 7 + ln, 8 + i * 3], fill=BLACK)


def _s32_taskmgr(img, d):
    rect(d, 1, 2, 30, 29, fill=SILVER, outline=BLACK)
    rect(d, 2, 3, 29, 6, fill=NAVY)
    bevel_sunken(d, 4, 9, 27, 26, fill=BLACK)
    for i, h in enumerate((5, 9, 7, 12, 10, 14, 11, 8, 13, 6)):
        rect(d, 7 + i * 2, 24 - h, 7 + i * 2, 24, fill=VGA["l"])


def _s32_run(img, d):
    rect(d, 1, 3, 30, 27, fill=SILVER, outline=BLACK)
    rect(d, 2, 4, 29, 7, fill=NAVY)
    bevel_sunken(d, 4, 11, 27, 17, fill=WHITE)
    d.line([7, 13, 7, 15], fill=BLACK); d.line([9, 13, 11, 13], fill=BLACK)
    bevel_raised(d, 12, 20, 27, 25, inner_light=LIGHT)
    d.line([15, 22, 24, 22], fill=BLACK); d.line([15, 23, 24, 23], fill=BLACK)


def build_sprites32():
    _draw32("win7-start", _s32_start)
    _draw32("computer", _s32_computer)
    _draw32("user-trash", lambda i, d: _s32_trash(i, d, False))
    _draw32("user-trash-full", lambda i, d: _s32_trash(i, d, True))
    _draw32("network-workgroup", _s32_network)
    _draw32("win7-control-panel", _s32_control)
    _draw32("win7-cmd", _s32_cmd)
    _draw32("folder", lambda i, d: _s32_folder(i, d, False))
    _draw32("user-home", lambda i, d: _s32_folder(i, d, True))
    _draw32("web-browser", _s32_globe)
    _draw32("accessories-text-editor", _s32_notepad)
    _draw32("utilities-system-monitor", _s32_taskmgr)
    _draw32("system-run", _s32_run)


RETRO_ICON_MAP = {
    # Icon-Name → (Kontexte, 16er-Sprite, 32er-Sprite)
    "win7-start": (("apps",), "win7-start", "win7-start"),
    "distributor-logo": (("apps",), "win7-start", "win7-start"),
    "start-here": (("apps",), "win7-start", "win7-start"),
    "computer": (("devices", "places"), "computer", "computer"),
    "drive-harddisk": (("devices",), "computer", "computer"),
    "user-trash": (("places",), "user-trash", "user-trash"),
    "user-trash-full": (("places",), "user-trash-full", "user-trash-full"),
    "network-workgroup": (("places",), "network-workgroup", "network-workgroup"),
    "network-server": (("places",), "network-workgroup", "network-workgroup"),
    "preferences-desktop": (("apps",), "win7-control-panel", "win7-control-panel"),
    "xfce4-settings-manager": (("apps",), "win7-control-panel", "win7-control-panel"),
    "win7-control-panel": (("apps",), "win7-control-panel", "win7-control-panel"),
    "win7-cmd": (("apps",), "win7-cmd", "win7-cmd"),
    "utilities-terminal": (("apps",), "win7-cmd", "win7-cmd"),
    "xfce-terminal": (("apps",), "win7-cmd", "win7-cmd"),
    "win7-explorer": (("apps",), "folder", "folder"),
    "system-file-manager": (("apps",), "folder", "folder"),
    "folder": (("places",), "folder", "folder"),
    "inode-directory": (("mimetypes",), "folder", "folder"),
    "user-home": (("places",), "user-home", "user-home"),
    "web-browser": (("apps", "categories"), "web-browser", "web-browser"),
    "applications-internet": (("categories",), "web-browser", "web-browser"),
    "accessories-text-editor": (("apps",), "accessories-text-editor", "accessories-text-editor"),
    "utilities-system-monitor": (("apps",), "utilities-system-monitor", "utilities-system-monitor"),
    "system-run": (("apps", "actions"), "system-run", "system-run"),
}
ICON_SIZES = (16, 22, 24, 32, 48, 64, 96, 128, 256)


def retro_icon_at(name16, name32, size):
    s16 = sprite(RETRO_SPRITES16[name16])
    s32 = RETRO_SPRITES32[name32]
    if size == 16:
        return s16
    if size in (22, 24):
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        img.alpha_composite(s16, ((size - 16) // 2, (size - 16) // 2))
        return img
    if size == 48:
        return upscale(s16, 3)
    return upscale(s32, size // 32)


def retro_gen_icons(out, theme_name="Windows-Retro"):
    build_sprites32()
    base = ensure(out)
    dirs = set()
    for name, (ctxs, n16, n32) in RETRO_ICON_MAP.items():
        for size in ICON_SIZES:
            img = retro_icon_at(n16, n32, size)
            for ctx in ctxs:
                d = ensure(os.path.join(base, f"{size}x{size}", ctx))
                img.save(os.path.join(d, f"{name}.png"))
                dirs.add(f"{size}x{size}/{ctx}")
    ctx_names = {"apps": "Applications", "devices": "Devices", "places": "Places", "categories": "Categories", "actions": "Actions", "mimetypes": "MimeTypes"}
    dirs = sorted(dirs, key=lambda s: (int(s.split("x")[0]), s))
    lines = ["[Icon Theme]", f"Name={theme_name}", "Comment=Pixel-Icons im Windows-95-Stil für TheWindowsLinux (Original-Artwork)",
             "Inherits=elementary-xfce,Adwaita,gnome,hicolor", "Directories=" + ",".join(dirs), ""]
    for d in dirs:
        s = int(d.split("x")[0]); ctx = d.split("/")[1]
        lines += [f"[{d}]", f"Size={s}", f"Context={ctx_names[ctx]}", "Type=Fixed", ""]
    with open(os.path.join(base, "index.theme"), "w") as fh:
        fh.write("\n".join(lines))
    print("  retro icons ok")


# ---------------------------------------------------------------------------
# Retro: GTK-Assets (Dither, Pfeile, Häkchen)
# ---------------------------------------------------------------------------
def retro_gen_gtk_assets(out):
    ensure(out)
    d = Image.new("RGBA", (2, 2))
    px = d.load()
    px[0, 0] = (*WHITE, 255); px[1, 1] = (*WHITE, 255); px[1, 0] = (*SILVER, 255); px[0, 1] = (*SILVER, 255)
    d.save(os.path.join(out, "dither.png"))
    d2 = Image.new("RGBA", (2, 2))
    px = d2.load()
    px[0, 0] = (*NAVY, 255); px[1, 1] = (*NAVY, 255); px[1, 0] = (*SILVER, 255); px[0, 1] = (*SILVER, 255)
    d2.save(os.path.join(out, "dither-navy.png"))
    arrows = {
        "arrow-up":    ["...k...", "..kkk..", ".kkkkk.", "kkkkkkk"],
        "arrow-down":  ["kkkkkkk", ".kkkkk.", "..kkk..", "...k..."],
        "arrow-left":  ["...k", "..kk", ".kkk", "kkkk", ".kkk", "..kk", "...k"],
        "arrow-right": ["k...", "kk..", "kkk.", "kkkk", "kkk.", "kk..", "k..."],
    }
    for name, rows in arrows.items():
        s = sprite(rows)
        canvas = Image.new("RGBA", (9, 9), (0, 0, 0, 0))
        canvas.alpha_composite(s, ((9 - s.width) // 2, (9 - s.height) // 2))
        canvas.save(os.path.join(out, f"{name}.png"))
        # ausgegraut
        g = sprite([r.replace("k", "a") for r in rows])
        canvas = Image.new("RGBA", (9, 9), (0, 0, 0, 0))
        canvas.alpha_composite(g, ((9 - g.width) // 2, (9 - g.height) // 2))
        canvas.save(os.path.join(out, f"{name}-disabled.png"))
    sprite(["......k", ".....kk", "....kkk", "k..kkk.", "kkkkk..", ".kkk...", "..k...."]).save(os.path.join(out, "check.png"))
    sprite([".kk.", "kkkk", "kkkk", ".kk."]).save(os.path.join(out, "radio.png"))
    sprite(["kkkkkkkkk", "k.......k", "k.kkkkk.k", "k.k...k.k", "k.k...k.k", "k.k...k.k", "k.kkkkk.k", "k.......k", "kkkkkkkkk"]).save(os.path.join(out, "grip.png"))
    # Fenster-Schaltflächen für CSD-Headerbars (16x14 wie xfwm4)
    for kind in ("hide", "maximize", "restore", "close"):
        img = Image.new("RGBA", (16, 14), (0, 0, 0, 0))
        dd = ImageDraw.Draw(img)
        bevel_raised(dd, 0, 0, 15, 13, inner_light=LIGHT)
        retro_glyph(dd, kind, 0, 0)
        img.save(os.path.join(out, f"titlebutton-{kind}.png"))
    print("  retro gtk assets ok")


# ---------------------------------------------------------------------------
# Retro: Mauszeiger (Xcursor-Theme via xcursorgen)
# ---------------------------------------------------------------------------
CURSOR_SPRITES = {
    "left_ptr": (0, 0, [
        "k...............",
        "kk..............",
        "kwk.............",
        "kwwk............",
        "kwwwk...........",
        "kwwwwk..........",
        "kwwwwwk.........",
        "kwwwwwwk........",
        "kwwwwwwwk.......",
        "kwwwwwwwwk......",
        "kwwwwwkkkkk.....",
        "kwwkwwk.........",
        "kwk.kwwk........",
        "kk...kwwk.......",
        "k.....kwwk......",
        ".......kk.......",
    ]),
    "hand2": (5, 0, [
        ".....kk.........",
        "....kwwk........",
        "....kwwk........",
        "....kwwk........",
        "....kwwkkk......",
        "....kwwkwwkkk...",
        "....kwwkwwkwwkk.",
        "kkk.kwwkwwkwwkwk",
        "kwwkkwwwwwwwwwwk",
        "kwwwkwwwwwwwwwwk",
        ".kwwwwwwwwwwwwwk",
        ".kwwwwwwwwwwwwk.",
        "..kwwwwwwwwwwwk.",
        "..kwwwwwwwwwwk..",
        "...kwwwwwwwwwk..",
        "...kkkkkkkkkkk..",
    ]),
    "xterm": (7, 7, [
        "kkkkk.kkkkk.....",
        "kwwwwkwwwwk.....",
        "kkkkkwkkkkk.....",
        ".....kwk........",
        ".....kwk........",
        ".....kwk........",
        ".....kwk........",
        ".....kwk........",
        ".....kwk........",
        ".....kwk........",
        ".....kwk........",
        ".....kwk........",
        ".....kwk........",
        "kkkkkwkkkkk.....",
        "kwwwwkwwwwk.....",
        "kkkkk.kkkkk.....",
    ]),
    "watch": (7, 7, [
        "kkkkkkkkkkkkkkk.",
        "kwwwwwwwwwwwwwk.",
        "kkkkkkkkkkkkkkk.",
        ".kwkkkkkkkkkwk..",
        ".kwwkkkkkkkwwk..",
        "..kwwwkkkwwwk...",
        "...kwwwkwwwk....",
        "....kwwwwwk.....",
        "....kwwkwwk.....",
        "...kwwkkkwwk....",
        "..kwwkkkkkwwk...",
        ".kwwkkkkkkkwwk..",
        ".kwkkkkkkkkkwk..",
        "kkkkkkkkkkkkkkk.",
        "kwwwwwwwwwwwwwk.",
        "kkkkkkkkkkkkkkk.",
    ]),
    "fleur": (7, 7, [
        ".......k........",
        "......kwk.......",
        ".....kwwwk......",
        "....kwwwwwk.....",
        ".....kkwkk......",
        "..kk...k...kk...",
        ".kwk...k...kwk..",
        "kwwkkkkkkkkkwwk.",
        ".kwk...k...kwk..",
        "..kk...k...kk...",
        ".....kkwkk......",
        "....kwwwwwk.....",
        ".....kwwwk......",
        "......kwk.......",
        ".......k........",
        "................",
    ]),
    "sb_h_double_arrow": (7, 3, [
        "..kk.......kk...",
        ".kwk.......kwk..",
        "kwwkkkkkkkkkwwk.",
        "kwwwwwwwwwwwwwwk",
        "kwwkkkkkkkkkwwk.",
        ".kwk.......kwk..",
        "..kk.......kk...",
    ]),
    "sb_v_double_arrow": (3, 7, [
        "...k....",
        "..kwk...",
        ".kwwwk..",
        "kwwwwwk.",
        "kkkwkkk.",
        "..kwk...",
        "..kwk...",
        "..kwk...",
        "..kwk...",
        "..kwk...",
        "kkkwkkk.",
        "kwwwwwk.",
        ".kwwwk..",
        "..kwk...",
        "...k....",
    ]),
    "bd_double_arrow": (6, 6, [
        "kkkkkkk......",
        "kwwwwwk......",
        "kwwwwk.......",
        "kwwwwwk......",
        "kwwkwwwk.....",
        "kwk.kwwwk....",
        "kk...kwwwk.kk",
        "......kwwwkwk",
        ".......kwwwwk",
        "........kwwwk",
        ".......kwwwwk",
        "......kwwwwwk",
        "......kkkkkkk",
    ]),
    "fd_double_arrow": (6, 6, [
        "......kkkkkkk",
        "......kwwwwwk",
        ".......kwwwwk",
        "......kwwwwwk",
        ".....kwwwkwwk",
        "....kwwwk.kwk",
        "kk.kwwwk...kk",
        "kwkwwwk......",
        "kwwwwk.......",
        "kwwwk........",
        "kwwwwk.......",
        "kwwwwwk......",
        "kkkkkkk......",
    ]),
    "crosshair": (7, 7, [
        ".......k........",
        "......kwk.......",
        "......kwk.......",
        "......kwk.......",
        "......kwk.......",
        "......kwk.......",
        "kkkkkkkkkkkkkkk.",
        "kwwwwwk.kwwwwwk.",
        "kkkkkkkkkkkkkkk.",
        "......kwk.......",
        "......kwk.......",
        "......kwk.......",
        "......kwk.......",
        "......kwk.......",
        ".......k........",
        "................",
    ]),
}
CURSOR_ALIASES = {
    "left_ptr": ["default", "arrow", "top_left_arrow", "left-ptr", "dnd-none", "copy", "dnd-copy", "alias", "dnd-link", "link", "context-menu", "right_ptr", "not-allowed", "crossed_circle", "forbidden", "no-drop", "dnd-move", "pencil", "zoom-in", "zoom-out", "cell", "vertical-text", "color-picker"],
    "hand2": ["pointer", "hand", "hand1", "pointing_hand", "openhand", "grab", "grabbing", "closedhand", "dnd-ask"],
    "xterm": ["text", "ibeam"],
    "watch": ["wait", "progress", "left_ptr_watch", "half-busy"],
    "fleur": ["move", "all-scroll", "size_all", "all_scroll"],
    "sb_h_double_arrow": ["col-resize", "ew-resize", "h_double_arrow", "left_side", "right_side", "e-resize", "w-resize", "size_hor", "split_h"],
    "sb_v_double_arrow": ["row-resize", "ns-resize", "v_double_arrow", "top_side", "bottom_side", "n-resize", "s-resize", "size_ver", "split_v"],
    "bd_double_arrow": ["nwse-resize", "size_fdiag", "top_left_corner", "bottom_right_corner", "nw-resize", "se-resize"],
    "fd_double_arrow": ["nesw-resize", "size_bdiag", "top_right_corner", "bottom_left_corner", "ne-resize", "sw-resize"],
    "crosshair": ["cross", "tcross", "cross_reverse", "diamond_cross", "plus"],
}


def retro_gen_cursors(out, theme_name="Windows-Retro"):
    """Xcursor-Theme: 16px-Sprites in 2x (32px) und 3x (48px); benötigt xcursorgen."""
    if shutil.which("xcursorgen") is None:
        print("  cursors übersprungen (xcursorgen fehlt)")
        return
    cdir = ensure(os.path.join(out, "cursors"))
    tmp = ensure(os.path.join(out, ".build"))
    for name, (hx, hy, rows) in CURSOR_SPRITES.items():
        cfg = os.path.join(tmp, name + ".cfg")
        with open(cfg, "w") as fh:
            for scale in (2, 3):
                img = sprite(rows, scale)
                png = os.path.join(tmp, f"{name}-{scale}.png")
                img.save(png)
                fh.write(f"{16 * scale} {hx * scale} {hy * scale} {png}\n")
        subprocess.run(["xcursorgen", cfg, os.path.join(cdir, name)], check=True)
        for alias in CURSOR_ALIASES.get(name, []):
            dst = os.path.join(cdir, alias)
            if os.path.lexists(dst):
                os.remove(dst)
            os.symlink(name, dst)
    shutil.rmtree(tmp)
    # index.theme stammt vom Icon-Theme (gleicher Ordner); Xcursor nutzt dessen Inherits (… Adwaita).
    with open(os.path.join(out, "cursor.theme"), "w") as fh:
        fh.write(f"[Icon Theme]\nName={theme_name}\nInherits={theme_name}\n")
    print("  retro cursors ok")


# ---------------------------------------------------------------------------
# Retro: Sounds (Rechteckwellen, 8-Bit-Quantisierung, 11 kHz)
# ---------------------------------------------------------------------------
R_SR = 11025


def square(freq, dur, vol=0.4, decay=0.25, duty=0.5):
    t = np.arange(int(R_SR * dur)) / R_SR
    phase = (t * freq) % 1.0
    sig = np.where(phase < duty, 1.0, -1.0)
    env = np.exp(-t / decay)
    return vol * sig * env


def r_mix(events, total):
    out = np.zeros(int(R_SR * total))
    for start, sig in events:
        i = int(start * R_SR)
        n = min(len(sig), len(out) - i)
        if n > 0:
            out[i:i + n] += sig[:n]
    out = np.clip(out, -1, 1)
    return np.round(out * 127) / 127  # 8-Bit-Stufen


def write_wav(path, data, sr):
    data = np.clip(data, -1, 1)
    pcm = (data * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def retro_gen_sounds(out):
    if np is None:
        print("  sounds übersprungen (numpy fehlt)"); return
    ensure(out)
    C, E, G, C2, E2, G2 = 261.63, 329.63, 392.0, 523.25, 659.25, 783.99
    write_wav(os.path.join(out, "logon.wav"), r_mix([(0.0, square(C, 0.5)), (0.15, square(E, 0.5)), (0.30, square(G, 0.5)), (0.45, square(C2, 0.9, decay=0.4))], 1.6), R_SR)
    write_wav(os.path.join(out, "startup.wav"), r_mix([(0.0, square(C, 0.4)), (0.2, square(G, 0.4)), (0.4, square(E2, 0.4)), (0.6, square(C2, 0.4)), (0.8, square(G2, 0.6)), (1.0, square(C2, 1.2, decay=0.5)), (1.0, square(E2, 1.2, 0.2, decay=0.5))], 2.6), R_SR)
    write_wav(os.path.join(out, "logoff.wav"), r_mix([(0.0, square(G2, 0.4)), (0.18, square(E2, 0.4)), (0.36, square(C2, 0.4)), (0.54, square(G, 0.8, decay=0.4))], 1.5), R_SR)
    write_wav(os.path.join(out, "notify.wav"), r_mix([(0.0, square(E2, 0.25, decay=0.12)), (0.12, square(G2, 0.35, decay=0.15))], 0.6), R_SR)
    write_wav(os.path.join(out, "error.wav"), r_mix([(0.0, square(110, 0.25, 0.5, decay=0.2, duty=0.25)), (0.25, square(98, 0.4, 0.5, decay=0.25, duty=0.25))], 0.8), R_SR)
    write_wav(os.path.join(out, "ding.wav"), r_mix([(0.0, square(C2, 0.4, decay=0.2))], 0.5), R_SR)
    print("  retro sounds ok")


# ---------------------------------------------------------------------------
# Retro: Vorschau (640x400 → 2x = 1280x800)
# ---------------------------------------------------------------------------
def retro_window(img, x, y, w, h, title, active=True, icon=None, fnt=None):
    """Pixelgenaues Win95-Fenster auf img zeichnen; gibt Client-Box zurück."""
    d = ImageDraw.Draw(img)
    rect(d, x, y, x + w - 1, y + h - 1, fill=SILVER)
    d.line([x, y, x + w - 2, y], fill=SILVER); d.line([x, y, x, y + h - 2], fill=SILVER)
    d.line([x + 1, y + 1, x + w - 3, y + 1], fill=WHITE); d.line([x + 1, y + 1, x + 1, y + h - 3], fill=WHITE)
    d.line([x, y + h - 1, x + w - 1, y + h - 1], fill=BLACK); d.line([x + w - 1, y, x + w - 1, y + h - 1], fill=BLACK)
    d.line([x + 1, y + h - 2, x + w - 2, y + h - 2], fill=GRAY); d.line([x + w - 2, y + 1, x + w - 2, y + h - 2], fill=GRAY)
    tb = NAVY if active else GRAY
    rect(d, x + 4, y + 4, x + w - 5, y + 4 + R_TITLE - 1, fill=tb)
    if icon is not None:
        img.alpha_composite(icon, (x + 6, y + 5))
    pixel_text(img, (x + 24, y + 5), title, WHITE if active else SILVER, fnt=fnt)
    bx = x + w - 5 - 2 - 16
    for kind, gap in (("close", 2), ("maximize", 0), ("hide", 0)):
        b = retro_button(kind, "active", active, 0).crop((0, R_FRAME, 16, R_TH))
        img.alpha_composite(b, (bx, y + 4))
        bx -= 16 + gap
    return (x + 4, y + 4 + R_TITLE, x + w - 5, y + h - 5)


def retro_gen_preview(style_dir):
    W, H = 640, 400
    build_sprites32()
    img = retro_wallpaper(W, H, logo=True)
    fnt = pixel_font(16)
    fnt_small = pixel_font(16)
    # Desktop-Icons
    icons = [("Computer", "computer"), ("Eigene Dateien", "user-home"), ("Netzwerk", "network-workgroup"), ("Papierkorb", "user-trash")]
    for i, (label, name) in enumerate(icons):
        s = RETRO_SPRITES32[name]
        x, y = 40, 10 + i * 64
        img.alpha_composite(s, (x + 14, y))
        tw = fnt.getmask(label, mode="1").size[0]
        pixel_text(img, (x + 30 - tw // 2, y + 34), label, WHITE, fnt=fnt)

    # Explorer-Fenster
    cx0, cy0, cx1, cy1 = retro_window(img, 100, 30, 400, 250, "Eigene Dateien", active=False, icon=sprite(RETRO_SPRITES16["folder"]), fnt=fnt)
    d = ImageDraw.Draw(img)
    rect(d, cx0, cy0, cx1, cy0 + 14, fill=SILVER)
    mx = cx0 + 6
    for m in ("Datei", "Bearbeiten", "Ansicht", "Hilfe"):
        pixel_text(img, (mx, cy0 + 1), m, BLACK, fnt=fnt)
        mx += fnt.getmask(m, mode="1").size[0] + 12
    d = ImageDraw.Draw(img)
    bevel_sunken(d, cx0, cy0 + 15, cx1, cy1 - 18, fill=WHITE)
    names = ("Bilder", "Dokumente", "Downloads", "Musik", "Videos", "Spiele")
    for i, n in enumerate(names):
        fx = cx0 + 16 + (i % 4) * 90
        fy = cy0 + 24 + (i // 4) * 70
        img.alpha_composite(RETRO_SPRITES32["folder"], (fx + 14, fy))
        tw = fnt.getmask(n, mode="1").size[0]
        if i == 1:
            d = ImageDraw.Draw(img)
            rect(d, fx + 30 - tw // 2 - 2, fy + 34, fx + 30 + tw // 2 + 1, fy + 50, fill=NAVY)
            pixel_text(img, (fx + 30 - tw // 2, fy + 34), n, WHITE, fnt=fnt)
        else:
            pixel_text(img, (fx + 30 - tw // 2, fy + 34), n, BLACK, fnt=fnt)
    d = ImageDraw.Draw(img)
    bevel_sunken(d, cx0, cy1 - 16, cx1, cy1, fill=SILVER)
    pixel_text(img, (cx0 + 4, cy1 - 15), "6 Objekt(e)", BLACK, fnt=fnt)

    # Eingabeaufforderung
    cx0, cy0, cx1, cy1 = retro_window(img, 250, 150, 370, 200, "Eingabeaufforderung", active=True, icon=sprite(RETRO_SPRITES16["win7-cmd"]), fnt=fnt)
    d = ImageDraw.Draw(img)
    rect(d, cx0, cy0, cx1, cy1, fill=BLACK)
    lines = ["TheWindowsLinux [Version 4.10.2222]", "(c) 2026 TheWindowsLinux.", "", "C:\\Users\\user>dir /w", " Verzeichnis von C:\\Users\\user", "",
             "[Desktop]    [Dokumente]  [Downloads]", "notizen.txt  spiel.exe", "       2 Datei(en)      1.204 Bytes", "", "C:\\Users\\user>_"]
    for i, ln in enumerate(lines):
        pixel_text(img, (cx0 + 3, cy0 + 2 + i * 16), ln, SILVER, fnt=fnt)

    # Taskleiste
    TB = 28
    d = ImageDraw.Draw(img)
    rect(d, 0, H - TB, W - 1, H - 1, fill=SILVER)
    d.line([0, H - TB, W - 1, H - TB], fill=SILVER)
    d.line([0, H - TB + 1, W - 1, H - TB + 1], fill=WHITE)
    bevel_raised(d, 2, H - TB + 3, 68, H - 3, inner_light=LIGHT)
    img.alpha_composite(sprite(RETRO_SPRITES16["win7-start"]), (5, H - TB + 6))
    pixel_text(img, (25, H - TB + 6), "Start", BLACK, fnt=fnt)
    d = ImageDraw.Draw(img)
    d.line([72, H - TB + 3, 72, H - 3], fill=GRAY); d.line([73, H - TB + 3, 73, H - 3], fill=WHITE)
    x = 78
    for label, icon, active in (("Eigene Dateien", "folder", False), ("Eingabeaufforderung", "win7-cmd", True)):
        bw = 150
        if active:
            bevel_sunken(d, x, H - TB + 3, x + bw, H - 3, fill=SILVER)
            dither_fill(img, (x + 2, H - TB + 5, x + bw - 2, H - 5), WHITE, SILVER)
        else:
            bevel_raised(d, x, H - TB + 3, x + bw, H - 3, inner_light=LIGHT)
        img.alpha_composite(sprite(RETRO_SPRITES16[icon]), (x + 4 + (1 if active else 0), H - TB + 6 + (1 if active else 0)))
        pixel_text(img, (x + 24 + (1 if active else 0), H - TB + 6 + (1 if active else 0)), label, BLACK, fnt=fnt)
        d = ImageDraw.Draw(img)
        x += bw + 4
    bevel_sunken(d, W - 96, H - TB + 3, W - 3, H - 3, fill=SILVER)
    img.alpha_composite(sprite(["....", ".kk.", "kkkk", "kkkk"]), (W - 90, H - TB + 11))
    img.alpha_composite(sprite(["...k", "..kk", "kkkk", "kkkk"]), (W - 80, H - TB + 11))
    pixel_text(img, (W - 50, H - TB + 6), "09:41", BLACK, fnt=fnt)

    ensure(os.path.join(ROOT, "docs"))
    upscale(img, 2).convert("RGB").save(os.path.join(ROOT, "docs", "preview-retro.png"), optimize=True)
    print("  retro preview ok")


# ===========================================================================
#  AERO  (Windows-7-artig)
# ===========================================================================
AERO = {
    "active_top": (205, 226, 247), "active_mid": (125, 175, 228), "active_bottom": (150, 192, 236), "active_border": (46, 82, 125),
    "inactive_top": (232, 238, 245), "inactive_mid": (196, 208, 222), "inactive_bottom": (206, 216, 228), "inactive_border": (118, 132, 150),
    "close_top": (241, 157, 136), "close_bottom": (199, 44, 24), "close_press_top": (203, 92, 72), "close_press_bottom": (140, 18, 8),
    "hover_top": (210, 232, 250), "hover_bottom": (120, 175, 235), "press_top": (150, 185, 225), "press_bottom": (60, 115, 185),
}
TITLE_H = 30
SIDE_W = 6
BOTTOM_H = 6
CORNER = 8
BTN_H = 20
BTN_W_SMALL = 27
BTN_W_CLOSE = 45
FRAME_ALPHA = 232


def draw_emblem(draw, cx, cy, r, glow=True):
    if glow:
        for i in range(6, 0, -1):
            a = int(18 * (7 - i) / 6)
            draw.ellipse([cx - r * (1 + i * 0.25), cy - r * (1 + i * 0.25), cx + r * (1 + i * 0.25), cy + r * (1 + i * 0.25)], fill=(140, 200, 255, a))
    gap = r * 0.12
    pane = r * 0.78
    colors = [(120, 190, 250), (160, 225, 255), (90, 160, 235), (200, 240, 255)]
    rects = [(cx - pane - gap / 2, cy - pane - gap / 2, cx - gap / 2, cy - gap / 2), (cx + gap / 2, cy - pane - gap / 2, cx + pane + gap / 2, cy - gap / 2),
             (cx - pane - gap / 2, cy + gap / 2, cx - gap / 2, cy + pane + gap / 2), (cx + gap / 2, cy + gap / 2, cx + pane + gap / 2, cy + pane + gap / 2)]
    for rc, col in zip(rects, colors):
        draw.rounded_rectangle(rc, radius=r * 0.18, fill=(*col, 235), outline=(255, 255, 255, 90), width=max(1, int(r * 0.03)))


def aero_wallpaper(w=1920, h=1080, dark=False):
    sw, sh = w // 2, h // 2
    img = Image.new("RGBA", (sw, sh))
    px = img.load()
    cx, cy = sw * 0.5, sh * 0.52
    maxd = math.hypot(sw, sh) * 0.5
    c_center = (62, 140, 215) if not dark else (28, 70, 125)
    c_edge = (10, 38, 92) if not dark else (4, 16, 44)
    for y in range(sh):
        for x in range(sw):
            dd = math.hypot(x - cx, (y - cy) * 1.25) / maxd
            px[x, y] = (*lerp(c_center, c_edge, min(1.0, dd ** 1.15)), 255)
    overlay = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for (x0, y0, x1, y1, a0, a1, width) in ((0.10, 0.55, 1.10, 1.40, 200, 330, 7), (0.25, 0.70, 1.30, 1.60, 190, 320, 10), (-0.30, 0.20, 0.90, 1.30, 300, 400, 6), (0.05, -0.35, 1.15, 0.95, 60, 170, 8), (0.40, -0.10, 1.70, 1.10, 100, 200, 5)):
        od.arc([x0 * sw, y0 * sh, x1 * sw, y1 * sh], start=a0, end=a1, fill=(190, 230, 255, 120), width=width)
    img = Image.alpha_composite(img, overlay.filter(ImageFilter.GaussianBlur(radius=6)))
    glow = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(14, 0, -1):
        rr = sw * 0.045 * i
        gd.ellipse([cx - rr, cy - rr * 0.7, cx + rr, cy + rr * 0.7], fill=(150, 205, 255, 7))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(radius=25)))
    emb = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw_emblem(ImageDraw.Draw(emb), cx, cy, sw * 0.055)
    img = Image.alpha_composite(img, emb)
    return img.resize((w, h), Image.LANCZOS).convert("RGB")


def aero_gen_wallpapers(out):
    ensure(out)
    aero_wallpaper().save(os.path.join(out, "aero.png"), optimize=True)
    aero_wallpaper(dark=True).save(os.path.join(out, "aero-login.png"), optimize=True)
    print("  aero wallpapers ok")


def render_frame(active, w=320, h=200):
    W, H = w * SS, h * SS
    r = 7 * SS
    key = "active" if active else "inactive"
    top, mid, bottom = AERO[f"{key}_top"], AERO[f"{key}_mid"], AERO[f"{key}_bottom"]
    border = AERO[f"{key}_border"]
    grad = vgradient((W, TITLE_H * SS), [(0, top), (0.45, mid), (0.5, lerp(mid, bottom, 0.3)), (1, bottom)], FRAME_ALPHA)
    body = Image.new("RGBA", (W, H), (*bottom, FRAME_ALPHA))
    body.paste(grad, (0, 0))
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, W - 1, H - 1], radius=r, fill=255)
    md.rectangle([SIDE_W * SS, TITLE_H * SS, W - SIDE_W * SS - 1, H - BOTTOM_H * SS - 1], fill=0)
    frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    frame.paste(body, (0, 0), mask)
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=r, outline=(*border, 255), width=SS)
    d.rounded_rectangle([SS, SS, W - 1 - SS, H - 1 - SS], radius=r - SS, outline=(255, 255, 255, 140 if active else 110), width=SS)
    d.rectangle([SIDE_W * SS - SS, TITLE_H * SS - SS, W - SIDE_W * SS, H - BOTTOM_H * SS], outline=(*lerp(border, (255, 255, 255), 0.35), 255), width=SS)
    return frame


def crop_scaled(img, box):
    x0, y0, x1, y1 = [v * SS for v in box]
    return downscale(img.crop((x0, y0, x1, y1)), (box[2] - box[0], box[3] - box[1]))


def draw_glyph(d, kind, w, h, color, outline):
    cx, cy = w / 2, h / 2
    t = 2.2 * SS
    if kind == "hide":
        x0, x1 = cx - 5 * SS, cx + 5 * SS
        y = cy + 3 * SS
        d.rectangle([x0 - SS, y - t / 2 - SS, x1 + SS, y + t / 2 + SS], fill=outline)
        d.rectangle([x0, y - t / 2, x1, y + t / 2], fill=color)
    elif kind == "maximize":
        x0, y0, x1, y1 = cx - 5.5 * SS, cy - 4.5 * SS, cx + 5.5 * SS, cy + 4.5 * SS
        d.rectangle([x0 - SS, y0 - SS, x1 + SS, y1 + SS], outline=outline, width=int(t + 2 * SS))
        d.rectangle([x0, y0, x1, y1], outline=color, width=int(t))
        d.rectangle([x0, y0, x1, y0 + 2.5 * SS], fill=color)
    elif kind == "restore":
        for (ox, oy) in ((2.5 * SS, -2.5 * SS), (-2.5 * SS, 2.5 * SS)):
            x0, y0, x1, y1 = cx - 4 * SS + ox, cy - 3.5 * SS + oy, cx + 4 * SS + ox, cy + 3.5 * SS + oy
            d.rectangle([x0 - SS, y0 - SS, x1 + SS, y1 + SS], fill=outline)
            d.rectangle([x0, y0, x1, y1], outline=color, width=int(t * 0.8))
            d.rectangle([x0 + t * 0.8, y0 + t * 0.8, x1 - t * 0.8, y1 - t * 0.8], fill=outline)
            d.rectangle([x0, y0, x1, y0 + 2 * SS], fill=color)
    elif kind == "close":
        s = 4.5 * SS
        d.line([cx - s, cy - s, cx + s, cy + s], fill=outline, width=int(t + 2 * SS))
        d.line([cx + s, cy - s, cx - s, cy + s], fill=outline, width=int(t + 2 * SS))
        d.line([cx - s, cy - s, cx + s, cy + s], fill=color, width=int(t))
        d.line([cx + s, cy - s, cx - s, cy + s], fill=color, width=int(t))
    elif kind == "shade":
        d.polygon([(cx - 5 * SS, cy + 3 * SS), (cx + 5 * SS, cy + 3 * SS), (cx, cy - 4 * SS)], fill=color, outline=outline)
    elif kind == "unshade":
        d.polygon([(cx - 5 * SS, cy - 4 * SS), (cx + 5 * SS, cy - 4 * SS), (cx, cy + 3 * SS)], fill=color, outline=outline)
    elif kind == "stick":
        d.ellipse([cx - 4 * SS, cy - 4 * SS, cx + 4 * SS, cy + 4 * SS], outline=color, width=int(t))
    elif kind == "unstick":
        d.ellipse([cx - 4 * SS, cy - 4 * SS, cx + 4 * SS, cy + 4 * SS], fill=color, outline=outline)


def render_button(kind, state, active, width, round_left, round_right):
    W, H = width * SS, TITLE_H * SS
    BH = BTN_H * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    is_close = kind == "close"
    if state == "prelight":
        if is_close:
            fill = [(0, AERO["close_top"]), (0.5, lerp(AERO["close_top"], AERO["close_bottom"], 0.55)), (1, AERO["close_bottom"])]
        else:
            fill = [(0, AERO["hover_top"]), (0.5, lerp(AERO["hover_top"], AERO["hover_bottom"], 0.5)), (1, AERO["hover_bottom"])]
        alpha = 245
    elif state == "pressed":
        fill = [(0, AERO["close_press_top"]), (1, AERO["close_press_bottom"])] if is_close else [(0, AERO["press_top"]), (1, AERO["press_bottom"])]
        alpha = 250
    else:
        if active:
            fill = [(0, (235, 243, 252)), (0.5, (190, 215, 240)), (0.5, (170, 200, 232)), (1, (200, 222, 244))]
            alpha = 150
        else:
            fill = [(0, (240, 243, 247)), (1, (215, 222, 230))]
            alpha = 120
    grad = vgradient((W, BH), fill, alpha)
    mask = Image.new("L", (W, BH), 0)
    md = ImageDraw.Draw(mask)
    rad = 4 * SS
    md.rectangle([0, 0, W - 1, BH - 1], fill=255)
    if round_left:
        md.rectangle([0, BH - rad, rad, BH - 1], fill=0)
        md.pieslice([0, BH - 2 * rad, 2 * rad, BH - 1], 90, 180, fill=255)
    if round_right:
        md.rectangle([W - rad - 1, BH - rad, W - 1, BH - 1], fill=0)
        md.pieslice([W - 2 * rad - 1, BH - 2 * rad, W - 1, BH - 1], 0, 90, fill=255)
    img.paste(grad, (0, 0), mask)
    border = (40, 60, 90, 200) if (active or state != "normal") else (110, 120, 135, 170)
    outline = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(outline)
    od.rounded_rectangle([0, -rad, W - 1, BH - 1], radius=rad, outline=border, width=SS)
    if not round_left:
        od.rectangle([0, 0, SS - 1, BH - 1], fill=border)
    if not round_right:
        od.rectangle([W - SS, 0, W - 1, BH - 1], fill=border)
    img = Image.alpha_composite(img, outline)
    d = ImageDraw.Draw(img)
    d.line([SS, SS, W - SS, SS], fill=(255, 255, 255, 170), width=SS)
    glyph_color = (255, 255, 255, 255) if (active or state != "normal") else (235, 238, 242, 255)
    glyph_outline = (40, 50, 70, 190) if (active or state != "normal") else (120, 128, 140, 150)
    glyph = {"maximize-toggled": "restore", "shade-toggled": "unshade", "stick-toggled": "unstick"}.get(kind, kind)
    gl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_glyph(ImageDraw.Draw(gl), glyph, W, BH, glyph_color, glyph_outline)
    img = Image.alpha_composite(img, gl)
    return downscale(img, (width, TITLE_H))


def aero_gen_xfwm(out):
    ensure(out)
    w, h = 320, 200
    for active in (True, False):
        suffix = "active" if active else "inactive"
        fr = render_frame(active, w, h)
        pieces = {"top-left": (0, 0, CORNER, TITLE_H), "top-right": (w - CORNER, 0, w, TITLE_H), "title-1": (CORNER, 0, CORNER + 2, TITLE_H),
                  "title-2": (CORNER + 4, 0, CORNER + 6, TITLE_H), "title-3": (w // 2 - 1, 0, w // 2 + 1, TITLE_H), "title-4": (w - CORNER - 6, 0, w - CORNER - 4, TITLE_H),
                  "title-5": (w - CORNER - 2, 0, w - CORNER, TITLE_H), "left": (0, h // 2, SIDE_W, h // 2 + 1), "right": (w - SIDE_W, h // 2, w, h // 2 + 1),
                  "bottom": (w // 2, h - BOTTOM_H, w // 2 + 1, h), "bottom-left": (0, h - CORNER, CORNER, h), "bottom-right": (w - CORNER, h - CORNER, w, h)}
        for name, box in pieces.items():
            crop_scaled(fr, box).save(os.path.join(out, f"{name}-{suffix}.png"))
    specs = {"hide": (BTN_W_SMALL, True, False), "maximize": (BTN_W_SMALL, False, False), "maximize-toggled": (BTN_W_SMALL, False, False), "close": (BTN_W_CLOSE, False, True),
             "shade": (BTN_W_SMALL, True, True), "shade-toggled": (BTN_W_SMALL, True, True), "stick": (BTN_W_SMALL, True, True), "stick-toggled": (BTN_W_SMALL, True, True)}
    for kind, (bw, rl, rr) in specs.items():
        for state in ("active", "inactive", "prelight", "pressed"):
            render_button(kind, "normal" if state in ("active", "inactive") else state, state != "inactive", bw, rl, rr).save(os.path.join(out, f"{kind}-{state}.png"))
    for state in ("active", "inactive", "pressed"):
        Image.new("RGBA", (22, TITLE_H), (0, 0, 0, 0)).save(os.path.join(out, f"menu-{state}.png"))
    print("  aero xfwm4 ok")


def icon_start_orb(S):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = S * 0.03
    cx = cy = S / 2
    r = S / 2 - m
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(10, 30, 70, 255))
    sphere = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sp = sphere.load()
    for y in range(S):
        for x in range(S):
            dx, dy = x - cx, y - cy
            dist = math.hypot(dx, dy)
            if dist <= r - S * 0.02:
                base = lerp((120, 190, 250), (20, 80, 170), (dy / r + 1) / 2)
                base = lerp(base, (10, 40, 110), min(1.0, (dist / r) ** 3) * 0.6)
                sp[x, y] = (*base, 255)
    img = Image.alpha_composite(img, sphere)
    draw_emblem(ImageDraw.Draw(img), cx, cy * 1.02, r * 0.42, glow=False)
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse([cx - r * 0.78, cy - r * 0.92, cx + r * 0.78, cy - r * 0.05], fill=(255, 255, 255, 110))
    img = Image.alpha_composite(img, gloss.filter(ImageFilter.GaussianBlur(S * 0.01)))
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(rim).ellipse([cx - r * 0.6, cy + r * 0.35, cx + r * 0.6, cy + r * 0.95], fill=(170, 230, 255, 70))
    img = Image.alpha_composite(img, rim.filter(ImageFilter.GaussianBlur(S * 0.03)))
    ImageDraw.Draw(img).ellipse([cx - r, cy - r, cx + r, cy + r], outline=(230, 240, 255, 200), width=max(1, int(S * 0.012)))
    return img


def icon_computer(S):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = S / 64
    d.rounded_rectangle([4 * u, 6 * u, 60 * u, 44 * u], radius=4 * u, fill=(60, 64, 70, 255), outline=(25, 28, 32, 255), width=int(u))
    d.rounded_rectangle([8 * u, 10 * u, 56 * u, 40 * u], radius=2 * u, fill=(40, 120, 210, 255))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([10 * u, 12 * u, 50 * u, 34 * u], fill=(140, 200, 255, 120))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(3 * u)))
    d = ImageDraw.Draw(img)
    d.polygon([(8 * u, 10 * u), (56 * u, 10 * u), (8 * u, 30 * u)], fill=(255, 255, 255, 40))
    d.rectangle([28 * u, 44 * u, 36 * u, 50 * u], fill=(90, 95, 100, 255))
    d.rounded_rectangle([16 * u, 50 * u, 48 * u, 56 * u], radius=2 * u, fill=(110, 115, 122, 255), outline=(50, 54, 60, 255), width=int(u))
    return img


def icon_trash(S, full=False):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = S / 64
    d.polygon([(14 * u, 18 * u), (50 * u, 18 * u), (46 * u, 58 * u), (18 * u, 58 * u)], fill=(205, 212, 220, 230), outline=(110, 118, 128, 255))
    for i in range(5):
        x = 20 * u + i * 6 * u
        d.line([(x, 22 * u), (x - 1 * u, 54 * u)], fill=(150, 158, 168, 200), width=int(1.5 * u))
    if full:
        d.rounded_rectangle([18 * u, 4 * u, 34 * u, 22 * u], radius=2 * u, fill=(250, 250, 250, 255), outline=(150, 150, 150, 255), width=int(u))
        d.rounded_rectangle([30 * u, 8 * u, 48 * u, 24 * u], radius=2 * u, fill=(240, 240, 240, 255), outline=(150, 150, 150, 255), width=int(u))
        for yy in (9, 13, 17):
            d.line([(21 * u, yy * u), (31 * u, yy * u)], fill=(120, 140, 200, 255), width=int(u))
    d.rounded_rectangle([10 * u, 14 * u, 54 * u, 20 * u], radius=2 * u, fill=(170, 178, 188, 255), outline=(100, 108, 118, 255), width=int(u))
    d.rounded_rectangle([26 * u, 10 * u, 38 * u, 15 * u], radius=2 * u, fill=(170, 178, 188, 255), outline=(100, 108, 118, 255), width=int(u))
    return img


def icon_network(S):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = S / 64
    d.ellipse([16 * u, 4 * u, 48 * u, 36 * u], fill=(70, 150, 230, 255), outline=(30, 70, 130, 255), width=int(u))
    d.ellipse([24 * u, 4 * u, 40 * u, 36 * u], outline=(200, 230, 255, 200), width=int(u))
    d.line([(16 * u, 20 * u), (48 * u, 20 * u)], fill=(200, 230, 255, 200), width=int(u))
    d.arc([16 * u, 11 * u, 48 * u, 29 * u], 0, 360, fill=(200, 230, 255, 160), width=int(u))
    for x0 in (6, 34):
        d.rounded_rectangle([x0 * u, 38 * u, (x0 + 24) * u, 54 * u], radius=2 * u, fill=(65, 70, 78, 255), outline=(25, 28, 32, 255), width=int(u))
        d.rectangle([(x0 + 3) * u, 41 * u, (x0 + 21) * u, 51 * u], fill=(90, 170, 240, 255))
        d.rectangle([(x0 + 8) * u, 54 * u, (x0 + 16) * u, 58 * u], fill=(110, 115, 122, 255))
    d.line([(18 * u, 36 * u), (32 * u, 30 * u), (46 * u, 36 * u)], fill=(40, 90, 150, 255), width=int(1.5 * u))
    return img


def icon_control_panel(S):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = S / 64
    d.rounded_rectangle([4 * u, 8 * u, 60 * u, 56 * u], radius=5 * u, fill=(235, 238, 242, 255), outline=(120, 128, 138, 255), width=int(u))
    d.rounded_rectangle([4 * u, 8 * u, 60 * u, 18 * u], radius=5 * u, fill=(110, 165, 225, 255))
    d.rectangle([4 * u, 14 * u, 60 * u, 18 * u], fill=(110, 165, 225, 255))
    for i, pos in enumerate((0.3, 0.7, 0.5)):
        y = (26 + i * 10) * u
        d.rounded_rectangle([12 * u, y - 1.5 * u, 52 * u, y + 1.5 * u], radius=u, fill=(160, 168, 178, 255))
        kx = 12 * u + pos * 40 * u
        d.rounded_rectangle([kx - 4 * u, y - 4 * u, kx + 4 * u, y + 4 * u], radius=2 * u, fill=(80, 150, 225, 255), outline=(40, 80, 140, 255), width=int(u))
    return img


def icon_cmd(S):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = S / 64
    d.rounded_rectangle([4 * u, 8 * u, 60 * u, 56 * u], radius=3 * u, fill=(10, 10, 12, 255), outline=(120, 140, 170, 255), width=int(u))
    d.rectangle([4 * u, 8 * u, 60 * u, 15 * u], fill=(160, 195, 235, 255))
    d.text((9 * u, 19 * u), "C:\\>", font=font(max(6, int(18 * u)), bold=True), fill=(230, 230, 230, 255))
    d.rectangle([34 * u, 34 * u, 42 * u, 36 * u], fill=(230, 230, 230, 255))
    return img


def icon_folder(S):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = S / 64
    d.rounded_rectangle([4 * u, 14 * u, 60 * u, 54 * u], radius=3 * u, fill=(214, 170, 70, 255), outline=(150, 110, 30, 255), width=int(u))
    d.polygon([(4 * u, 14 * u), (26 * u, 14 * u), (30 * u, 10 * u), (4 * u, 10 * u)], fill=(214, 170, 70, 255))
    d.rounded_rectangle([8 * u, 20 * u, 60 * u, 54 * u], radius=3 * u, fill=(250, 220, 120, 255), outline=(190, 150, 60, 255), width=int(u))
    d.polygon([(8 * u, 54 * u), (60 * u, 54 * u), (60 * u, 24 * u)], fill=(255, 235, 160, 120))
    return img


def icon_user_home(S):
    img = icon_folder(S)
    d = ImageDraw.Draw(img)
    u = S / 64
    d.ellipse([28 * u, 26 * u, 40 * u, 38 * u], fill=(80, 140, 220, 255), outline=(40, 80, 150, 255), width=int(u))
    d.pieslice([22 * u, 36 * u, 46 * u, 60 * u], 180, 360, fill=(80, 140, 220, 255), outline=(40, 80, 150, 255), width=int(u))
    return img


AERO_ICONS = {
    ("apps", "win7-start"): icon_start_orb, ("apps", "distributor-logo"): icon_start_orb, ("apps", "start-here"): icon_start_orb,
    ("devices", "computer"): icon_computer, ("places", "computer"): icon_computer, ("devices", "drive-harddisk"): icon_computer,
    ("places", "user-trash"): lambda s: icon_trash(s, False), ("places", "user-trash-full"): lambda s: icon_trash(s, True),
    ("places", "network-workgroup"): icon_network, ("apps", "preferences-desktop"): icon_control_panel, ("apps", "xfce4-settings-manager"): icon_control_panel,
    ("apps", "win7-control-panel"): icon_control_panel, ("apps", "win7-cmd"): icon_cmd, ("apps", "utilities-terminal"): icon_cmd,
    ("apps", "win7-explorer"): icon_folder, ("places", "folder"): icon_folder, ("places", "user-home"): icon_user_home,
}


def aero_gen_icons(out):
    base = ensure(out)
    for (ctx, name), fn in AERO_ICONS.items():
        big = fn(512)
        for s in ICON_SIZES:
            downscale(big, (s, s)).save(os.path.join(ensure(os.path.join(base, f"{s}x{s}", ctx)), f"{name}.png"))
    dirs = [f"{s}x{s}/{ctx}" for s in ICON_SIZES for ctx in ("apps", "devices", "places")]
    lines = ["[Icon Theme]", "Name=Windows7-Aero", "Comment=Windows-7-artiges Icon-Overlay für TheWindowsLinux (Original-Artwork)", "Inherits=elementary-xfce,Adwaita,gnome,hicolor", "Directories=" + ",".join(dirs), ""]
    ctx_names = {"apps": "Applications", "devices": "Devices", "places": "Places"}
    for d in dirs:
        s = int(d.split("x")[0]); ctx = d.split("/")[1]
        lines += [f"[{d}]", f"Size={s}", f"Context={ctx_names[ctx]}", "Type=Fixed", ""]
    with open(os.path.join(base, "index.theme"), "w") as fh:
        fh.write("\n".join(lines))
    print("  aero icons ok")


SR = 22050


def tone(freq, dur, vol=0.5, attack=0.01, decay=0.6, harmonics=((1, 1.0), (2, 0.35), (3, 0.12))):
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    sig = np.zeros_like(t)
    for mult, amp in harmonics:
        sig += amp * np.sin(2 * math.pi * freq * mult * t)
    return vol * sig * np.minimum(1.0, t / attack) * np.exp(-t / decay)


def mix(events, total):
    out = np.zeros(int(SR * total))
    for start, sig in events:
        i = int(start * SR)
        n = min(len(sig), len(out) - i)
        if n > 0:
            out[i:i + n] += sig[:n]
    return np.tanh(out * 1.2) * 0.9


def aero_gen_sounds(out):
    if np is None:
        print("  sounds übersprungen (numpy fehlt)"); return
    ensure(out)
    notes = [(0.00, 392.0), (0.22, 523.25), (0.44, 659.25), (0.66, 783.99)]
    write_wav(os.path.join(out, "logon.wav"), mix([(s, tone(f, 1.8, 0.4, decay=0.9)) for s, f in notes] + [(0.66, tone(1567.98, 1.6, 0.12, decay=1.2))], 3.0), SR)
    write_wav(os.path.join(out, "startup.wav"), mix([(0.0, tone(261.63, 2.5, 0.25, decay=1.6)), (0.3, tone(392.0, 2.4, 0.3, decay=1.4)), (0.6, tone(523.25, 2.2, 0.35, decay=1.4)), (0.9, tone(659.25, 2.0, 0.35, decay=1.4)), (1.2, tone(783.99, 2.0, 0.3, decay=1.6))], 3.6), SR)
    write_wav(os.path.join(out, "logoff.wav"), mix([(0.0, tone(659.25, 1.2, 0.35)), (0.25, tone(523.25, 1.2, 0.35)), (0.5, tone(392.0, 1.6, 0.35, decay=0.9))], 2.4), SR)
    write_wav(os.path.join(out, "notify.wav"), mix([(0.0, tone(880.0, 0.5, 0.4, decay=0.25)), (0.12, tone(1174.66, 0.6, 0.35, decay=0.3))], 0.9), SR)
    write_wav(os.path.join(out, "error.wav"), mix([(0.0, tone(196.0, 0.5, 0.5, decay=0.3, harmonics=((1, 1), (2, 0.6), (3, 0.3)))), (0.2, tone(174.61, 0.7, 0.5, decay=0.35, harmonics=((1, 1), (2, 0.6), (3, 0.3))))], 1.1), SR)
    write_wav(os.path.join(out, "ding.wav"), mix([(0.0, tone(1046.5, 0.8, 0.45, decay=0.35))], 0.9), SR)
    print("  aero sounds ok")


def aero_gen_preview():
    W, H = 1280, 800
    img = aero_wallpaper(W, H).convert("RGBA")
    f9 = font(12)
    f10 = font(13)
    mono = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
    fmono = ImageFont.truetype(mono, 13) if os.path.exists(mono) else f10
    d = ImageDraw.Draw(img)
    for i, (label, fn) in enumerate([("Computer", icon_computer), ("Benutzer", icon_user_home), ("Netzwerk", icon_network), ("Papierkorb", lambda s: icon_trash(s, False))]):
        x, y = 24, 24 + i * 96
        img.alpha_composite(downscale(fn(256), (48, 48)), (x + 12, y))
        d = ImageDraw.Draw(img)
        tw = d.textlength(label, font=f9)
        d.text((x + 36 - tw / 2 + 1, y + 53), label, font=f9, fill=(0, 0, 0, 160))
        d.text((x + 36 - tw / 2, y + 52), label, font=f9, fill=(255, 255, 255, 255))

    def window(x, y, w, h, title, active=True, content=None):
        nonlocal img
        fr = downscale(render_frame(active, w, h), (w, h))
        sh = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle([20, 24, w + 20, h + 20], radius=8, fill=(0, 0, 0, 110))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)), (x - 20, y - 20))
        client = Image.new("RGBA", (w - 2 * SIDE_W, h - TITLE_H - BOTTOM_H), (255, 255, 255, 255))
        if content:
            content(client)
        img.alpha_composite(client, (x + SIDE_W, y + TITLE_H))
        img.alpha_composite(fr, (x, y))
        dd = ImageDraw.Draw(img)
        for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            dd.text((x + 30 + ox, y + 8 + oy), title, font=f10, fill=(255, 255, 255, 200))
        dd.text((x + 30, y + 8), title, font=f10, fill=(0, 0, 0, 255))
        img.alpha_composite(downscale(icon_folder(256) if "Explorer" in title else icon_cmd(256), (16, 16)), (x + 9, y + 7))
        bx = x + w - SIDE_W - BTN_W_CLOSE - 2 * BTN_W_SMALL - 2
        for kind, bw in (("hide", BTN_W_SMALL), ("maximize", BTN_W_SMALL), ("close", BTN_W_CLOSE)):
            img.alpha_composite(render_button(kind, "normal", active, bw, kind == "hide", kind == "close"), (bx, y + 1))
            bx += bw

    def explorer_content(c):
        cd = ImageDraw.Draw(c)
        cw, ch = c.size
        cd.rectangle([0, 0, cw, 34], fill=(240, 244, 249, 255))
        cd.rounded_rectangle([70, 6, cw - 180, 28], radius=2, fill=(255, 255, 255, 255), outline=(170, 180, 195, 255))
        cd.text((78, 10), "Computer  ▸  Lokaler Datenträger (C:)  ▸  Benutzer  ▸", font=f9, fill=(20, 20, 20, 255))
        cd.rounded_rectangle([cw - 170, 6, cw - 8, 28], radius=2, fill=(255, 255, 255, 255), outline=(170, 180, 195, 255))
        cd.text((cw - 162, 10), "Benutzer durchsuchen", font=f9, fill=(120, 120, 120, 255))
        for i, (lab, col) in enumerate((("◀", (120, 170, 220)), ("▶", (160, 190, 220)))):
            cd.ellipse([8 + i * 30, 6, 30 + i * 30, 28], fill=(*col, 255), outline=(60, 90, 140, 255))
            cd.text((14 + i * 30, 9), lab, font=f9, fill=(255, 255, 255, 255))
        cd.rectangle([0, 34, cw, 58], fill=(240, 240, 240, 255))
        cd.line([0, 58, cw, 58], fill=(200, 200, 200, 255))
        mx = 10
        for m in ("Organisieren ▾", "In Bibliothek aufnehmen ▾", "Freigeben für ▾", "Brennen", "Neuer Ordner"):
            cd.text((mx, 40), m, font=f9, fill=(0, 0, 0, 255))
            mx += cd.textlength(m, font=f9) + 26
        cd.rectangle([0, 59, 170, ch], fill=(248, 249, 251, 255))
        cd.line([170, 59, 170, ch], fill=(215, 215, 215, 255))
        for i, m in enumerate(("★ Favoriten", "   Desktop", "   Downloads", "   Zuletzt besucht", "", "▸ Bibliotheken", "   Bilder", "   Dokumente", "   Musik", "   Videos", "", "▸ Computer", "   Lokaler Datenträger (C:)", "", "▸ Netzwerk")):
            cd.text((10, 68 + i * 18), m, font=f9, fill=(10, 30, 70, 255))
        fold = downscale(icon_folder(256), (48, 48))
        for i, n in enumerate(("Bilder", "Desktop", "Dokumente", "Downloads", "Musik", "Videos", "Projekte", "Spiele")):
            x = 190 + (i % 4) * 150
            y = 75 + (i // 4) * 95
            if i == 2:
                cd.rounded_rectangle([x - 8, y - 6, x + 120, y + 70], radius=3, fill=(220, 235, 252, 255), outline=(125, 162, 206, 255))
            c.alpha_composite(fold, (x + 30, y))
            cd = ImageDraw.Draw(c)
            tw = cd.textlength(n, font=f9)
            cd.text((x + 54 - tw / 2, y + 50), n, font=f9, fill=(0, 0, 0, 255))
        cd.rectangle([0, ch - 48, cw, ch], fill=(236, 243, 252, 255))
        cd.line([0, ch - 48, cw, ch - 48], fill=(190, 205, 225, 255))
        cd.text((60, ch - 38), "8 Elemente", font=f9, fill=(40, 40, 40, 255))
        cd.text((60, ch - 22), "Lokaler Datenträger (C:)   Freier Speicherplatz: 42,0 GB", font=f9, fill=(90, 90, 90, 255))

    def cmd_content(c):
        cd = ImageDraw.Draw(c)
        cd.rectangle([0, 0, c.size[0], c.size[1]], fill=(0, 0, 0, 255))
        lines = ["TheWindowsLinux [Version 6.1.7601]", "(c) 2026 TheWindowsLinux. Alle Rechte vorbehalten.", "", "C:\\Users\\user>dir", " Volume in Laufwerk C: hat keine Bezeichnung.", " Verzeichnis von C:\\Users\\user", "",
                 "11.11.2026  09:41    <DIR>          Desktop", "11.11.2026  09:41    <DIR>          Dokumente", "11.11.2026  09:41    <DIR>          Downloads", "11.11.2026  09:40             1.204 notizen.txt",
                 "               1 Datei(en),          1.204 Bytes", "               3 Verzeichnis(se), 45.097.156.608 Bytes frei", "", "C:\\Users\\user>_"]
        for i, ln in enumerate(lines):
            cd.text((6, 4 + i * 16), ln, font=fmono, fill=(192, 192, 192, 255))

    window(220, 60, 760, 480, "Benutzer – Windows-Explorer", active=False, content=explorer_content)
    window(560, 300, 640, 320, "Eingabeaufforderung", active=True, content=cmd_content)
    TB = 40
    img.alpha_composite(vgradient((W, TB), [(0, (90, 110, 140)), (0.08, (40, 58, 90)), (0.5, (22, 38, 68)), (1, (34, 54, 92))], 225), (0, H - TB))
    d = ImageDraw.Draw(img)
    d.line([0, H - TB, W, H - TB], fill=(160, 180, 210, 180))
    img.alpha_composite(downscale(icon_start_orb(512), (42, 42)), (4, H - TB - 1))
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    x = 60
    for label, fn, active in [("Windows-Explorer", icon_folder, False), ("Eingabeaufforderung", icon_cmd, True), ("Systemsteuerung", icon_control_panel, False)]:
        bw = 170
        od.rounded_rectangle([x, H - TB + 4, x + bw, H - 4], radius=3, fill=(255, 255, 255, 80 if active else 28), outline=(255, 255, 255, 70))
        od.line([x + 1, H - TB + 5, x + bw - 2, H - TB + 5], fill=(255, 255, 255, 60))
        ov.alpha_composite(downscale(fn(256), (24, 24)), (x + 8, H - TB + 8))
        od = ImageDraw.Draw(ov)
        od.text((x + 40, H - TB + 12), label, font=f9, fill=(255, 255, 255, 255))
        x += bw + 6
    tray_x = W - 230
    od.polygon([(tray_x, H - TB + 24), (tray_x + 10, H - TB + 24), (tray_x + 5, H - TB + 16)], fill=(230, 235, 245, 255))
    sx = tray_x + 26
    od.polygon([(sx, H - 24), (sx + 4, H - 24), (sx + 9, H - 29), (sx + 9, H - 11), (sx + 4, H - 16), (sx, H - 16)], fill=(235, 240, 250, 255))
    od.arc([sx + 8, H - 28, sx + 18, H - 12], -60, 60, fill=(235, 240, 250, 255), width=2)
    sx += 28
    for i in range(4):
        od.rectangle([sx + i * 4, H - 13 - (i + 1) * 3, sx + i * 4 + 2, H - 13], fill=(235, 240, 250, 255))
    sx += 24
    od.rectangle([sx, H - 25, sx + 16, H - 13], outline=(235, 240, 250, 255), width=1)
    od.rectangle([sx + 2, H - 23, sx + 12, H - 15], fill=(140, 220, 120, 255))
    od.rectangle([sx + 16, H - 22, sx + 18, H - 16], fill=(235, 240, 250, 255))
    od.text((W - 118, H - TB + 6), "09:41", font=f9, fill=(255, 255, 255, 255))
    od.text((W - 132, H - TB + 21), "11.11.2026", font=f9, fill=(255, 255, 255, 255))
    od.rectangle([W - 14, H - TB + 2, W - 2, H - 2], fill=(255, 255, 255, 40), outline=(255, 255, 255, 90))
    img.alpha_composite(ov)
    ensure(os.path.join(ROOT, "docs"))
    img.convert("RGB").save(os.path.join(ROOT, "docs", "preview-aero.png"), optimize=True)
    print("  aero preview ok")


# ===========================================================================
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--style", choices=["retro", "aero", "all"], default="all")
    ap.add_argument("--only", choices=["wallpaper", "xfwm", "icons", "cursors", "sounds", "preview", "gtk"])
    args = ap.parse_args()
    want = lambda k: args.only is None or args.only == k  # noqa: E731

    if args.style in ("retro", "all"):
        r = os.path.join(STYLES, "retro")
        print("TheWindowsLinux: erzeuge RETRO-Assets ...")
        if want("wallpaper"):
            retro_gen_wallpapers(os.path.join(r, "wallpapers"))
        if want("xfwm"):
            retro_gen_xfwm(os.path.join(r, "xfwm4", "Windows-Retro"))
        if want("icons"):
            retro_gen_icons(os.path.join(r, "icons", "Windows-Retro"))
        if want("gtk"):
            retro_gen_gtk_assets(os.path.join(r, "gtk", "Windows-Retro", "gtk-3.0", "assets"))
        if want("cursors"):
            retro_gen_cursors(os.path.join(r, "icons", "Windows-Retro"))
        if want("sounds"):
            retro_gen_sounds(os.path.join(r, "sounds"))
        if want("preview"):
            retro_gen_preview(r)
    if args.style in ("aero", "all"):
        a = os.path.join(STYLES, "aero")
        print("TheWindowsLinux: erzeuge AERO-Assets ...")
        if want("wallpaper"):
            aero_gen_wallpapers(os.path.join(a, "wallpapers"))
        if want("xfwm"):
            aero_gen_xfwm(os.path.join(a, "xfwm4", "Windows7-Aero"))
        if want("icons"):
            aero_gen_icons(os.path.join(a, "icons", "Windows7-Aero"))
        if want("sounds"):
            aero_gen_sounds(os.path.join(a, "sounds"))
        if want("preview"):
            aero_gen_preview()
    print("fertig.")


if __name__ == "__main__":
    main()
