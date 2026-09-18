"""Builds the game's working copy of LimeZu open-air place art (D-030).

Companion to import_limezu.py, import_limezu_tiles.py,
import_limezu_props.py and import_limezu_buildings.py. Run after extracting
the packs:

    python tools/import_limezu_places.py

then let Godot import it (`godot --headless --path . --import`).

These are the pieces `PlaceArt` arranges onto an open-air location: the
basketball court is one complete image the size of its whole place, the rest
are single objects a park or a worksite is furnished with. Every file is
copied as is, never cropped or scaled — a place's rect is authored to fit the
art rather than the other way round, for the same reason D-024 gives.

Without the output `PlaceArt` draws nothing and the park, court and worksite
are plain open ground: a thinner look, not a broken one.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
THEMES = (
    ROOT
    / "art/_limezu_source/exteriors/Modern_Exteriors_32x32/ME_Theme_Sorter_32x32"
)
OUT = ROOT / "art/vendor/limezu/places"

# PlaceArt file name -> source, relative to THEMES. The cell sizes in the
# comments are what PlaceArt's authored offsets assume.
FILES = {
    # 13x13 — a whole court, the size of loc_court's rect.
    "court.png": "13_School_Singles_32x32/ME_Singles_School_32x32_Basketball_Court_1.png",
    # Park furniture.
    "tree_1.png": "11_Camping_Singles_32x32/ME_Singles_Camping_32x32_Tree_1.png",       # 4x4
    "tree_2.png": "11_Camping_Singles_32x32/ME_Singles_Camping_32x32_Tree_100.png",     # 4x5
    "tree_3.png": "11_Camping_Singles_32x32/ME_Singles_Camping_32x32_Tree_121.png",     # 4x3
    "tree_4.png": "11_Camping_Singles_32x32/ME_Singles_Camping_32x32_Tree_133.png",     # 5x3
    "bench.png": "17_Garden_Singles_32x32/ME_Singles_Garden_32x32_Big_Bench_Horizontal.png",  # 3x1
    # Worksite.
    "skeleton.png": "8_Worksite_Singles_32x32/ME_Singles_Worksite_32x32_Building_Skeleton_2.png",  # 7x10
    "excavator.png": "8_Worksite_Singles_32x32/ME_Singles_Worksite_32x32_Excavator_1.png",         # 3x6
    "cone.png": "8_Worksite_Singles_32x32/ME_Singles_Worksite_32x32_Cone_2.png",                   # 1x2
}


def main() -> int:
    if not THEMES.is_dir():
        print("LimeZu source not found. Extract the packs first (see PROJECT_STATUS.md).")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    for name, source in FILES.items():
        image = Image.open(THEMES / source).convert("RGBA")
        image.save(OUT / name)
        print(f"  {name:16s} {image.width // 32}x{image.height // 32} cells")
    print(f"{len(FILES)} place pieces written to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
