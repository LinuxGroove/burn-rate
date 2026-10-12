class_name BurnTheme
extends RefCounted
## Burn Rate's own look: Kestrel Lift's brand, orange on midnight, with
## slanted panels and buttons, wide-spaced capitals and a cyan second colour.
## Built on the shared theme (so every shared panel, cycler and keyboard
## follows it) and applied once at startup by main.gd.
##
## Everything here is sized for a 7-inch handheld first: buttons are tall,
## text is never under 18 px at 720p, and focus is a solid orange fill that
## reads from the couch.

const MIDNIGHT := Color("0a0d1a")
const NIGHT := Color("121730")
const PANEL := Color(0.035, 0.045, 0.1, 0.88)
const PANEL_LIGHT := Color(0.09, 0.11, 0.21, 0.92)
const ORANGE := Color("ff7a1a")
const ORANGE_HOT := Color("ffb347")
const CYAN := Color("3fe0ff")
const MAGENTA := Color("ff3d9a")
const GOLD := Color("ffc83d")
const GREEN := Color("5dffa0")
const RED := Color("ff3b4e")
const TEXT := Color("eef2ff")
const DIM := Color("8a93b8")
const LINE := Color(0.55, 0.62, 0.9, 0.22)
## Burn levels x1 to x5.
const BURN := [Color("dfe6ff"), Color("ffd23f"), Color("ff8a1f"), Color("ff3b4e"), Color("ff3dd0")]
## How far the panels and buttons lean.
const SLANT := 0.18

const FONT_PATH := "res://addons/linuxgroove/ui/fonts/Kenney Future.ttf"
const NARROW_PATH := "res://addons/linuxgroove/ui/fonts/Kenney Future Narrow.ttf"

static var _fonts := {}


## Builds the theme on top of the shared one and makes it the default
## everywhere, as LGTheme.apply does.
static func apply(root: Window, base_size := 22) -> Theme:
	var t := build(base_size)
	root.theme = t
	ThemeDB.get_default_theme().merge_with(t)
	ThemeDB.get_default_theme().default_font = t.default_font
	ThemeDB.get_default_theme().default_font_size = t.default_font_size
	return t


