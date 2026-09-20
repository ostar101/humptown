"""Draws a contact sheet of every animation row of a LimeZu character sheet.

The sheets carry roughly twenty animations, one per 64 px row, and nothing in
the files names them (the Aseprite sources have no tags). This puts each row's
frames side by side, numbered, enlarged, so a person can look at them and
write down which row is which (D-058). It reads the local source pack and
writes only to the folder it is given; nothing here is committed.

    python tools/catalog_limezu_rows.py OUT_DIR [sheet.png]
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SHEET = (ROOT / "art/_limezu_source/interiors/2_Characters/Character_Generator"
                 / "0_Premade_Characters/32x32/Premade_Character_32x32_01.png")
FRAME_W, ROW_H = 32, 64
SCALE = 2
PER_LINE = 24


def frames_in_row(sheet: Image.Image, top: int) -> int:
    """How many 32 px columns of this row hold any pixel (the last such + 1)."""
    alpha = sheet.crop((0, top, sheet.width, top + ROW_H)).getchannel("A")
    last = -1
    for column in range(sheet.width // FRAME_W):
        if alpha.crop((column * FRAME_W, 0, (column + 1) * FRAME_W, ROW_H)).getbbox() is not None:
            last = column
    return last + 1


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(sys.argv[2] if len(sys.argv) > 2 else DEFAULT_SHEET).convert("RGBA")
    rows = sheet.height // ROW_H
    for row in range(rows):
        top = row * ROW_H
        count = frames_in_row(sheet, top)
        if count == 0:
            continue
        lines = (count + PER_LINE - 1) // PER_LINE
        cell_w, cell_h = FRAME_W * SCALE, ROW_H * SCALE + 12
        picture = Image.new("RGBA", (PER_LINE * cell_w, lines * cell_h), (235, 235, 235, 255))
        draw = ImageDraw.Draw(picture)
        for n in range(count):
            x, y = (n % PER_LINE) * cell_w, (n // PER_LINE) * cell_h
            frame = sheet.crop((n * FRAME_W, top, (n + 1) * FRAME_W, top + ROW_H))
            frame = frame.resize((cell_w, ROW_H * SCALE), Image.NEAREST)
            picture.alpha_composite(frame, (x, y))
            draw.text((x + 2, y + ROW_H * SCALE), str(n), fill=(160, 0, 0, 255))
        picture.convert("RGB").save(out / f"row_{row:02d}.png")
        print(f"row {row:2d}  y={top:4d}  frames={count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
