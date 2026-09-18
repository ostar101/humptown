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
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
VILLAS = (
    ROOT
    / "art/_limezu_source/exteriors/Modern_Exteriors_32x32/ME_Theme_Sorter_32x32"
    / "7_Villas_Singles_32x32"
)
OUT = ROOT / "art/vendor/limezu/buildings"

T = 32
CROP = (0, 0, 8 * T, 13 * T)  # BuildingArt.SPRITE_SIZE, in pixels


def main() -> int:
    if not VILLAS.is_dir():
        print("LimeZu source not found. Extract the packs first (see PROJECT_STATUS.md).")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    n = 0
    for i in range(1, 6):
        src = VILLAS / f"ME_Singles_Villas_32x32_Villa_{i}.png"
        Image.open(src).convert("RGBA").crop(CROP).save(OUT / f"home_{i}.png")
        n += 1
    print(f"{n} building sprites written to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
