"""Generate launcher icon PNGs for GitMdScribe.

Outputs:
  assets/icon/icon.png             1024x1024, full-bleed legacy icon (dark bg).
  assets/icon/icon_foreground.png  1024x1024, transparent; foreground art
                                   confined to inner ~66% for Android adaptive
                                   masking (safe zone).

Run: `python tool/gen_icon.py` from repo root.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# --- constants -------------------------------------------------------------

SIZE = 1024                 # master canvas
SUPERSAMPLE = 2             # draw at 2x then downscale for smoother edges
W = SIZE * SUPERSAMPLE

# Palette
BG_TOP = (30, 41, 59)       # slate-800
BG_BOT = (15, 23, 42)       # slate-900
PAPER = (248, 244, 233)     # warm cream
PAPER_FOLD = (220, 213, 196)
PAPER_FOLD_EDGE = (176, 168, 146)
INK = (37, 99, 235)         # blue-600 — redline ink
INK_SHADOW = (23, 64, 158)
GIT_ACCENT = (245, 158, 11) # amber-500 — git node accent
GIT_ACCENT_DARK = (180, 116, 8)

OUT = Path(__file__).resolve().parents[1] / "assets" / "icon"


# --- helpers ---------------------------------------------------------------

def vgradient(w: int, h: int, top: tuple[int, int, int], bot: tuple[int, int, int]) -> Image.Image:
    """Vertical linear gradient."""
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        grad.putpixel((0, y), (
            int(top[0] + (bot[0] - top[0]) * t),
            int(top[1] + (bot[1] - top[1]) * t),
            int(top[2] + (bot[2] - top[2]) * t),
        ))
    return grad.resize((w, h))


def tapered_stroke(draw: ImageDraw.ImageDraw, p0, p1, w_start, w_mid, w_end, color):
    """Draw a tapered polygon stroke from p0 to p1 with widths at start/mid/end."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / length, dx / length  # unit normal
    mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)

    def off(p, w):
        return (
            (p[0] + nx * w / 2, p[1] + ny * w / 2),
            (p[0] - nx * w / 2, p[1] - ny * w / 2),
        )

    (s1, s2), (m1, m2), (e1, e2) = off(p0, w_start), off(mid, w_mid), off(p1, w_end)
    draw.polygon([s1, m1, e1, e2, m2, s2], fill=color)
    # Round caps
    r_start = int(w_start / 2)
    r_end = int(w_end / 2)
    if r_start > 0:
        draw.ellipse((p0[0] - r_start, p0[1] - r_start, p0[0] + r_start, p0[1] + r_start), fill=color)
    if r_end > 0:
        draw.ellipse((p1[0] - r_end, p1[1] - r_end, p1[0] + r_end, p1[1] + r_end), fill=color)


