#!/usr/bin/env python3
"""
make_icon.py — Generate a 1024×1024 macOS app icon for MorseRunner.

Design: a Morse-code-themed icon. The letters "CQ" (the universal CW call)
are rendered as their Morse dit/dah patterns:

    C = -·-·   (dah dit dah dit)
    Q = --·-   (dah dah dit dah)

A dark blue gradient background evokes radio/night-sky, with bright cyan
dots and dashes for strong visual contrast at all sizes.
"""

import math
from PIL import Image, ImageDraw

SIZE = 1024


def lerp(a, b, t):
    return a + (b - a) * t


def make_gradient(size, top, bottom):
    """Vertical gradient from `top` to `bottom`."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        r = int(lerp(top[0], bottom[0], t))
        g = int(lerp(top[1], bottom[1], t))
        b = int(lerp(top[2], bottom[2], t))
        for x in range(size):
            px[x, y] = (r, g, b)
    return img


def round_rect_mask(size, radius):
    """Return an L-mode mask: white inside a rounded rect, black outside."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_dit(draw, cx, cy, r, fill):
    """Draw a Morse dit (dot) — a filled circle."""
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def draw_dah(draw, cx, cy, half_w, half_h, fill):
    """Draw a Morse dah (dash) — a filled rounded rectangle."""
    draw.rounded_rectangle(
        [cx - half_w, cy - half_h, cx + half_w, cy + half_h],
        radius=half_h,
        fill=fill,
    )


def main():
    # --- Background: dark blue gradient with rounded corners (macOS "squircle") ---
    # macOS app icons use a superellipse; a rounded rect with ~22% corner radius
    # is the standard approximation.
    corner_radius = int(SIZE * 0.223)
    top_color = (30, 60, 110)       # deep blue
    bottom_color = (12, 24, 55)     # near-black blue
    bg = make_gradient(SIZE, top_color, bottom_color)
    mask = round_rect_mask(SIZE, corner_radius)

    # Compose onto transparent canvas so corners are transparent (proper .icns).
    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), mask)

    draw = ImageDraw.Draw(icon, "RGBA")

    # --- Morse elements ---
    # We draw C and Q patterns stacked vertically.
    #
    #   C = dah  dit  dah  dit     (- · - ·)
    #   Q = dah  dah  dit  dah     (- - · -)
    #
    # Each element is centered horizontally. Within a row, elements are laid
    # out left-to-right with uniform spacing.

    dit_r = SIZE * 0.038          # dit radius
    dah_half_w = SIZE * 0.085     # dah half-width
    elem_half_h = SIZE * 0.038    # element half-height (dit r / dah half-h)
    gap = SIZE * 0.028            # gap between elements (1 dit length)
    row_gap = SIZE * 0.10         # vertical gap between C and Q rows

    fill_bright = (90, 210, 255, 255)   # bright cyan
    fill_glow = (120, 220, 255, 90)     # soft glow underlay

    # C pattern: dah dit dah dit
    c_pattern = ["dah", "dit", "dah", "dit"]
    # Q pattern: dah dah dit dah
    q_pattern = ["dah", "dit", "dah", "dah"]

    def element_width(kind):
        if kind == "dit":
            return dit_r * 2
        else:
            return dah_half_w * 2

    def draw_row(pattern, cy):
        # Compute total width of all elements + gaps.
        total = sum(element_width(k) for k in pattern) + gap * (len(pattern) - 1)
        x = (SIZE - total) / 2
        for kind in pattern:
            w = element_width(kind)
            cx = x + w / 2
            # Glow underlay (slightly larger, low alpha) for a neon effect.
            if kind == "dit":
                draw_dit(draw, cx, cy, dit_r * 1.7, fill_glow)
                draw_dit(draw, cx, cy, dit_r, fill_bright)
            else:
                draw_dah(draw, cx, cy, dah_half_w * 1.25, elem_half_h * 1.6, fill_glow)
                draw_dah(draw, cx, cy, dah_half_w, elem_half_h, fill_bright)
            x += w + gap

    # Position C in the upper-middle, Q in the lower-middle.
    c_y = SIZE * 0.40
    q_y = c_y + elem_half_h * 2 + row_gap
    draw_row(c_pattern, c_y)
    draw_row(q_pattern, q_y)

    # --- Subtle bottom label "CW" (small, low-opacity) ---
    # Skip text to avoid font-availability issues; the Morse pattern is enough.

    icon.save("AppIcon-1024.png")
    print("Wrote AppIcon-1024.png (%dx%d)" % (SIZE, SIZE))


if __name__ == "__main__":
    main()
