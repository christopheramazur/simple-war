class_name CvdSim
extends RefCounted
## Colour-vision simulation of a rendered Image, for the mock pipeline (sw-rlg).
## Same maths as team_palette_mock.gd: Machado et al. (2009) severity-1.0
## matrices in linear RGB; greyscale is WCAG luminance.

const VARIANTS: Array[String] = ["greyscale", "protan", "deutan"]
const PROTAN: Array = [0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998]
const DEUTAN: Array = [0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881]


## Returns a converted copy of img; the original is untouched.
static func simulate(img: Image, variant: String) -> Image:
	var out := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	var src := img.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	var m: Array = PROTAN if variant == "protan" else DEUTAN
	for y in src.get_height():
		for x in src.get_width():
			var col := src.get_pixel(x, y)
			var l := col.srgb_to_linear()
			var r: Color
			if variant == "greyscale":
				var lum := 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
				r = Color(lum, lum, lum)
			else:
				r = Color(m[0] * l.r + m[1] * l.g + m[2] * l.b,
					m[3] * l.r + m[4] * l.g + m[5] * l.b,
					m[6] * l.r + m[7] * l.g + m[8] * l.b)
			r = r.linear_to_srgb()
			out.set_pixel(x, y, Color(clampf(r.r, 0.0, 1.0), clampf(r.g, 0.0, 1.0), clampf(r.b, 0.0, 1.0), col.a))
	return out
