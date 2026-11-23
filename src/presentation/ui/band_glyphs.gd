class_name BandGlyphs
extends RefCounted
## Single source of the SIMPL band glyphs (sw-7kr): the squad card and the
## battle glance summary (EventText) both read from here, so a band reads the
## same wherever it appears (GDD 01 pillar 3: never colour alone). Placeholders
## until art direction decides (README Open topic 3); shapes stay distinct from
## the pool icons. A "band_icon.<id>" translation key overrides.

const ICONS: Dictionary = {
	"broken": "×", "fraying": "▽", "neutral": "◇", "primed": "△", "surging": "▲",
}


static func icon(band: String, fallback: String = "·") -> String:
	var key := "band_icon." + band
	var s := String(TranslationServer.translate(key))
	return s if s != key else String(ICONS.get(band, fallback))
