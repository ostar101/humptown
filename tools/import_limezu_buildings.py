"""Builds the game's working copy of LimeZu whole-building sprites (D-024).

Companion to the other three `import_limezu_*` scripts. Run after extracting
the packs:

    python tools/import_limezu_buildings.py

then let Godot import it (`godot --headless --path . --import`). Without the
output, a home building falls back to `RegionTiles`' generic per-cell wall
and roof — a real building, just plainer, not a broken one.

The per-cell WALL/ROOF atlas (D-021) makes a *generic* building of any size;
LimeZu's actual house art (Modern Exteriors, "Villas") is not generic at
all — a single hand-drawn image with a proper pitched, gabled roof, a porch,
a balcony and a round window, in one piece. `BuildingArt` uses it whole, as
an overlay sprite, for any building whose *rect exactly matches its size* —
see BuildingArt.SPRITE_SIZE and DECISIONS.md D-024 for why "exactly" and not
"close enough" (stretching pixel art distorts it).

The Villa source is one 288x416 (9x13-cell) image, and only its 9th column
is empty margin — every one of its 13 rows down to the porch steps is real
art, so the crop drops only that column. The building's own door — the
`DistrictMap` cell someone interacts with — is NOT the doorway drawn partway
up the image; it is the cell at the *bottom* of the porch, one row past the
visual door, where a person would actually stand to climb the steps. That
keeps the whole porch on screen instead of cutting it off to force the visual
door onto the building's front row.

`shop`/`bar`/`civic`/`work` share a second whole building: the "Post Office"
exteriors, a plain flat-roofed modern storefront that happens to be exactly
the same 8x13 cells as the Villa. Its own signage says "POST OFFICE", which
is wrong on every other kind of building, so the sign band (measured in
`postoffice_1.png`, the same in all four source variants) is repainted flat
in a colour per kind — the same idea as `RegionTiles.THEME_WALL_COLOR`, one
level up.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
EXT = ROOT / "art/_limezu_source/exteriors/Modern_Exteriors_32x32/ME_Theme_Sorter_32x32"
VILLAS = EXT / "7_Villas_Singles_32x32"
POST_OFFICE = EXT / "22_Post_Office_Singles_32x32"
POLICE = EXT / "15_Police_Station_Singles_32x32"
OUT = ROOT / "art/vendor/limezu/buildings"

T = 32
CROP = (0, 0, 8 * T, 13 * T)  # BuildingArt.SPRITE_SIZE, in pixels

# The sign's accent stripe and plate, as measured pixel rows in the source
# image (see the module docstring); repainted flat, per kind, over the
# "POST OFFICE" text so the building reads as a generic storefront.
SIGN_ACCENT_ROWS = (308, 322)
SIGN_PLATE_ROWS = (322, 352)
SIGN_COLOURS = {
    "shop": ("#3a6ea8", "#2a4a70"),
    "bar": ("#a13c3c", "#6e2020"),
    "civic": ("#8a8390", "#5a5560"),
    "work": ("#c9a23a", "#8a6d1f"),
}
# kind -> which Post Office source variant (1-4) it repaints, for a little
# variety between the four kinds sharing this building.
SOURCE_VARIANT = {"shop": 1, "bar": 2, "civic": 3, "work": 4}


def _repaint_sign(image: Image.Image, accent: str, plate: str) -> Image.Image:
    out = image.copy()
    draw = ImageDraw.Draw(out)
    draw.rectangle((0, SIGN_ACCENT_ROWS[0], out.width, SIGN_ACCENT_ROWS[1] - 1), fill=accent)
    draw.rectangle((0, SIGN_PLATE_ROWS[0], out.width, SIGN_PLATE_ROWS[1] - 1), fill=plate)
    return out


def main() -> int:
    if not VILLAS.is_dir() or not POST_OFFICE.is_dir():
        print("LimeZu source not found. Extract the packs first (see PROJECT_STATUS.md).")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    n = 0
    for i in range(1, 6):
        src = VILLAS / f"ME_Singles_Villas_32x32_Villa_{i}.png"
        Image.open(src).convert("RGBA").crop(CROP).save(OUT / f"home_{i}.png")
        n += 1
    for kind, variant in SOURCE_VARIANT.items():
        src = POST_OFFICE / f"22_Post_Office_32x32_Building_{variant}.png"
        image = Image.open(src).convert("RGBA").crop(CROP)
        accent, plate = SIGN_COLOURS[kind]
        _repaint_sign(image, accent, plate).save(OUT / f"{kind}_1.png")
        n += 1
    # The police station is its own building, 7x13 cells and used whole (D-060).
    police = POLICE / "ME_Singles_Police_Station_32x32_Police_Station_Small_1.png"
    Image.open(police).convert("RGBA").save(OUT / "police_1.png")
    n += 1
    print(f"{n} building sprites written to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
