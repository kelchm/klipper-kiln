#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Generate Klipper big-digit glyphs from JetBrains Mono Bold TTF.

Klipper's [display_glyph] is hardcoded to 16x16. To get a 16xN (N up to 32)
headline digit we render each character at ~N px tall, then emit it as TWO
glyphs per char — "d1_top" + "d1_bot" — that the display_data places on
adjacent display rows. If N < 32, the bot half is partly blank, giving a
visual gap before the next display row's small text.

License of JetBrains Mono: SIL Open Font License (see tools/fonts/JetBrainsMono.LICENSE).
"""

from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
TTF_PATH = SCRIPT_DIR / "fonts" / "JetBrainsMono-Bold.ttf"
OUT_PATH = SCRIPT_DIR.parent / "config" / "big-digits.generated.cfg"

CELL_W = 16          # width of each [display_glyph]
CELL_H = 16          # height of each [display_glyph] (Klipper-fixed)
HEADLINE_H = 32      # full vertical span across two stacked 16x16 cells
SPLIT_Y = 16         # split point: rows 0..15 → top half, 16..31 → bot half
CANVAS = 48          # render canvas, larger than HEADLINE_H for headroom

# Content height target within the 32-row composite. Centering puts equal
# blank padding above and below, distributing the digit body 50:50 between
# the top and bot glyph halves. Cap-height 20 px → 6 px pad each side.
CONTENT_H = 20
TOP_PAD = (HEADLINE_H - CONTENT_H) // 2
BOTTOM_PAD = HEADLINE_H - CONTENT_H - TOP_PAD

RENDER_SIZES_TO_TRY = [14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 38, 42]

# Each entry: (glyph_name, char, alignment)
#   "baseline" — bottom of content aligned to row (CELL_H-2). Digits, letters, -.
#   "top"      — top of content aligned to row 0. The degree symbol, which
#                  sits above the digit cap-top in normal typography.
#   "middle"   — vertically centered in the body. The minus sign.
#   "blank"    — skip rasterization, emit empty 16x16.
#
# Naming: `d` for digit, `l` for letter, `dspace`/`ddeg`/`dminus` for special.
# All glyphs are emitted as both `_top` and `_bot` halves for the 16x24
# stacked headline.
def _build_glyphs():
    g = [(f"d{i}", str(i), "baseline") for i in range(10)]
    for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        g.append((f"l{letter}", letter, "baseline"))
    g.extend([
        ("ddeg", "°", "top"),
        ("dminus", "-", "middle"),
        ("dspace", " ", "blank"),
    ])
    return g


GLYPHS = _build_glyphs()


BASELINE_Y = 32  # fixed baseline within CANVAS for baseline-aligned chars


def rasterize(font: ImageFont.FreeTypeFont, char: str, alignment: str) -> Image.Image:
    img = Image.new("L", (CANVAS, CANVAS), 0)
    if alignment == "blank":
        return img
    draw = ImageDraw.Draw(img)
    if alignment == "top":
        draw.text((2, 0), char, fill=255, font=font, anchor="lt")
    else:  # baseline
        draw.text((2, BASELINE_Y), char, fill=255, font=font, anchor="ls")
    return img


def to_grid(img: Image.Image) -> list[list[bool]]:
    w, h = img.size
    return [[img.getpixel((x, y)) > 127 for x in range(w)] for y in range(h)]


def content_bbox(grid: list[list[bool]]) -> tuple[int, int, int, int]:
    rows = [y for y, row in enumerate(grid) if any(row)]
    if not rows:
        return (0, 0, -1, -1)
    cols = [x for x in range(len(grid[0]))
            if any(grid[y][x] for y in rows)]
    return (min(cols), rows[0], max(cols), rows[-1])


def measure_cap_height(font: ImageFont.FreeTypeFont) -> int:
    """Vertical extent (px) of a digit set in this font."""
    extents = []
    for ch in "0123456789":
        img = rasterize(font, ch, "baseline")
        _, t, _, b = content_bbox(to_grid(img))
        if b >= t:
            extents.append(b - t + 1)
    return max(extents) if extents else 0


def pick_size() -> int:
    """Choose the largest font size whose digits fit within the headline cell
    minus top+bottom padding."""
    target = HEADLINE_H - BOTTOM_PAD - TOP_PAD
    best = RENDER_SIZES_TO_TRY[0]
    for sz in RENDER_SIZES_TO_TRY:
        font = ImageFont.truetype(str(TTF_PATH), sz)
        h = measure_cap_height(font)
        if h <= target:
            best = sz
        else:
            break
    return best


def fit_into_headline(grid: list[list[bool]], alignment: str) -> list[list[bool]]:
    """Render a HEADLINE_H-tall composite that the caller splits into top+bot
    16x16 halves. Vertical placement per alignment mode."""
    if alignment == "blank":
        return [[False] * CELL_W for _ in range(HEADLINE_H)]
    l, t, r, b = content_bbox(grid)
    if r < l:
        return [[False] * CELL_W for _ in range(HEADLINE_H)]
    cw = r - l + 1
    if cw > CELL_W:
        center = (l + r) // 2
        l = max(0, center - CELL_W // 2)
        r = l + CELL_W - 1
        cw = CELL_W
    pad_l = (CELL_W - cw) // 2
    out = [[False] * CELL_W for _ in range(HEADLINE_H)]

    if alignment == "top":
        shift = TOP_PAD - t
    elif alignment == "middle":
        body_top = TOP_PAD
        body_bot = HEADLINE_H - BOTTOM_PAD - 1
        content_h = b - t + 1
        target_top = body_top + (body_bot - body_top + 1 - content_h) // 2
        shift = target_top - t
    else:  # baseline
        shift = (HEADLINE_H - BOTTOM_PAD - 1) - b

    for y in range(t, b + 1):
        dy = y + shift
        if 0 <= dy < HEADLINE_H:
            for x in range(l, r + 1):
                if grid[y][x]:
                    out[dy][pad_l + (x - l)] = True
    return out


def split_into_halves(composite: list[list[bool]]) -> tuple[list[list[bool]], list[list[bool]]]:
    """Split the 32-row composite into two 16x16 halves. With centered
    content and TOP_PAD == BOTTOM_PAD, this yields a true 50:50 distribution
    of the digit body between the top and bot display glyphs."""
    top = composite[:SPLIT_Y]
    bot = composite[SPLIT_Y:HEADLINE_H]
    return top, bot


def emit_glyph(name: str, rows: list[list[bool]]) -> str:
    lines = [f"[display_glyph {name}]", "data:"]
    for row in rows:
        lines.append("  " + "".join("*" if b else "." for b in row))
    return "\n".join(lines)


def main() -> None:
    size = pick_size()
    font = ImageFont.truetype(str(TTF_PATH), size)
    cap = measure_cap_height(font)
    print(f"size={size}, cap={cap}px", file=sys.stderr)

    out_lines = [
        "# Big-headline glyph set for the kiln display.",
        "# Auto-generated by tools/rasterize-glyphs.py — DO NOT HAND-EDIT.",
        f"# Source: JetBrainsMono-Bold.ttf rendered at {size} px.",
        "# License: SIL OFL (tools/fonts/JetBrainsMono.LICENSE).",
        "#",
        "# Each char is split into _top + _bot 16x16 halves with content",
        f"# distributed 50:50 across the {HEADLINE_H} px vertical span.",
        "# Place ~dN_top~/~lN_top~ on display row R, ~..._bot~ on row R+1.",
        "",
    ]
    for name, char, alignment in GLYPHS:
        img = rasterize(font, char, alignment)
        composite = fit_into_headline(to_grid(img), alignment)
        top, bot = split_into_halves(composite)
        out_lines.append(emit_glyph(f"{name}_top", top))
        out_lines.append("")
        out_lines.append(emit_glyph(f"{name}_bot", bot))
        out_lines.append("")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(out_lines))
    print(
        f"wrote {OUT_PATH} ({len(GLYPHS) * 2} glyphs, {len(GLYPHS)} chars)",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
