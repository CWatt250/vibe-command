extends RefCounted
class_name UiTheme
## UiTheme — one place for the HUD's look (visual-roadmap V7). Dark glass panels with a
## faction-coloured hairline; buttons that read as chips. Applied per-control with
## add_theme_*_override so the panels stay code-built like the rest of presentation/.

const FACTION_COLORS := {
	"VC": Color(0.0, 0.82, 1.0),
	"FC": Color(0.95, 0.75, 0.15),
}
const GLASS := Color(0.05, 0.06, 0.08, 0.86)
const GLASS_LIGHT := Color(0.12, 0.14, 0.18, 0.9)
const GLASS_HOVER := Color(0.18, 0.21, 0.27, 0.95)
const TEXT := Color(0.92, 0.94, 0.96)
const TEXT_DIM := Color(0.55, 0.58, 0.64)
const WARN := Color(1.0, 0.45, 0.35)

static func accent(faction: String) -> Color:
	return FACTION_COLORS.get(faction, Color.WHITE)

static func panel(faction: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GLASS
	sb.border_color = Color(accent(faction), 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	return sb

static func chip(faction: String) -> StyleBoxFlat:
	var sb := panel(faction)
	sb.bg_color = GLASS_LIGHT
	sb.set_content_margin_all(0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb

static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(4)
	return sb

## Chip-style button: dim glass, accent hairline on hover, dimmed when disabled.
static func style_button(b: Button, faction: String) -> void:
	var acc := accent(faction)
	b.add_theme_stylebox_override("normal", _button_box(GLASS_LIGHT, Color(acc, 0.25)))
	b.add_theme_stylebox_override("hover", _button_box(GLASS_HOVER, Color(acc, 0.9)))
	b.add_theme_stylebox_override("pressed", _button_box(Color(acc, 0.35), acc))
	b.add_theme_stylebox_override("disabled", _button_box(Color(GLASS_LIGHT, 0.5), Color(acc, 0.08)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.add_theme_font_size_override("font_size", 12)

## Sprite icon for a content id, cropped to its opaque region. Null if no sprite.
static func icon_for(def_id: String) -> Texture2D:
	var tex := SpriteAtlas.texture(def_id)
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = SpriteAtlas.region(def_id)
	return at

static func money(v: float) -> String:
	var n := int(v)
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
