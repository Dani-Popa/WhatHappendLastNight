#!/usr/bin/env python3
"""
Generate a print-ready QR flyer (A5 portrait @ 300 DPI by default).

Modern look: multi-stop vertical gradient background, rounded shadowed
QR card, gradient eyebrow pill, filled CTA button, and a gradient-framed
location pill. QR sits on solid white so it stays bulletproof to scan.

Usage:
    python3 make_flyer.py "https://what-happend-last-night.netlify.app/"
    python3 make_flyer.py "https://..." --out flyer.png --team "..." \
        --top "#7c5cff" --bottom "#3dc9ff"

Requires: pip install qrcode pillow
"""
import argparse
import sys

try:
    import qrcode
    from qrcode.constants import ERROR_CORRECT_H
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("Run first:  pip install qrcode pillow")


# ---------- fonts ----------
FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "C:\\Windows\\Fonts\\arialbd.ttf",
]
FONT_REG_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "C:\\Windows\\Fonts\\arial.ttf",
]


def load_font(size: int, bold: bool = True):
    paths = FONT_CANDIDATES if bold else FONT_REG_CANDIDATES
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()


# ---------- color helpers ----------
def _hex_to_rgb(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def _soften(rgb: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    """Blend toward white by `t` (0 = original, 1 = white)."""
    r, g, b = rgb
    return (int(r + (255 - r) * t),
            int(g + (255 - g) * t),
            int(b + (255 - b) * t))


def _lerp_rgb(a, b, t):
    return (int(a[0] + (b[0] - a[0]) * t),
            int(a[1] + (b[1] - a[1]) * t),
            int(a[2] + (b[2] - a[2]) * t))


# ---------- background ----------
def _make_multi_gradient_bg(width: int, height: int,
                            stops: list[tuple[float, tuple[int, int, int]]]
                            ) -> Image.Image:
    """Vertical gradient with multiple color stops. `stops` is a list of
    (position 0..1, rgb) sorted by position. Renders a 1px strip and
    stretches horizontally."""
    stops = sorted(stops, key=lambda s: s[0])
    strip = Image.new("RGB", (1, height))
    px = strip.load()
    for y in range(height):
        t = y / max(1, height - 1)
        # find the segment t falls into
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                local = (t - p0) / max(1e-6, p1 - p0)
                px[0, y] = _lerp_rgb(c0, c1, local)
                break
        else:
            px[0, y] = stops[-1][1] if t >= stops[-1][0] else stops[0][1]
    return strip.resize((width, height), Image.BILINEAR)


# ---------- shape helpers ----------
def _rounded_shadow_card(canvas: Image.Image, rect, radius: int,
                         fill=(255, 255, 255),
                         shadow_color=(20, 20, 60, 110),
                         shadow_offset=(0, 18), shadow_blur=28) -> None:
    """Paint a rounded card with a soft drop shadow onto `canvas` (RGB).
    `rect` is (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = rect
    pad = shadow_blur * 2

    # Shadow
    sh = Image.new("RGBA", (canvas.width, canvas.height), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.rounded_rectangle(
        [x0 + shadow_offset[0], y0 + shadow_offset[1],
         x1 + shadow_offset[0], y1 + shadow_offset[1]],
        radius=radius, fill=shadow_color)
    sh = sh.filter(ImageFilter.GaussianBlur(shadow_blur))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), sh).convert("RGB"),
                 (0, 0))

    # Card
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=fill)


def _gradient_pill(canvas: Image.Image, rect, radius: int,
                   color_a, color_b, text: str, text_font,
                   text_fill=(255, 255, 255)) -> None:
    """Fill a rounded pill with a horizontal gradient and centered text."""
    x0, y0, x1, y1 = [int(v) for v in rect]
    w, h = x1 - x0, y1 - y0

    # build horizontal gradient inside a pill-shaped mask
    strip = Image.new("RGB", (w, 1))
    spx = strip.load()
    for x in range(w):
        t = x / max(1, w - 1)
        spx[x, 0] = _lerp_rgb(color_a, color_b, t)
    grad = strip.resize((w, h), Image.BILINEAR)

    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w, h], radius=radius, fill=255)

    canvas.paste(grad, (x0, y0), mask)

    d = ImageDraw.Draw(canvas)
    tw = d.textlength(text, font=text_font)
    th = text_font.size
    d.text((x0 + (w - tw) / 2, y0 + (h - th) / 2 - 2),
           text, fill=text_fill, font=text_font)


def _gradient_outline_pill(canvas: Image.Image, rect, radius: int,
                           color_a, color_b, fill=(255, 255, 255),
                           border: int = 6) -> None:
    """Rounded pill with a gradient border and a solid fill."""
    x0, y0, x1, y1 = [int(v) for v in rect]
    w, h = x1 - x0, y1 - y0

    strip = Image.new("RGB", (w, 1))
    spx = strip.load()
    for x in range(w):
        t = x / max(1, w - 1)
        spx[x, 0] = _lerp_rgb(color_a, color_b, t)
    grad = strip.resize((w, h), Image.BILINEAR)

    # outer pill mask
    outer_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(outer_mask).rounded_rectangle([0, 0, w, h], radius=radius, fill=255)
    canvas.paste(grad, (x0, y0), outer_mask)

    # inner fill
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(
        [x0 + border, y0 + border, x1 - border, y1 - border],
        radius=max(0, radius - border), fill=fill)


# ---------- text utility ----------
def wrap_to_width(draw, text: str, font, max_w: int) -> list[str]:
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=font) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


# ---------- main builder ----------
def make_flyer(url: str, team: str, tagline: str, location: str, out_path: str,
               width: int, height: int,
               top_hex: str = "#7c5cff",
               bottom_hex: str = "#3dc9ff") -> None:
    top_raw = _hex_to_rgb(top_hex)
    bot_raw = _hex_to_rgb(bottom_hex)

    # Background uses lightly washed stops so it reads as a real gradient
    # but black text stays crisp. Brand colors stay vivid on the accents.
    top_bg = _soften(top_raw, 0.55)
    mid_bg = _soften(_lerp_rgb(top_raw, bot_raw, 0.5), 0.45)
    bot_bg = _soften(bot_raw, 0.55)

    # 1. QR
    qr = qrcode.QRCode(version=None, error_correction=ERROR_CORRECT_H,
                       box_size=20, border=2)
    qr.add_data(url)
    qr.make(fit=True)
    qr_img = qr.make_image(fill_color="black", back_color="white").convert("RGB")

    # 2. Canvas + 3-stop gradient
    canvas = _make_multi_gradient_bg(
        width, height,
        stops=[(0.0, top_bg), (0.5, mid_bg), (1.0, bot_bg)],
    )
    draw = ImageDraw.Draw(canvas)

    # 3. Layout constants — tighter margins in compact mode so the bigger
    #    secondary text doesn't crowd out the QR.
    compact = width < 800
    side_pad = int(width * (0.045 if compact else 0.08))
    content_w = width - 2 * side_pad

    # Fonts — at sticker sizes (<800 px wide ≈ ≤6.7cm @ 300 DPI) the
    # secondary text needs to be relatively larger to stay legible in print.
    if compact:
        # Sized so the title and tagline each fit on ONE line at 4.5cm wide.
        # Frees up vertical space for a much bigger QR while keeping every
        # secondary label easily readable in print.
        eyebrow_scale = 0.052
        title_scale   = 0.064
        tagline_scale = 0.046
        cta_scale     = 0.058
        loc_lbl_scale = 0.044
        loc_scale     = 0.068
    else:
        eyebrow_scale = 0.026
        title_scale   = 0.082
        tagline_scale = 0.032
        cta_scale     = 0.048
        loc_lbl_scale = 0.022
        loc_scale     = 0.046

    eyebrow_font  = load_font(int(width * eyebrow_scale), bold=True)
    title_font    = load_font(int(width * title_scale),   bold=True)
    tagline_font  = load_font(int(width * tagline_scale), bold=False)
    cta_font      = load_font(int(width * cta_scale),     bold=True)
    loc_lbl_font  = load_font(int(width * loc_lbl_scale), bold=False)
    loc_font      = load_font(int(width * loc_scale),     bold=True)

    # Stronger contrast: near-black with a hint of purple. Muted is darker
    # than before so the tagline / FIND US AT label pop on the gradient.
    text_dark  = (8, 6, 28)
    text_muted = (38, 32, 70)
    accent_a = top_raw             # gradient start (vivid)
    accent_b = bot_raw             # gradient end   (vivid)

    # Top breathing room — tighter on stickers so QR can grow.
    y = int(height * (0.045 if compact else 0.07))

    # 4. Eyebrow as gradient pill ("OUR TEAM")
    eyebrow = "OUR TEAM"
    eb_tw = draw.textlength(eyebrow, font=eyebrow_font)
    eb_pad_x = int(width * 0.045)
    eb_h = int(eyebrow_font.size * 1.95)
    eb_w = int(eb_tw + 2 * eb_pad_x)
    eb_x = (width - eb_w) // 2
    _gradient_pill(canvas, (eb_x, y, eb_x + eb_w, y + eb_h),
                   radius=eb_h // 2,
                   color_a=accent_a, color_b=accent_b,
                   text=eyebrow, text_font=eyebrow_font,
                   text_fill=(255, 255, 255))
    y += eb_h + int(height * (0.018 if compact else 0.025))

    # 5. Title
    title_lines = wrap_to_width(draw, team, title_font, content_w)
    for line in title_lines:
        tw = draw.textlength(line, font=title_font)
        draw.text(((width - tw) / 2, y), line, fill=text_dark, font=title_font)
        y += int(title_font.size * 1.02)
    y += int(height * 0.015)

    # 6. Tagline
    for line in wrap_to_width(draw, tagline, tagline_font, content_w):
        tw = draw.textlength(line, font=tagline_font)
        draw.text(((width - tw) / 2, y), line, fill=text_muted, font=tagline_font)
        y += int(tagline_font.size * 1.3)

    # 7. QR card with soft shadow
    cta_text = "SCAN  TO  WATCH  &  VOTE"
    bottom_reserve = int(height * (0.27 if compact else 0.26))
    qr_top_target = y + int(height * (0.018 if compact else 0.025))
    available_h = height - bottom_reserve - qr_top_target - int(height * 0.015)
    qr_size = min(available_h - int(width * 0.04),
                  content_w - int(width * 0.04),
                  int(width * (0.94 if compact else 0.72)))

    card_pad = int(width * (0.018 if compact else 0.035))
    card_w = qr_size + 2 * card_pad
    card_h = qr_size + 2 * card_pad
    card_x = (width - card_w) // 2
    card_y = qr_top_target
    _rounded_shadow_card(canvas,
                         (card_x, card_y, card_x + card_w, card_y + card_h),
                         radius=int(width * 0.035),
                         fill=(255, 255, 255),
                         shadow_color=(40, 28, 90, 95),
                         shadow_offset=(0, 22),
                         shadow_blur=int(width * 0.018))

    qr_x = card_x + card_pad
    qr_y = card_y + card_pad
    canvas.paste(qr_img.resize((qr_size, qr_size), Image.NEAREST), (qr_x, qr_y))

    y = card_y + card_h + int(height * (0.028 if compact else 0.035))

    # 8. CTA as filled dark pill button
    cta_tw = draw.textlength(cta_text, font=cta_font)
    cta_pad_x = int(width * 0.06)
    cta_h = int(cta_font.size * 1.95)
    cta_w = int(cta_tw + 2 * cta_pad_x)
    cta_x = (width - cta_w) // 2
    _gradient_pill(canvas, (cta_x, y, cta_x + cta_w, y + cta_h),
                   radius=cta_h // 2,
                   color_a=text_dark, color_b=text_dark,
                   text=cta_text, text_font=cta_font,
                   text_fill=(255, 255, 255))
    y += cta_h + int(height * (0.014 if compact else 0.022))

    # 9. Find-us pill with gradient border
    if location:
        label = "FIND US AT"
        lbl_w = draw.textlength(label, font=loc_lbl_font)
        loc_w = draw.textlength(location, font=loc_font)
        inner_w = max(lbl_w, loc_w)
        pad_x = int(width * 0.06)
        pad_y = int(width * 0.022)
        pill_w = int(inner_w + 2 * pad_x)
        pill_h = int(loc_lbl_font.size + loc_font.size + pad_y * 2 + 6)
        pill_x = (width - pill_w) // 2
        pill_y = y
        _gradient_outline_pill(canvas,
                               (pill_x, pill_y,
                                pill_x + pill_w, pill_y + pill_h),
                               radius=int(pill_h * 0.5),
                               color_a=accent_a, color_b=accent_b,
                               fill=(255, 255, 255),
                               border=int(width * 0.005))
        # Label
        draw.text(((width - lbl_w) / 2, pill_y + pad_y),
                  label, fill=text_muted, font=loc_lbl_font)
        # Code
        code_y = pill_y + pad_y + loc_lbl_font.size + 6
        draw.text(((width - loc_w) / 2, code_y),
                  location, fill=text_dark, font=loc_font)

    # 10. Save
    canvas.save(out_path, "PNG", dpi=(300, 300), optimize=True)
    print(f"Wrote {out_path}  ({width}x{height} @ 300 DPI)  →  {url}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("url", help="URL the QR code should open")
    p.add_argument("--team", default="What Happened Last Night?",
                   help="Team / title text")
    p.add_argument("--tagline", default="Watch our entry — then vote for us.",
                   help="Short line under the title")
    p.add_argument("--location", default="CLU.T6.PETA",
                   help="Where to find the team. Set to '' to omit.")
    p.add_argument("--out", default="flyer.png", help="Output PNG path")
    # A5 portrait @ 300 DPI = 1748 x 2480 px
    p.add_argument("--width", type=int, default=1748)
    p.add_argument("--height", type=int, default=2480)
    p.add_argument("--top", default="#7c5cff",
                   help="Hex color for the top accent / gradient start.")
    p.add_argument("--bottom", default="#3dc9ff",
                   help="Hex color for the bottom accent / gradient end.")
    args = p.parse_args()

    make_flyer(args.url, args.team, args.tagline, args.location,
               args.out, args.width, args.height,
               top_hex=args.top, bottom_hex=args.bottom)
