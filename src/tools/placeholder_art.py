"""Generates the core package's placeholder pixel art (sw-kys.3).

Original art made by this script, released CC0 with the project. Run from the
repo root:  python src/tools/placeholder_art.py
Writes PNGs under data/packages/core/art/ and prints the manifest "assets"
entries. Swap any file for real art with the same name, or point a template's
icon/tile/texture at a different asset id.
"""
import json
import os
import random

from PIL import Image

OUT = os.path.join("data", "packages", "core", "art")


def hexc(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def save(img, rel):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return rel


def grid(rows, pal):
    """An image from ASCII rows; '.' is transparent."""
    h, w = len(rows), max(len(r) for r in rows)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != "." and ch in pal:
                img.putpixel((x, y), hexc(pal[ch]))
    return img


def jitter(c, rnd, amt):
    d = rnd.randint(-amt, amt)
    return tuple(max(0, min(255, v + d)) for v in c[:3]) + (255,)


def noise_tile(size, base, rnd, amt=10, specks=(), speck_n=0):
    img = Image.new("RGBA", (size, size))
    b = hexc(base)
    for y in range(size):
        for x in range(size):
            img.putpixel((x, y), jitter(b, rnd, amt))
    for _ in range(speck_n):
        c = hexc(rnd.choice(specks))
        img.putpixel((rnd.randrange(size), rnd.randrange(size)), c)
    return img


def blob(img, cx, cy, r, col, hi=None):
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if 0 <= x < img.width and 0 <= y < img.height and (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 1:
                c = col
                if hi and (x - cx) + (y - cy) < -r // 2:
                    c = hi
                img.putpixel((x, y), hexc(c))


# --- overworld hex tiles (32x32, clipped to the hex by the view) -------------

def tiles():
    rnd = random.Random(7)
    out = {}
    out["tile_plains"] = save(noise_tile(32, "5d6b4c", rnd, 8, ["6f7f58", "4f5c40", "7a8a5e"], 60), "tiles/plains.png")
    f = noise_tile(32, "33482f", rnd, 6, ["2a3c27"], 40)
    for _ in range(9):
        x, y = rnd.randrange(3, 29), rnd.randrange(3, 29)
        blob(f, x + 1, y + 1, 4, "1e2b1c")
        blob(f, x, y, 4, "3f5a3a", "557a4c")
    out["tile_forest"] = save(f, "tiles/forest.png")
    hl = noise_tile(32, "6e6a52", rnd, 7, ["7d785e", "5e5a45"], 50)
    for cx, cy in ((9, 20), (23, 12), (22, 27)):
        for dx in range(-7, 8):
            hgt = 5 - abs(dx) * 5 // 8
            for dy in range(hgt):
                x, y = cx + dx, cy - dy
                if 0 <= x < 32 and 0 <= y < 32:
                    hl.putpixel((x, y), hexc("8a8466" if dx < 0 else "5a553f"))
    out["tile_hills"] = save(hl, "tiles/hills.png")
    w = noise_tile(32, "2d4f6e", rnd, 5)
    for _ in range(12):
        x, y = rnd.randrange(0, 28), rnd.randrange(0, 32)
        for dx in range(4):
            w.putpixel((x + dx, y), hexc("4f7896"))
    out["tile_lake"] = save(w, "tiles/lake.png")
    r = noise_tile(32, "5d6b4c", rnd, 8, ["6f7f58"], 30)
    for y in range(12, 20):
        for x in range(32):
            r.putpixel((x, y), jitter(hexc("8b8476"), rnd, 9))
    for x in range(0, 32, 4):
        r.putpixel((x, 15), hexc("a39b8a"))
    out["tile_road"] = save(r, "tiles/road.png")
    return out


# --- overworld feature icons (16x16) -----------------------------------------

FEATURES = {
    "village": (["................",
                 ".......rr.......",
                 "......rrrr......",
                 ".....rrrrrr.....",
                 "....rrrrrrrr....",
                 "...rrrrrrrrrr...",
                 "....wwwwwwww....",
                 "....wwdwwwdw....",
                 "....wwdwwwdw....",
                 "....wwwwwwww....",
                 "....wwwbbwww....",
                 "....wwwbbwww....",
                 "....wwwbbwww....",
                 "..gggggggggggg..",
                 "................",
                 "................"], {"r": "9c4a3a", "w": "d8cba8", "d": "4a6a8a", "b": "5a3e2a", "g": "3c4a30"}),
    "barracks": (["......f.........",
                  "......fff.......",
                  "......ffff......",
                  "......p.........",
                  "..tttttttttttt..",
                  ".tTTTTTTTTTTTTt.",
                  ".tttttttttttttt.",
                  ".wwwwwwwwwwwwww.",
                  ".wwdwwwwwwwwdww.",
                  ".wwwwwwbbwwwwww.",
                  ".wwwwwwbbwwwwww.",
                  ".wwwwwwbbwwwwww.",
                  ".gggggggggggggg.",
                  "................",
                  "................",
                  "................"], {"f": "c84a3a", "p": "6a5a48", "t": "4a5038", "T": "5f6648", "w": "8a8a72", "d": "2a2e2a", "b": "3a3020", "g": "3c4a30"}),
    "depot": (["................",
               "................",
               "......cccc......",
               "......cCCc......",
               "......cccc......",
               "..cccccccccc....",
               "..cCCcccCCcc....",
               "..cccccccccc....",
               "..cccccccccccccc",
               "..cCCcccCCcccCCc",
               "..cccccccccccccc",
               "..bbbbbbbbbbbbbb",
               "................",
               "................",
               "................",
               "................"], {"c": "a07a4a", "C": "6a4e2e", "b": "3c4a30"}),
    "mine": (["................",
              "................",
              "....kkkkkkkk....",
              "...kkrrrrrrkk...",
              "..kkr......rkk..",
              "..kr........rk..",
              "..kr........rk..",
              "..kr..xxxx..rk..",
              "..kr..xxxx..rk..",
              "..kr..xxxx..rk..",
              ".kkkkkkkkkkkkkk.",
              ".kssssssssssssk.",
              "................",
              "................",
              "................",
              "................"], {"k": "5a5550", "r": "7a5a3a", "x": "141414", "s": "8a857c"}),
    "ore_deposit": (["................",
                     "................",
                     "................",
                     "......kkk.......",
                     ".....kkKkk......",
                     "....kkoKkkk.....",
                     "...kkkkkkokk....",
                     "..kkKkkokkkkk...",
                     "..kkkkkkkkKkk...",
                     ".kkokkKkkkkkok..",
                     ".kkkkkkkkkkkkk..",
                     "................",
                     "................",
                     "................",
                     "................",
                     "................"], {"k": "6a6560", "K": "8a857c", "o": "e0b040"}),
    "supply_cache": (["................",
                      "................",
                      "................",
                      "................",
                      "...cccccccccc...",
                      "...cyyyyyyyyc...",
                      "...cccccccccc...",
                      "...cCcccccCcc...",
                      "...ccCcccCccc...",
                      "...cccCcCcccc...",
                      "...ccCcccCccc...",
                      "...cCcccccCcc...",
                      "...cccccccccc...",
                      "................",
                      "................",
                      "................"], {"c": "a07a4a", "C": "6a4e2e", "y": "e0c050"}),
    "arms_cache": (["................",
                    "................",
                    "................",
                    "................",
                    "..kkkkkkkkkkkk..",
                    "..kOOOOOOOOOOk..",
                    "..kkkkkkkkkkkk..",
                    "..kOOOOOOOOOOk..",
                    "..kOggggggggOk..",
                    "..kOOOOOOOggOk..",
                    "..kOOOOOOOOOOk..",
                    "..kkkkkkkkkkkk..",
                    "................",
                    "................",
                    "................",
                    "................"], {"k": "3a4030", "O": "56603e", "g": "1a1a1a"}),
    "shrine": (["................",
                ".......yy.......",
                "......y..y......",
                ".......yy.......",
                "......ssss......",
                "......sSss......",
                "......sSss......",
                "......sSss......",
                "......sSss......",
                "......sSss......",
                ".....ssssss.....",
                "....ssssssss....",
                "...gggggggggg...",
                "................",
                "................",
                "................"], {"y": "f0e090", "s": "a8a0b8", "S": "c8c0d8", "g": "3c4a30"}),
    "bandit_camp": (["................",
                     "................",
                     "......k.........",
                     ".....kkk........",
                     "....kkTkk.......",
                     "...kkTTTkk......",
                     "..kkTTTTTkk.....",
                     ".kkkkxxkkkkk....",
                     ".kkkkxxkkkkk....",
                     "..........o.....",
                     ".........oyo....",
                     "........oyryo...",
                     "........bbbbb...",
                     "................",
                     "................",
                     "................"], {"k": "6a3a32", "T": "8a4a3e", "x": "1a1210", "o": "e07030", "y": "f0c040", "r": "c03020", "b": "4a3020"}),
    "angel_host": (["................",
                    "......yyyy......",
                    ".....y....y.....",
                    "......yyyy......",
                    ".ww....ff....ww.",
                    ".www..ffff..www.",
                    "..wwwwffffwwww..",
                    "...wwwffffwww...",
                    "....wwffffww....",
                    "......ffff......",
                    "......ffff......",
                    ".....ffffff.....",
                    "................",
                    "................",
                    "................",
                    "................"], {"y": "f0e090", "w": "e8e4f4", "f": "c8c0e0"}),
}


def features():
    return {"icon_" + k: save(grid(rows, pal), "features/%s.png" % k) for k, (rows, pal) in FEATURES.items()}


# --- soldiers and commanders (16x16, front facing) ---------------------------

BODY = ["................",
        "......hhhh......",
        ".....hhhhhh.....",
        ".....hssssh.....",
        ".....sesses.....",
        "......ssss......",
        "....uuuuuuuu....",
        "...uuuuuuuuuu...",
        "...suuuuuuuus...",
        "...s.uuuuuu.s...",
        ".....uuuuuu.....",
        ".....bbbbbb.....",
        ".....pp..pp.....",
        ".....pp..pp.....",
        ".....kk..kk.....",
        "................"]

# weapon overlays: list of (x, y) pixels in dark gunmetal, plus optional extra colours
WEAPONS = {
    "rifle": [(x, 12 - (x - 2) // 2) for x in range(2, 14)],
    "carbine": [(x, 11 - (x - 4) // 2) for x in range(4, 12)],
    "lmg": [(x, 9) for x in range(1, 15)] + [(x, 10) for x in range(3, 13)] + [(5, 11), (6, 12)],
    "marksman": [(x, 13 - (x - 1) // 2) for x in range(1, 16)] + [(8, 8), (9, 8)],
    "rocket": [(x, 5) for x in range(0, 13)] + [(x, 6) for x in range(0, 13)],
    "shotgun": [(x, 10) for x in range(4, 12)] + [(x, 11) for x in range(4, 10)],
    "mortar": [(12, y) for y in range(4, 14)] + [(13, y) for y in range(4, 14)] + [(11, 13), (14, 13)],
}

SOLDIERS = {
    # id: (helmet, uniform, weapon, extra)
    "trooper": ("4a5838", "5f6e48", "rifle", None),
    "sergeant": ("4a5838", "5f6e48", "rifle", "chevron"),
    "gunner": ("3e4a30", "56603e", "lmg", None),
    "marksman": ("6a6448", "746c4c", "marksman", "hood"),
    "rocketeer": ("4a5838", "5f6e48", "rocket", None),
    "scout": ("5a6a4a", "6a7a54", "carbine", "hood"),
    "chi_operative": ("2e3440", "444c5c", "rifle", "visor"),
    "breacher": ("3a3e44", "50565e", "shotgun", "visor"),
    "engineer": ("c8a030", "6a6a50", "carbine", None),
    "mortarman": ("4a5838", "5f6e48", "mortar", None),
}


def soldier(helmet, uniform, weapon, extra):
    pal = {"h": helmet, "s": "d0a888", "e": "202020", "u": uniform, "b": "3a3020", "p": "4a4a3a", "k": "2a2420"}
    img = grid(BODY, pal)
    gun = hexc("2a2a2e")
    for x, y in WEAPONS[weapon]:
        if 0 <= x < 16 and 0 <= y < 16:
            img.putpixel((x, y), gun)
    if weapon == "rocket":
        img.putpixel((0, 5), hexc("c06030"))
        img.putpixel((0, 6), hexc("c06030"))
    if extra == "chevron":
        for x, y in ((5, 8), (6, 9), (7, 8)):
            img.putpixel((x, y), hexc("e0c050"))
    if extra == "visor":
        for x in range(5, 11):
            img.putpixel((x, 4), hexc("60c0e0"))
    if extra == "hood":
        for x, y in ((4, 2), (11, 2), (4, 3), (11, 3), (4, 4), (11, 4)):
            img.putpixel((x, y), hexc(helmet))
    return img


COMMANDERS = {
    "field_commander": ("2e3a26", "4a5a3a", "e0c050"),
    "outrider": ("5a4a32", "6a5a3e", "c8c8c8"),
    "siege_captain": ("3a3e44", "50565e", "e07030"),
}

OFFICER = ["................",
           ".....cccccc.....",
           "....cccccccc....",
           "....ttttttttt...",
           ".....ssssss.....",
           ".....sesses.....",
           "......ssss......",
           "...uuuuuuuuuu...",
           "..uuuummuuuuuu..",
           "..uuuummuuuuuu..",
           "..suuuuuuuuuus..",
           "....uuuuuuuu....",
           ".....bbbbbb.....",
           ".....pp..pp.....",
           ".....kk..kk.....",
           "................"]


def units():
    out = {}
    for k, v in SOLDIERS.items():
        out["unit_" + k] = save(soldier(*v), "units/%s.png" % k)
    for k, (cap, uni, trim) in COMMANDERS.items():
        pal = {"c": cap, "t": trim, "s": "d0a888", "e": "202020", "u": uni, "m": trim, "b": "3a3020", "p": "3a3a30", "k": "2a2420"}
        out["commander_" + k] = save(grid(OFFICER, pal), "commanders/%s.png" % k)
    return out


# --- battle terrain textures (16x16, muted so squads stand out) ---------------

def terrain():
    rnd = random.Random(11)
    out = {}
    out["ground_open"] = save(noise_tile(16, "2f362d", rnd, 5, ["384034", "283026"], 18), "terrain/open.png")
    out["ground_road"] = save(noise_tile(16, "4a4840", rnd, 6, ["55534a", "3e3c36"], 14), "terrain/road.png")
    f = noise_tile(16, "223527", rnd, 5, ["1a2a1e"], 10)
    blob(f, 5, 5, 3, "2c4430", "35503a")
    blob(f, 12, 11, 3, "2c4430", "35503a")
    out["ground_forest"] = save(f, "terrain/forest.png")
    r = noise_tile(16, "3d3a3a", rnd, 6, ["4a4646", "302e2e"], 16)
    for x0, y0 in ((2, 3), (9, 10)):
        for x in range(x0, x0 + 4):
            r.putpixel((x, y0), hexc("57524e"))
    out["ground_ruins"] = save(r, "terrain/ruins.png")
    wl = noise_tile(16, "8a857c", rnd, 4)
    for y in (3, 7, 11, 15):
        for x in range(16):
            wl.putpixel((x, y), hexc("6a665e"))
    out["ground_wall"] = save(wl, "terrain/wall.png")
    w = noise_tile(16, "1f3a4d", rnd, 4)
    for x0, y0 in ((2, 4), (8, 11)):
        for x in range(x0, x0 + 4):
            w.putpixel((x, y0), hexc("2e5068"))
    out["ground_water"] = save(w, "terrain/water.png")
    return out


if __name__ == "__main__":
    assets = {}
    for part in (tiles, features, units, terrain):
        assets.update({k: "art/" + v.replace(os.sep, "/") for k, v in part().items()})
    print(json.dumps(assets, indent="\t", sort_keys=True))