static func build(base_size := 22) -> Theme:
	var t := LGTheme.build(base_size)
	var head := heading()
	var body := narrow()
	t.default_font = body
	t.default_font_size = base_size

	# Labels.
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 4)
	t.set_font("font", "HeaderLarge", spaced(head, 4))
	t.set_color("font_color", "HeaderLarge", TEXT)
	t.set_font("font", "HeaderMedium", spaced(head, 3))
	t.set_color("font_color", "HeaderMedium", ORANGE)
	t.set_color("font_color", "HintLabel", Color(DIM, 1.0).lightened(0.25))
	t.set_type_variation("CapsLabel", "Label")
	t.set_font("font", "CapsLabel", spaced(head, 3))
	t.set_font_size("font_size", "CapsLabel", int(base_size * 0.8))
	t.set_color("font_color", "CapsLabel", CYAN)
	t.set_type_variation("BigNumber", "Label")
	t.set_font("font", "BigNumber", spaced(head, 2))
	t.set_font_size("font_size", "BigNumber", int(base_size * 2.4))
	t.set_color("font_color", "BigNumber", TEXT)
	for ink in ["InkLabel", "InkHeader", "InkTitle"]:
		t.set_color("font_color", ink, TEXT)

	# Buttons: slanted midnight slabs with an orange edge; focus fills them.
	var normal := slab(PANEL_LIGHT, ORANGE.darkened(0.25), 0, 6)
	var hover := slab(PANEL_LIGHT.lightened(0.08), ORANGE, 0, 6)
	var pressed := slab(ORANGE.darkened(0.2), ORANGE_HOT, 0, 6)
	var focus := slab(ORANGE, ORANGE_HOT, 2, 6)
	focus.shadow_color = Color(ORANGE, 0.55)
	focus.shadow_size = 14
	var disabled := slab(Color(0.08, 0.09, 0.15, 0.7), Color(DIM, 0.35), 0, 6)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_font("font", type, spaced(head, 2))
		t.set_font_size("font_size", type, base_size)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, MIDNIGHT)
		t.set_color("font_hover_pressed_color", type, MIDNIGHT)
		t.set_color("font_pressed_color", type, MIDNIGHT)
		t.set_color("font_disabled_color", type, Color(DIM, 0.6))
		t.set_constant("outline_size", type, 0)
	# A focused button is filled, so focus text stays dark even when hovered.
	t.set_type_variation("DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", slab(Color(0.2, 0.04, 0.08, 0.9), RED, 0, 6))
	var dfocus := slab(RED, Color("ff8090"), 2, 6)
	dfocus.shadow_color = Color(RED, 0.5)
	dfocus.shadow_size = 14
	t.set_stylebox("focus", "DangerButton", dfocus)
	for c in ["font_color", "font_hover_color"]:
		t.set_color(c, "DangerButton", Color("ffd6db"))
	t.set_color("font_focus_color", "DangerButton", Color.WHITE)
	# The big one: Fly, Fly again.
	t.set_type_variation("HeroButton", "Button")
	var hero := slab(ORANGE.darkened(0.35), ORANGE_HOT, 0, 8)
	hero.set_content_margin_all(18)
	t.set_stylebox("normal", "HeroButton", hero)
	var hero_focus := slab(ORANGE, Color("ffe0b0"), 3, 8)
	hero_focus.shadow_color = Color(ORANGE, 0.7)
	hero_focus.shadow_size = 22
	hero_focus.set_content_margin_all(18)
	t.set_stylebox("focus", "HeroButton", hero_focus)
	t.set_font_size("font_size", "HeroButton", int(base_size * 1.45))
	# Tiles in pickers (prototypes, suits, courses): flatter, and they keep
	# their own colours.
	t.set_type_variation("TileButton", "Button")
	var tile := slab(Color(0.06, 0.08, 0.16, 0.92), LINE, 0, 2)
	tile.set_border_width_all(2)
	t.set_stylebox("normal", "TileButton", tile)
	var tile_hover := tile.duplicate() as StyleBoxFlat
	tile_hover.border_color = ORANGE
	t.set_stylebox("hover", "TileButton", tile_hover)
	var tile_focus := slab(Color(0.14, 0.09, 0.07, 0.95), ORANGE, 0, 4)
	tile_focus.set_border_width_all(4)
	tile_focus.shadow_color = Color(ORANGE, 0.45)
	tile_focus.shadow_size = 12
	t.set_stylebox("focus", "TileButton", tile_focus)
	t.set_color("font_focus_color", "TileButton", Color.WHITE)
	t.set_color("font_pressed_color", "TileButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "TileButton", Color.WHITE)
	t.set_font_size("font_size", "TileButton", int(base_size * 0.82))
	t.set_font("font", "TileButton", spaced(head, 1))

	# Panels.
	var panel := slab(PANEL, LINE, 0, 0)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(20)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var dark := slab(Color(0.02, 0.025, 0.06, 0.94), Color(ORANGE, 0.5), 0, 0)
	dark.border_width_top = 3
	dark.set_content_margin_all(24)
	t.set_stylebox("panel", "DarkPanel", dark)
	var glass := flat(Color(0.03, 0.04, 0.09, 0.72), Color(CYAN, 0.18), 1)
	glass.set_content_margin_all(14)
	t.set_stylebox("panel", "GlassPanel", glass)
	t.set_stylebox("panel", "ParchmentPanel", dark)
	t.set_type_variation("HudPanel", "PanelContainer")
	var hud := flat(Color(0.02, 0.03, 0.07, 0.62), Color(CYAN, 0.16), 1)
	hud.set_content_margin_all(12)
	hud.content_margin_left = 20
	hud.border_width_left = 4
	hud.border_color = Color(ORANGE, 0.8)
	hud.border_width_top = 0
	hud.border_width_right = 0
	hud.border_width_bottom = 0
	hud.content_margin_right = 18
	hud.skew = Vector2(-SLANT * 0.6, 0)
	t.set_stylebox("panel", "HudPanel", hud)

	# Text entry.
	var edit := flat(Color(0.02, 0.03, 0.07, 0.95), Color(CYAN, 0.4), 2)
	edit.set_content_margin_all(12)
	t.set_stylebox("normal", "LineEdit", edit)
	var edit_focus := flat(Color(0.03, 0.04, 0.1, 0.95), ORANGE, 3)
	edit_focus.set_content_margin_all(12)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ORANGE)
	t.set_color("font_placeholder_color", "LineEdit", Color(DIM, 0.8))

	# Bars.
	var bar_bg := flat(Color(0, 0, 0, 0.45), Color(LINE, 0.4), 1)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", flat(ORANGE, Color(0, 0, 0, 0), 0))
	t.set_stylebox("fill", "BlueProgressBar", flat(CYAN, Color(0, 0, 0, 0), 0))
	t.set_stylebox("fill", "RedProgressBar", flat(RED, Color(0, 0, 0, 0), 0))

	# Scroll bars and lists.
	var grab := flat(Color(ORANGE, 0.75), Color(0, 0, 0, 0), 0)
	grab.set_corner_radius_all(3)
	for s in ["grabber", "grabber_highlight", "grabber_pressed"]:
		t.set_stylebox(s, "VScrollBar", grab)
	var track := flat(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0)
	track.set_corner_radius_all(3)
	t.set_stylebox("scroll", "VScrollBar", track)
	var sel := flat(Color(ORANGE, 0.35), Color(0, 0, 0, 0), 0)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font("bold_font", "RichTextLabel", head)
	t.set_color("font_color", "CheckBox", TEXT)
	return t


