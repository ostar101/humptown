"""Builds the game's working copy of LimeZu ground terrain (D-031).

Companion to the other import_limezu_*.py scripts. Run after extracting the
packs:

    python tools/import_limezu_terrain.py

then let Godot import it (`godot --headless --path . --import`).

Two kinds of output, because `RegionTiles` uses them two different ways:

**Plain tiles** (`grass_N`, `sand`, `dock_N`) are ordinary per-cell art that
replaces the code-painted ground from D-014. LimeZu's base grass is a single
flat green with no texture of its own — the life comes from tufts scattered
over it — so three of the four grass variants get a `Props_Grass` tuft
composited on here, the same way `RegionTiles._blit_real()` composites a
window onto a wall.

**Edge sets** (`edge_*`) are 4x4 blocks: a terrain's sixteen ways of meeting
a different one, laid out so that column 0 is its western edge, column 3 its
eastern, row 0 its northern and row 3 its southern, with the four middle
cells the open interior. `RegionTiles` picks one with a four-bit neighbour
mask. The water sets keep LimeZu's eight animation frames, side by side, four
columns apart — which is exactly what Godot's tile animation separation
expects, so the sea moves without a line of code.

    edge_water_sand   the sea meeting a beach          8 frames
    edge_water_dock   the sea meeting the quay         8 frames
    edge_road         asphalt meeting a pavement kerb  1 frame

`edge_water_dock` is composited here: LimeZu's "No_Sand" sea set is
transparent where the land would be, which is right for drawing over a beach
in a layered editor and wrong for a single ground layer, so the deck is
painted in underneath at import time.

Without this output `RegionTiles` falls back to the code-painted ground and
picks no edges at all — flat, hard-edged, and perfectly playable.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art/_limezu_source/exteriors/Modern_Exteriors_32x32"
THEMES = SRC / "ME_Theme_Sorter_32x32"
TERRAIN = THEMES / "1_Terrains_and_Fences_Singles_32x32"
CITY = THEMES / "2_City_Terrains_Singles_32x32"
CAMPING = THEMES / "11_Camping_Singles_32x32"
ANIMATED = SRC / "Animated_32x32/Animated_Terrains_32x32"
OUT = ROOT / "art/vendor/limezu/terrain"

TILE = 32
FRAMES = 8

# Sidewalk piece numbers, read off the art by which of a tile's four edges
# carry the light kerb. 10 is plain asphalt, 9 plain pavement (unused here).
KERB = [
    [13, 6, 6, 14],
    [4, 10, 10, 8],
    [4, 10, 10, 8],
    [12, 2, 2, 11],
]

# Only Props_Grass_9 upwards are actual transparent clumps; 1-8 are whole
# tiles with a patch drawn into them, which tile into a chequerboard. One
# clump on one variant in four is enough to break up a lawn without turning
# it into a pattern.
GRASS_TUFT = "Props_Grass_9"
# One plank pattern for the whole quay. The pier set's four deck tiles differ
# in which planks are darker, and picking among them per cell turns a boardwalk
# into vertical stripes; a deck reads better as one continuous run.
DOCK_PIECES = ["Pier_7", "Pier_7", "Pier_7", "Pier_7"]


def _terrain(name: str) -> Image.Image:
    return Image.open(TERRAIN / f"ME_Singles_Terrains_and_Fences_32x32_{name}.png").convert("RGBA")


def _write_plain_tiles() -> list[str]:
    written = []
    grass = _terrain("Grass_1_22")
    tuft = _terrain(GRASS_TUFT).crop((0, 0, TILE, TILE))
    for v in range(4):
        tile = grass.copy()
        if v == 3:
            tile.alpha_composite(tuft)
        tile.save(OUT / f"grass_{v}.png")
        written.append(f"grass_{v}.png")

    # The beach the shoreline is drawn against, taken from the sea set itself
    # so the two cannot drift apart in colour.
    sea = Image.open(ANIMATED / "Sea_Water_Tileset_32x32.png").convert("RGBA")
    sea.crop((5 * TILE, 1 * TILE, 6 * TILE, 2 * TILE)).save(OUT / "sand.png")
    written.append("sand.png")

    for v, piece in enumerate(DOCK_PIECES):
        deck = Image.open(CAMPING / f"ME_Singles_Camping_32x32_{piece}.png").convert("RGBA")
        deck.save(OUT / f"dock_{v}.png")
        written.append(f"dock_{v}.png")
    return written


def _write_water_sets() -> list[str]:
    basic = Image.open(ANIMATED / "Sea_Water_Tileset_Basic_32x32.png").convert("RGBA")
    basic.save(OUT / "edge_water_sand.png")

    # The same set without its beach, laid over the quay decking so the
    # transparent half of each edge tile is planking rather than a hole.
    no_sand = Image.open(ANIMATED / "Sea_Water_Tileset_No_Sand_Basic_32x32.png").convert("RGBA")
    deck = Image.open(OUT / "dock_0.png").convert("RGBA")
    backing = Image.new("RGBA", no_sand.size)
    for y in range(0, no_sand.height, TILE):
        for x in range(0, no_sand.width, TILE):
            backing.paste(deck, (x, y))
    backing.alpha_composite(no_sand)
    backing.save(OUT / "edge_water_dock.png")
    return ["edge_water_sand.png", "edge_water_dock.png"]


def _write_road_set() -> list[str]:
    block = Image.new("RGBA", (4 * TILE, 4 * TILE))
    for row, pieces in enumerate(KERB):
        for col, piece in enumerate(pieces):
            tile = Image.open(CITY / f"ME_Singles_City_Terrains_32x32_Sidewalk_1_{piece}.png").convert("RGBA")
            block.paste(tile, (col * TILE, row * TILE))
    block.save(OUT / "edge_road.png")
    return ["edge_road.png"]


def main() -> int:
    if not THEMES.is_dir() or not ANIMATED.is_dir():
        print("LimeZu source not found. Extract the packs first (see PROJECT_STATUS.md).")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    written = _write_plain_tiles() + _write_water_sets() + _write_road_set()
    for name in written:
        image = Image.open(OUT / name)
        print(f"  {name:22s} {image.width // TILE}x{image.height // TILE} cells")
    print(f"{len(written)} terrain files written to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
