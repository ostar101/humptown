"""Builds the game's working copy of LimeZu ground/wall/roof tiles (D-019).

Companion to import_limezu.py (which handles the character layers); this one
handles `RegionTiles`. Run after extracting the packs:

    python tools/import_limezu_tiles.py

then let Godot import it (`godot --headless --path . --import`). Without the
output `RegionTiles` falls back to its code-painted atlas, so the game and
tests run either way.

LimeZu's tile packs are built for a level editor with real autotiling
(edge-aware grass/dirt/water borders, per-shop prefab building fronts); they
are not sets of simple, independent "pick one of four" tiles. Rather than
build a full autotiling system to use them (a much bigger feature), this
importer takes only the pieces that ARE self-contained: flat sidewalk and
asphalt tiles, the generic Room Builder floor and wall swatches, and a plain
roof shingle sheet. GRASS, WATER, SAND and DOCK stay code-painted until
ground gets real neighbour-aware tiling; see DECISIONS.md D-021.

`WALL` and `ROOF` are not four interchangeable variants here: `coords_for()`
in RegionTiles gives each column a fixed meaning (upper facade, upper facade
with a window, plinth, interior top // roof body, roof eave). This script
exports exactly the pieces that meaning needs; RegionTiles composites the
window and the top-down darkening itself, from the one upper-wall tile, so
the window-drawing pixels only exist in one place.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
EXT = ROOT / "art/_limezu_source/exteriors/Modern_Exteriors_32x32/ME_Theme_Sorter_32x32"
INT = ROOT / "art/_limezu_source/interiors/1_Interiors/32x32/Room_Bulder_subfiles_32x32"
OUT = ROOT / "art/vendor/limezu/tiles"

T = 32  # tile size


def crop(sheet: Image.Image, col: int, row: int) -> Image.Image:
    return sheet.crop((col * T, row * T, (col + 1) * T, (row + 1) * T))


def main() -> int:
    if not EXT.is_dir() or not INT.is_dir():
        print("LimeZu source not found. Extract the packs first (see PROJECT_STATUS.md).")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)

    sidewalk = EXT / "2_City_Terrains_Singles_32x32"
    for i, name in enumerate(["Sidewalk_1_10", "Sidewalk_2_10", "Sidewalk_3_10", "Sidewalk_6_1"]):
        Image.open(sidewalk / f"ME_Singles_City_Terrains_32x32_{name}.png").convert("RGBA").save(
            OUT / f"pavement_{i}.png"
        )

    asphalt = EXT / "2_City_Terrains_Singles_32x32"
    plain_variations = [18, 19, 20, 21]
    for i, v in enumerate(plain_variations):
        Image.open(asphalt / f"ME_Singles_City_Terrains_32x32_Asphalt_1_Variation_{v}.png").convert(
            "RGBA"
        ).save(OUT / f"road_{i}.png")

    # The dash-mark overlay (Variation_2) is drawn on transparent background,
    # meant to sit on top of plain asphalt; road_line is that composite.
    base = Image.open(asphalt / "ME_Singles_City_Terrains_32x32_Asphalt_1_Variation_18.png").convert("RGBA")
    mark = Image.open(asphalt / "ME_Singles_City_Terrains_32x32_Asphalt_1_Variation_2.png").convert("RGBA")
    line = base.copy()
    line.alpha_composite(mark)
    line.save(OUT / "road_line.png")

    # A wood-plank floor swatch from the Room Builder floor grid. The sheet is
    # a wide continuous plank run (each column is a different phase of the
    # same boards), so using one column repeated avoids seams from randomly
    # mixing phases.
    floors = Image.open(INT / "Room_Builder_Floors_32x32.png").convert("RGBA")
    crop(floors, 0, 12).save(OUT / "floor.png")

    # Generic (non-shop-themed) wall swatches: a plain cream upper wall and a
    # slightly deeper plinth tone directly below it in the same sheet.
    walls = Image.open(INT / "Room_Builder_Walls_32x32.png").convert("RGBA")
    crop(walls, 0, 2).save(OUT / "wall_upper.png")
    crop(walls, 0, 4).save(OUT / "wall_lower.png")

    # A red shingle roof sheet: the top rows are the far slope, the bottom
    # rows the near one (naturally brighter) — used as the eave row.
    roof_sheet_path = (
        EXT
        / "5_Floor_Modular_Building_Singles_32x32"
        / "ME_Singles_Floor_Modular_Building_32x32_Roof_2.png"
    )
    roof_sheet = Image.open(roof_sheet_path).convert("RGBA")
    for i, x in enumerate((0, 32, 64)):
        roof_sheet.crop((x, 0, x + T, T)).save(OUT / f"roof_{i}.png")
    roof_sheet.crop((0, 96, T, 96 + T)).save(OUT / "roof_eave.png")

    names = sorted(p.name for p in OUT.glob("*.png"))
    print(f"{len(names)} tiles written to {OUT}")
    for n in names:
        print(" ", n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
