"""Builds the game's working copy of LimeZu's character layers (D-019).

The packs themselves may not be redistributed, so neither the extracted source
(art/_limezu_source/) nor this script's output (art/vendor/limezu/) is
committed. Anyone with the packs rebuilds the output with:

    python tools/import_limezu.py

then lets Godot import it (`godot --headless --path . --import`). Without the
output the game falls back to the code-drawn figures.

What it does, per layer (body, eyes, outfit, hairstyle):
- keeps only the animations the game plays (ACTIONS below: standing, idle,
  walk, and the few others it shows) and stacks them, one 64 px row each, into
  a compact atlas per layer, because a whole sheet is ~9 MB of video memory
  and a person wears four of them;
- measures the layer's mean colour, so an authored palette colour can pick
  the closest variant (CharacterSprites.look_for);
- writes manifest.json listing everything, including where each action sits
  in the atlas, because an exported game cannot list res:// directories
  reliably.

Which source row is which animation was read off the sheet by eye, with
tools/catalog_limezu_rows.py (D-058); the files themselves name nothing.

Children's layers are never imported: every simulated person is an adult.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "art/_limezu_source/interiors/2_Characters/Character_Generator"
OUT = ROOT / "art/vendor/limezu/characters"

FRAME_W, FRAME_H = 32, 64
# The animations kept, in atlas order: (name, source row, frames, directional).
# A directional row is four blocks of `frames`, in the order right, up, left,
# down; anything else is one run of frames facing the viewer. Rows are 64 px
# apart in every layer's sheet. Extra columns on a row (labels, props) are not
# copied.
ACTIONS = (
    ("stand", 0, 1, True),
    ("idle", 1, 6, True),
    ("walk", 2, 6, True),
    ("phone", 6, 12, False),    # frames 0-3 lift it, 4-9 loop, 10-11 put it away
    ("gift", 10, 10, True),     # holding something out
)
DOWN_STAND = (3 * FRAME_W, 0, 4 * FRAME_W, FRAME_H)
# The dark blue-grey every layer is outlined and shaded with.
OUTLINE = {(58, 58, 80), (70, 70, 94), (86, 89, 114)}
# LimeZu draws black hair as a blue-tinted dark grey; what it stands for is black.
BLACK_HAIR = "#1e1e24"

# Styles left out of the random pool: costumes rather than clothes or hair.
SKIP = {
    "bodies": {"05", "06", "08", "09"},  # zombie, ghost, pink, blue skin
    "outfits": {"30"},          # masked burglar
    "hairstyles": {"28", "29"},  # animal ears
}

LAYERS = {
    # kind: (folder, filename pattern with the style number as group 1 or None)
    "bodies": ("Bodies", r"Body_32x32_(\d+)"),
    "eyes": ("Eyes", None),
    "outfits": ("Outfits", r"Outfit_(\d+)_"),
    "hairstyles": ("Hairstyles", r"Hairstyle_(\d+)_"),
}


def atlas_of(sheet: Image.Image) -> Image.Image:
    """The kept rows of a layer's sheet, stacked left-aligned into one image."""
    width = max(frames * (4 if directional else 1) * FRAME_W for _, _, frames, directional in ACTIONS)
    atlas = Image.new("RGBA", (width, len(ACTIONS) * FRAME_H), (0, 0, 0, 0))
    for slot, (_, row, frames, directional) in enumerate(ACTIONS):
        columns = frames * (4 if directional else 1)
        strip = sheet.crop((0, row * FRAME_H, columns * FRAME_W, (row + 1) * FRAME_H))
        atlas.paste(strip, (0, slot * FRAME_H))
    return atlas


def action_table() -> dict[str, dict[str, object]]:
    return {
        name: {"y": slot * FRAME_H, "frames": frames, "directional": directional}
        for slot, (name, _, frames, directional) in enumerate(ACTIONS)
    }


def mean_colour(sheet: Image.Image) -> str:
    """Mean colour of the front-facing frame, ignoring outline and shadow.

    The mean, not the most common pixel: a layer's most common pixel is often
    its highlight, which makes black hair read as brown and blond as orange.
    """
    frame = sheet.crop(DOWN_STAND).convert("RGBA")
    data = frame.tobytes()
    total = [0, 0, 0]
    count = 0
    for i in range(0, len(data), 4):
        r, g, b, a = data[i], data[i + 1], data[i + 2], data[i + 3]
        if a < 200 or (r, g, b) in OUTLINE:
            continue
        total[0] += r
        total[1] += g
        total[2] += b
        count += 1
    if count == 0:
        return "#000000"
    r, g, b = (round(c / count) for c in total)
    return f"#{r:02x}{g:02x}{b:02x}"


def is_blue_tinted(colour: str) -> bool:
    r, b = int(colour[1:3], 16), int(colour[5:7], 16)
    return b > r + 12


def main() -> int:
    if not SOURCE.is_dir():
        print(f"LimeZu source not found at {SOURCE}. Extract the packs first.")
        return 1
    manifest: dict[str, object] = {"frame": [FRAME_W, FRAME_H], "actions": action_table()}
    for kind, (folder, pattern) in LAYERS.items():
        entries = []
        dest = OUT / kind
        dest.mkdir(parents=True, exist_ok=True)
        for path in sorted((SOURCE / folder / "32x32").glob("*.png")):
            if "kid" in path.name.lower():
                continue
            style = ""
            if pattern:
                match = re.search(pattern, path.name)
                if match is None:
                    continue
                style = match.group(1)
                if style in SKIP.get(kind, set()):
                    continue
            sheet = atlas_of(Image.open(path).convert("RGBA"))
            sheet.save(dest / path.name, optimize=True)
            colour = mean_colour(sheet)
            if kind == "hairstyles" and is_blue_tinted(colour):
                colour = BLACK_HAIR
            entry = {"file": f"{kind}/{path.name}", "colour": colour}
            if style and kind != "bodies":
                entry["style"] = style
            entries.append(entry)
        manifest[kind] = entries
        print(f"{kind}: {len(entries)}")
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
