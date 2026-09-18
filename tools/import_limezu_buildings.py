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

The Villa source is one 288x416 (9x13-cell) image with a transparent 9th
column; only its top-left 8x11 cells are real art — the rest is an empty
margin and, at the bottom, porch steps below the doorway that would otherwise
push the visual door a cell lower than `DistrictMap`'s "the door is on the
building's front row" rule expects. Cropping to that 8x11 keeps the door
cell exactly aligned and loses only those steps.
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
CROP = (0, 0, 8 * T, 11 * T)  # BuildingArt.SPRITE_SIZE, in pixels


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
