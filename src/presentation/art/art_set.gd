class_name ArtSet
extends RefCounted
## Package art for the views (sw-kys.3). Templates name their art by asset ID
## (PackageLoader.ART_FIELDS): `icon` on units, squads, commanders and hex
## features, `tile` on hex features (the hex's ground), `texture` on battle
## terrain features. This keeps the lookup and a texture cache; textures load
## through PackageLoader.load_texture, never ResourceLoader, so mod packages
## can bring art without bringing code. Anything without art returns null and
## the view falls back to its colours.

const CORE := "res://data/packages/core"
## Pixels per battlefield metre (or map cell) when ground is drawn from textures.
const GROUND_PX: int = 4

static var _core: ArtSet

var _loader: PackageLoader
## "<template>|<field>" -> asset ID as written.
var _refs: Dictionary = {}
## Asset ID -> Texture2D (null cached too).
var _tex: Dictionary = {}
## Asset ID -> Image (for compositing battle terrain).
var _img: Dictionary = {}


static func from_loader(loader: PackageLoader) -> ArtSet:
	var a := ArtSet.new()
	a._loader = loader
	var t := loader.templates
	if t == null:
		return a
	for id in t.ids():
		if not PackageLoader.ART_KINDS.has(t.kind_of(id)):
			continue
		var v := t.values_of(id)
		for f in PackageLoader.ART_FIELDS:
			if v.has(f):
				a._refs["%s|%s" % [id, f]] = String(v[f])
	return a


## The core package's art, loaded once.
static func core() -> ArtSet:
	if _core == null:
		_core = from_loader(PackageLoader.load_dirs(PackedStringArray([CORE])))
	return _core


func has_art(template: String, field: String = "icon") -> bool:
	return _refs.has("%s|%s" % [template, field])


## The template's art for `field`, or null.
func texture(template: String, field: String = "icon") -> Texture2D:
	var ref: String = _refs.get("%s|%s" % [template, field], "")
	if ref.is_empty():
		return null
	if not _tex.has(ref):
		var img := image(template, field)
		_tex[ref] = ImageTexture.create_from_image(img) if img != null else null
	return _tex[ref]


## Whether the art is already cut to its shape (a transparent top-left
## corner, like a pre-drawn hex tile): drawn whole rather than clipped.
func shaped(template: String, field: String = "tile") -> bool:
	var img := image(template, field)
	return img != null and img.get_pixel(0, 0).a < 0.1


## Ground as pixels (sw-8rk), shared by the war room's battle view and the
## map editor. `cells[y * w + x]` indexes `ids` (feature template IDs) and
## `colors` (one colour per ID, parallel to `ids`); an index out of range is
## black. With a ground texture for any feature, each cell is GROUND_PX pixels
## cut from its feature's texture (tiled, nearest); a feature without one is
## a flat block of its colour. With no textures at all, a pixel a cell.
## `art` may be null (colours only).
static func ground_image(art: ArtSet, w: int, h: int, cells: PackedInt32Array, ids: PackedStringArray, colors: Array[Color]) -> Image:
	var srcs := {}
	if art != null:
		for i in ids.size():
			var src := art.image(ids[i], "texture")
			if src != null:
				srcs[i] = src
	var px := GROUND_PX if not srcs.is_empty() else 1
	var img := Image.create(maxi(w, 1) * px, maxi(h, 1) * px, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := cells[y * w + x]
			var col := colors[i] if i >= 0 and i < ids.size() else Color.BLACK
			if px == 1:
				img.set_pixel(x, y, col)
			elif srcs.has(i):
				var src: Image = srcs[i]
				var sx := (x * px) % maxi(src.get_width() - px + 1, 1)
				var sy := (y * px) % maxi(src.get_height() - px + 1, 1)
				img.blit_rect(src, Rect2i(sx, sy, px, px), Vector2i(x * px, y * px))
			else:
				img.fill_rect(Rect2i(x * px, y * px, px, px), col)
	return img


## The template's art as an Image (RGBA8), or null.
func image(template: String, field: String = "icon") -> Image:
	var ref: String = _refs.get("%s|%s" % [template, field], "")
	if ref.is_empty() or _loader == null:
		return null
	if not _img.has(ref):
		var path: String = _loader.assets.get(_loader.resolve_asset(ref), "")
		var img: Image = Image.load_from_file(path) if not path.is_empty() else null
		if img != null:
			img.convert(Image.FORMAT_RGBA8)
		_img[ref] = img
	return _img[ref]