## A slanted slab with a thick left edge in `edge`.
static func slab(bg: Color, edge: Color, border := 0, left := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border)
	s.border_width_left = maxi(left, border)
	s.skew = Vector2(SLANT, 0)
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	return s


## Gives `c` the focus at the end of the frame, if it's still on screen by
## then (a page can be swapped again before it).
static func focus(c: Control) -> void:
	_grab.call_deferred(c)


static func _grab(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()


## A plain box with a thin border.
static func flat(bg: Color, edge: Color, border := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border)
	s.set_corner_radius_all(2)
	s.anti_aliasing = true
	return s


static func heading() -> Font:
	return _font(FONT_PATH)


static func narrow() -> Font:
	return _font(NARROW_PATH)


static func _font(path: String) -> Font:
	if not _fonts.has(path):
		_fonts[path] = load(path)
	return _fonts[path]


## The font with extra space between letters, for the brand's capitals.
static func spaced(base: Font, px: int) -> Font:
	var key := "%s/%d" % [base.resource_path, px]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = base
		f.spacing_glyph = px
		_fonts[key] = f
	return _fonts[key]


## The font leaning forward, for the logo and big call-outs.
static func italic(base: Font, px := 2) -> Font:
	var key := "%s/i%d" % [base.resource_path, px]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = base
		f.spacing_glyph = px
		f.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
		_fonts[key] = f
	return _fonts[key]


## A label in the brand's style.
static func label(text: String, size := 22, color := TEXT, font: Font = null, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else spaced(heading(), 2))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The Burn level's colour (1 to 5).
static func burn_color(level: int) -> Color:
	return BURN[clampi(level, 1, 5) - 1]


## The game's logo: BURN in white, RATE in orange, leaning forward, with a
## burner streak under it.
static func logo(size := 96) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(size * 0.02))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(size * 0.28))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var f := italic(heading(), int(size * 0.06))
	var burn := label("BURN", size, TEXT, f, int(size * 0.12))
	row.add_child(burn)
	var rate := label("RATE", size, ORANGE, f, int(size * 0.12))
	rate.add_theme_color_override("font_outline_color", Color(0.25, 0.06, 0.0, 0.95))
	row.add_child(rate)
	var streak := Streak.new()
	streak.custom_minimum_size = Vector2(size * 5.2, size * 0.16)
	box.add_child(streak)
	var tag := label("A KESTREL LIFT PROTOTYPE", int(size * 0.2), CYAN, spaced(heading(), int(size * 0.07)), 4)
	box.add_child(tag)
	return box


## The burner streak under the logo: a bar that fades from white-hot to
## orange to nothing.
class Streak:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cols := PackedColorArray([Color(1, 0.95, 0.85), BurnTheme.ORANGE_HOT, BurnTheme.ORANGE, Color(BurnTheme.ORANGE, 0.0)])
		var stops := [0.0, 0.12, 0.45, 1.0]
		for i in 3:
			var x0: float = w * stops[i]
			var x1: float = w * stops[i + 1]
			var pts := PackedVector2Array([Vector2(x0 + h * 0.4, 0), Vector2(x1 + h * 0.4, 0), Vector2(x1, h), Vector2(x0, h)])
			draw_polygon(pts, PackedColorArray([cols[i], cols[i + 1], cols[i + 1], cols[i]]))
