"""Imports the Kenney CC0 sprites the core package uses (sw-kys.4).

    python src/tools/import_kenney_art.py <hexagon-pack dir> <tiny-battle dir>

The directories are the extracted zips from kenney.nl/assets/hexagon-pack and
kenney.nl/assets/tiny-battle (both CC0). Copies the chosen hex tiles as they
are, cuts battle ground textures out of Tiny Battle's packed tilemap (muted,
per GDD 01: desaturated terrain so squads stand out), and copies each pack's
License.txt next to them. Writes under data/packages/core/art/kenney/.
"""
import os
import shutil
import sys

from PIL import Image, ImageEnhance

OUT = os.path.join("data", "packages", "core", "art", "kenney")

# asset file name -> path inside the Hexagon Pack's PNG/Tiles folder
HEX = {
    "plains": "Terrain/Grass/grass_05.png",
    "forest": "Terrain/Grass/grass_12.png",
    "hills": "Terrain/Grass/grass_14.png",
    "ore_deposit": "Terrain/Grass/grass_16.png",
    "village": "Medieval/medieval_house.png",
    "barracks": "Military/military_entrance.png",
    "depot": "Mill/mill_storage.png",
    "mine": "Medieval/medieval_mine.png",
    "shrine": "Medieval/medieval_church.png",
    "bandit_camp": "Modern/modern_campsite.png",
}

# battle ground: Tiny Battle tilemap_packed.png index (18 columns of 16 px)
# (its road and tree tiles have heavy outlines that tile badly: placeholders stay)
GROUND = {"open": 0, "water": 37}
COLUMNS = 18


def mute(img, colour=0.45, bright=0.5):
    img = ImageEnhance.Color(img).enhance(colour)
    return ImageEnhance.Brightness(img).enhance(bright)


def main(hexdir, tbdir):
    os.makedirs(os.path.join(OUT, "hex"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "ground"), exist_ok=True)
    for name, rel in HEX.items():
        img = Image.open(os.path.join(hexdir, "PNG", "Tiles", rel)).convert("RGBA")
        mute(img, 0.6, 0.75).save(os.path.join(OUT, "hex", name + ".png"))
    sheet = Image.open(os.path.join(tbdir, "Tilemap", "tilemap_packed.png")).convert("RGBA")

    def tile(i):
        x, y = (i % COLUMNS) * 16, (i // COLUMNS) * 16
        return sheet.crop((x, y, x + 16, y + 16))

    for name, i in GROUND.items():
        mute(tile(i)).save(os.path.join(OUT, "ground", name + ".png"))
    shutil.copy(os.path.join(hexdir, "License.txt"), os.path.join(OUT, "hexagon-pack-License.txt"))
    shutil.copy(os.path.join(tbdir, "License.txt"), os.path.join(OUT, "tiny-battle-License.txt"))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
