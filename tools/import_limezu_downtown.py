"""Builds the game's working copy of LimeZu's downtown tower sprites.

Companion to `import_limezu_buildings.py`, same idea, a different source
sheet. Run after extracting the packs:

    python tools/import_limezu_downtown.py

then let Godot import it (`godot --headless --path . --import`). Without the
output, a downtown building falls back to `RegionTiles`' generic per-cell
wall and roof, same as any other building whose art is not installed.

`5_Floor_Modular_Building_Singles_32x32` is genuinely modular — a ground
cap, a repeatable middle slice and a roof cap, meant to be stacked for a
building of any height — unlike every other source sheet `BuildingArt`
uses, which is one whole fixed-size image. Rather than teach the runtime to
composite tiles (real surface area across BuildingArt/RegionTiles/ArtShape,
all of which assume one image per building today), this script bakes a
handful of fixed-height PNGs at import time, so BuildingArt never learns the
art was assembled from pieces — the same "prepare it once, load a finished
file" shape `import_limezu_buildings.py` already uses (D-024).

All three source pieces are exactly 7 cells wide. `Ground_Floor_Condo_2` is
the one ground-floor variant this script uses for every height: it draws a
door centred on column 3 of 7 (measured against a 3x-scaled, column-ruled
render — the same "measure, don't assume" lesson D-024 paid for once with
the villa's own door row), matching `police_1.png`'s existing door_column
convention for a 7-wide building. `Middle_Floor_1` (a plain window band, no
door — correct, only the ground floor may have one) repeats once per extra
storey; `Roof_1` (the flat-roofed cap, not the pitched `Roof_Modular`
variant) is the flat, teal-trimmed rooftop that reads as a modern tower's
top rather than a house's.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art/_limezu_source/exteriors/Modern_Exteriors_32x32/ME_Theme_Sorter_32x32/5_Floor_Modular_Building_Singles_32x32"
OUT = ROOT / "art/vendor/limezu/buildings"

T = 32
GROUND = SRC / "ME_Singles_Floor_Modular_Building_32x32_Ground_Floor_Condo_2.png"
MIDDLE = SRC / "ME_Singles_Floor_Modular_Building_32x32_Middle_Floor_1.png"
ROOF = SRC / "ME_Singles_Floor_Modular_Building_32x32_Roof_1.png"

# BuildingArt.BUILDINGS key -> how many Middle_Floor repeats to stack between
# the roof cap (top) and the ground cap (bottom). Walkable floors = repeats + 1 (the ground
# floor); total height in cells = 3 (ground) + 4 * repeats (middle) + 6 (roof).
LINEUP = {"downtown_2": 1, "downtown_4": 3, "downtown_6": 5}


def _composite(ground: Image.Image, middle: Image.Image, roof: Image.Image, repeats: int) -> Image.Image:
    """Roof at the top of the image, ground floor at the bottom: the art is
    seen from the street, so the door must sit on the building's bottom row,
    where the map puts it. (D-107: the first version stacked them the other
    way up, door in the sky and roof on the pavement.)"""
    width = ground.width
    height = ground.height + middle.height * repeats + roof.height
    out = Image.new("RGBA", (width, height))
    out.paste(roof, (0, 0))
    for i in range(repeats):
        out.paste(middle, (0, roof.height + middle.height * i))
    out.paste(ground, (0, height - ground.height))
    return out


def main() -> int:
    if not GROUND.is_file() or not MIDDLE.is_file() or not ROOF.is_file():
        print("LimeZu source not found. Extract the packs first (see PROJECT_STATUS.md).")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    ground = Image.open(GROUND).convert("RGBA")
    middle = Image.open(MIDDLE).convert("RGBA")
    roof = Image.open(ROOF).convert("RGBA")
    n = 0
    for key, repeats in LINEUP.items():
        image = _composite(ground, middle, roof, repeats)
        image.save(OUT / f"{key}_1.png")
        n += 1
    print(f"{n} downtown building sprites written to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