def draw_foreground(canvas: Image.Image, scale: float = 1.0, offset=(0, 0)):
    """Draw doc + ink swipe + git branch glyph onto canvas (RGBA).

    scale applies to the whole composition — use <1.0 to shrink for adaptive
    icon safe zone. offset shifts the composition in master-canvas units.
    """
    draw = ImageDraw.Draw(canvas)
    s = SUPERSAMPLE

    def S(v: float) -> int:
        return int(v * scale * s)

    ox, oy = int(offset[0] * s), int(offset[1] * s)
    cx_master = W // 2 + ox
    cy_master = W // 2 + oy

    # Document footprint (relative to canvas center)
    doc_w = S(640)
    doc_h = S(780)
    fold = S(160)
    doc_left = cx_master - doc_w // 2
    doc_right = cx_master + doc_w // 2
    doc_top = cy_master - doc_h // 2
    doc_bottom = cy_master + doc_h // 2

    # Soft drop shadow under the doc
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.polygon(
        [
            (doc_left, doc_top),
            (doc_right - fold, doc_top),
            (doc_right, doc_top + fold),
            (doc_right, doc_bottom),
            (doc_left, doc_bottom),
        ],
        fill=(0, 0, 0, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=S(14)))
    # Offset shadow down-right a touch
    shadow_off = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_off.paste(shadow, (S(8), S(14)), shadow)
    canvas.alpha_composite(shadow_off)

    # Document body (cut corner at top-right)
    doc_poly = [
        (doc_left, doc_top),
        (doc_right - fold, doc_top),
        (doc_right, doc_top + fold),
        (doc_right, doc_bottom),
        (doc_left, doc_bottom),
    ]
    draw.polygon(doc_poly, fill=PAPER)

    # Fold triangle (darker) + crease
    fold_poly = [
        (doc_right - fold, doc_top),
        (doc_right, doc_top + fold),
        (doc_right - fold, doc_top + fold),
    ]
    draw.polygon(fold_poly, fill=PAPER_FOLD)
    # Crease shadow
    draw.line(
        [(doc_right - fold, doc_top), (doc_right - fold, doc_top + fold), (doc_right, doc_top + fold)],
        fill=PAPER_FOLD_EDGE,
        width=S(3),
    )

    # Subtle horizontal lines to suggest a page of text
    text_line_color = (210, 204, 188)
    line_left_pad = S(80)
    line_right_pad_base = S(80)
    top_pad = S(160)
    line_gap = S(64)
    line_h = S(12)
    for i in range(7):
        ly = doc_top + top_pad + i * line_gap
        # Shorten lines that would clip into the fold
        right = doc_right - line_right_pad_base
        if ly < doc_top + fold:
            right = min(right, (doc_right - fold) - S(24))
        # Some lines shorter for variety (last-line effect)
        if i == 6:
            right = doc_left + doc_w // 2 + S(60)
        draw.rounded_rectangle(
            (doc_left + line_left_pad, ly, right, ly + line_h),
            radius=line_h // 2,
            fill=text_line_color,
        )

    # Git-branch glyph at the fold — small, amber
    gx = doc_right - fold + S(30)
    gy = doc_top + S(30)
    node_r = S(16)
    stem_len = S(46)
    stem_w = S(8)
    # Vertical line
    draw.rounded_rectangle(
        (gx - stem_w // 2, gy, gx + stem_w // 2, gy + stem_len),
        radius=stem_w // 2,
        fill=GIT_ACCENT_DARK,
    )
    # Node dot
    draw.ellipse(
        (gx - node_r, gy + stem_len - node_r // 2, gx + node_r, gy + stem_len + node_r * 2 - node_r // 2),
        fill=GIT_ACCENT,
    )
    # Ring highlight on node
    hl_r = node_r // 3
    draw.ellipse(
        (gx - hl_r, gy + stem_len + node_r // 2 - hl_r, gx + hl_r, gy + stem_len + node_r // 2 + hl_r),
        fill=(255, 220, 150),
    )

    # Ink swipe — bold diagonal redline across the doc body
    # Start: lower-left area of doc; End: upper-right, stopping well before the fold
    p_start = (doc_left + S(70), doc_bottom - S(130))
    p_end = (doc_right - fold - S(40), doc_top + S(140))

    # Shadow layer (soft)
    shadow_stroke = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd2 = ImageDraw.Draw(shadow_stroke)
    tapered_stroke(
        sd2,
        (p_start[0] + S(4), p_start[1] + S(8)),
        (p_end[0] + S(4), p_end[1] + S(8)),
        S(10), S(58), S(16),
        (*INK_SHADOW, 180),
    )
    shadow_stroke = shadow_stroke.filter(ImageFilter.GaussianBlur(radius=S(5)))
    canvas.alpha_composite(shadow_stroke)

    # Main ink stroke
    tapered_stroke(draw, p_start, p_end, S(10), S(60), S(18), INK)
    # Ink highlight — thinner, offset, lighter — gives the stroke some life
    hl_start = (p_start[0] + S(2), p_start[1] - S(8))
    hl_end = (p_end[0] + S(2), p_end[1] - S(8))
    hl_color = (120, 160, 255, 110)
    tapered_stroke(draw, hl_start, hl_end, S(2), S(14), S(4), hl_color)


# --- build -----------------------------------------------------------------

def build_legacy_icon() -> Image.Image:
    """Full-bleed icon with dark gradient background + rounded mask."""
    # Paint gradient bg
    big = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    grad = vgradient(W, W, BG_TOP, BG_BOT).convert("RGBA")
    # Rounded square mask — Android adaptive will re-mask, but this is
    # also the icon that ships for legacy <API 26.
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, W, W), radius=int(W * 0.22), fill=255)
    big.paste(grad, (0, 0), mask)

    # Foreground composition — at ~82% scale so there's padding on legacy
    draw_foreground(big, scale=0.82, offset=(0, 0))

    return big.resize((SIZE, SIZE), Image.LANCZOS)


def build_adaptive_foreground() -> Image.Image:
    """Transparent foreground for adaptive icon. Art at ~58% scale to sit
    inside the 66% safe zone with a little breathing room."""
    big = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_foreground(big, scale=0.58, offset=(0, 0))
    return big.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    legacy = build_legacy_icon()
    legacy.save(OUT / "icon.png", optimize=True)
    print(f"wrote {OUT / 'icon.png'}")

    fg = build_adaptive_foreground()
    fg.save(OUT / "icon_foreground.png", optimize=True)
    print(f"wrote {OUT / 'icon_foreground.png'}")


if __name__ == "__main__":
    main()
