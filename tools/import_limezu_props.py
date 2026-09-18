"""Builds the game's working copy of LimeZu street furniture (D-022).

Companion to import_limezu.py and import_limezu_tiles.py. Run after
extracting the packs:

    python tools/import_limezu_props.py

then let Godot import it (`godot --headless --path . --import`). Without the
output, `StreetProps` places nothing — these are pure decoration (no
gameplay effect, no collision), so there is no code-painted fallback to keep
in sync; skipping them is a legitimate, simple "no art installed" state.

Each file is a standalone sprite, taller than one tile, so it is copied as
is rather than cropped from a sheet; `StreetProps`/`RegionView` anchor it by
its bottom-centre onto the cell it stands on, the same convention
`CharacterFigure` uses for people.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PROPS = (
    ROOT
    / "art/_limezu_source/exteriors/Modern_Exteriors_32x32/ME_Theme_Sorter_32x32"
    / "3_City_Props_Singles_32x32"
)
OUT = ROOT / "art/vendor/limezu/props"

# StreetProps.KINDS names -> source file. One look per kind for now; picking
# among a few is a later flourish, not a first pass.
FILES = {
    "lamp": "ME_Singles_City_Props_32x32_Street_Lamp_3.png",
    "trash": "ME_Singles_City_Props_32x32_Small_Closed_Trash_Can.png",
    "hydrant": "ME_Singles_City_Props_32x32_Hydrant_1.png",
}


def main() -> int:
    if not PROPS.is_dir():
        print("LimeZu source not found. Extract the packs first (see PROJECT_STATUS.md).")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    for kind, filename in FILES.items():
        Image.open(PROPS / filename).convert("RGBA").save(OUT / f"{kind}.png")
    print(f"{len(FILES)} props written to {OUT}")
    for kind in FILES:
        print(" ", kind)
    return 0


if __name__ == "__main__":
    sys.exit(main())
