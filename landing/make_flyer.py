#!/usr/bin/env python3
"""
Generate a print-ready QR flyer (A5 portrait @ 300 DPI by default).
Pure black/white so it photocopies cleanly.

Usage:
    python3 make_flyer.py "https://what-happend-last-night.netlify.app/"
    python3 make_flyer.py "https://..." --out flyer.png --team "What Happened Last Night?"

Requires: pip install qrcode pillow
"""
import argparse
import sys

try:
    import qrcode
    from qrcode.constants import ERROR_CORRECT_H
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("Run first:  pip install qrcode pillow")


# Try a few font paths in order; fall back to default if none found.
FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",       # macOS
    "/System/Library/Fonts/HelveticaNeue.ttc",                  # macOS
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",     # Linux
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "C:\\Windows\\Fonts\\arialbd.ttf",                          # Windows
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


def make_flyer(url: str, team: str, tagline: str, location: str, out_path: str,
               width: int, height: int) -> None:
    # 1. Render QR code (high error correction so a logo/scuff doesn't kill it)
    qr = qrcode.QRCode(
        version=None,
        error_correction=ERROR_CORRECT_H,
        box_size=20,
        border=2,
    )
    qr.add_data(url)
    qr.make(fit=True)
    qr_img = qr.make_image(fill_color="black", back_color="white").convert("RGB")

    # 2. Build canvas
    canvas = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(canvas)

    # Outer border (thin double-line frame, very subtle)
    margin = int(width * 0.04)
    draw.rectangle([margin, margin, width - margin, height - margin],
                   outline="black", width=4)
    inner = margin + 14
    draw.rectangle([inner, inner, width - inner, height - inner],
                   outline="black", width=1)

    # 3. Top text block
    eyebrow_font  = load_font(int(width * 0.030), bold=True)
    title_font    = load_font(int(width * 0.075), bold=True)
    tagline_font  = load_font(int(width * 0.035), bold=False)
    cta_font      = load_font(int(width * 0.055), bold=True)
    url_font      = load_font(int(width * 0.025), bold=False)
    location_font = load_font(int(width * 0.038), bold=True)
    location_lbl_font = load_font(int(width * 0.024), bold=False)

    content_left  = inner + int(width * 0.04)
    content_right = width - inner - int(width * 0.04)
    content_w     = content_right - content_left
    y = inner + int(height * 0.04)

    # Eyebrow
    eyebrow = "OUR  TEAM"
    tw = draw.textlength(eyebrow, font=eyebrow_font)
    draw.text(((width - tw) / 2, y), eyebrow, fill="black", font=eyebrow_font)
    # underline accent
    y_eb_bottom = y + eyebrow_font.size + 4
    bar_w = int(width * 0.10)
    draw.rectangle([(width - bar_w) / 2, y_eb_bottom + 6,
                    (width + bar_w) / 2, y_eb_bottom + 12], fill="black")
    y = y_eb_bottom + 36

    # Title (wrap if needed)
    title_lines = wrap_to_width(draw, team, title_font, content_w)
    for line in title_lines:
        tw = draw.textlength(line, font=title_font)
        draw.text(((width - tw) / 2, y), line, fill="black", font=title_font)
        y += int(title_font.size * 1.05)
    y += int(height * 0.02)

    # Divider rule
    rule_w = int(width * 0.35)
    draw.line([((width - rule_w) / 2, y), ((width + rule_w) / 2, y)],
              fill="black", width=2)
    y += int(height * 0.025)

    # Tagline
    for line in wrap_to_width(draw, tagline, tagline_font, content_w):
        tw = draw.textlength(line, font=tagline_font)
        draw.text(((width - tw) / 2, y), line, fill="black", font=tagline_font)
        y += int(tagline_font.size * 1.25)

    # 4. QR code — sized to fit between current y and CTA area
    cta_text = "SCAN  TO  WATCH  &  VOTE"
    bottom_reserve = int(height * 0.22)  # space for CTA + URL + Find-us block
    qr_top = y + int(height * 0.03)
    qr_max_h = height - inner - bottom_reserve - qr_top
    qr_max_w = content_w
    qr_size = min(qr_max_h, qr_max_w, int(width * 0.78))
    qr_resized = qr_img.resize((qr_size, qr_size), Image.NEAREST)
    qr_x = (width - qr_size) // 2
    canvas.paste(qr_resized, (qr_x, qr_top))

    # Thin frame around QR for visual definition
    pad = 8
    draw.rectangle([qr_x - pad, qr_top - pad,
                    qr_x + qr_size + pad, qr_top + qr_size + pad],
                   outline="black", width=2)

    y = qr_top + qr_size + pad + int(height * 0.025)

    # 5. CTA
    tw = draw.textlength(cta_text, font=cta_font)
    draw.text(((width - tw) / 2, y), cta_text, fill="black", font=cta_font)
    y += int(cta_font.size * 1.2)

    y += int(height * 0.015)

    # 6. "Find us at" block — small pill near the bottom
    if location:
        label = "FIND  US  AT"
        lbl_w = draw.textlength(label, font=location_lbl_font)
        loc_w = draw.textlength(location, font=location_font)
        block_w = int(max(lbl_w, loc_w) + width * 0.08)
        block_h = int(location_lbl_font.size + location_font.size + width * 0.025)
        bx = (width - block_w) // 2
        by = y
        # rounded-ish rectangle (regular rect with thick border for print)
        draw.rectangle([bx, by, bx + block_w, by + block_h],
                       outline="black", width=3)
        # label
        draw.text(((width - lbl_w) / 2, by + int(width * 0.008)),
                  label, fill="black", font=location_lbl_font)
        # location code
        draw.text(((width - loc_w) / 2,
                   by + int(location_lbl_font.size + width * 0.012)),
                  location, fill="black", font=location_font)

    # 7. Save with DPI metadata for clean print
    canvas.save(out_path, "PNG", dpi=(300, 300), optimize=True)
    print(f"Wrote {out_path}  ({width}x{height} @ 300 DPI)  →  {url}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("url", help="URL the QR code should open")
    p.add_argument("--team", default="What Happened Last Night?", help="Team / title text")
    p.add_argument("--tagline", default="Watch our entry — then vote for us.",
                   help="Short line under the title")
    p.add_argument("--location", default="CLU.T6.PETA",
                   help="Where to find the team (booth/stand code). Set to '' to omit.")
    p.add_argument("--out", default="flyer.png", help="Output PNG path")
    # A5 portrait @ 300 DPI = 1748 x 2480 px
    p.add_argument("--width", type=int, default=1748)
    p.add_argument("--height", type=int, default=2480)
    args = p.parse_args()
    make_flyer(args.url, args.team, args.tagline, args.location,
               args.out, args.width, args.height)
