extends SceneTree
## One-shot generator for the tank's UI theme.
## Run: godot --headless --script res://tools/generate_theme.gd
##
## A Theme is written here rather than hand-authored as a .tres for the same reason the
## species resources are: a StyleBoxFlat serialises to two dozen opaque keys, and an
## exported array of them cannot be hand-written at all. Editing this file and re-running
## it is the supported way to change how the app looks.
##
## The palette is the app icon's, deliberately: the icon draws deep water and one orange
## clownfish, so the controls are deep water and the accent is that fish. Every surface
## is translucent — the tank is the content, and an opaque bar over it would be a chrome
## app with an aquarium inside rather than an aquarium with controls floating on it.

# === Palette ===
const WATER_DEEP := Color(0.039, 0.125, 0.204)   # #0a2034, the icon's top water
const ACCENT := Color(0.941, 0.471, 0.133)       # #f07822, the clownfish
const TEXT := Color(0.918, 0.949, 0.969)
const TEXT_DIM := Color(0.624, 0.714, 0.776)
const DANGER := Color(0.914, 0.388, 0.361)

# Glass: the tank showing through every surface. Alpha, not a lighter blue — the
# backdrop is not a flat colour, and a matched opaque navy separates from it the moment
# the camera pans over a plant.
const GLASS := Color(0.039, 0.125, 0.204, 0.76)
const GLASS_DEEP := Color(0.031, 0.094, 0.157, 0.92)
const EDGE := Color(1.0, 1.0, 1.0, 0.11)
const LIFT := Color(1.0, 1.0, 1.0, 0.07)         # a pressed/hover wash over glass

# === Metrics ===
## Units per point. The project lays out in a 720-unit-wide viewport and ships to a
## phone about 400 points wide, so one unit is a bit over half a point.
##
## This is not a detail. Sizing the controls as though a unit were a pixel produced
## 48-unit buttons, which measured 27 points across on an iPhone 17 Pro — every control
## in the app was around 60% of the size it looked in a desktop window, and the body
## font came out under 10 points. Everything a finger or an eye deals with is written
## below in POINTS and converted, so the numbers can be checked against a human-factors
## guideline instead of against a screenshot.
const UNITS_PER_POINT: float = 1.8

## Minimum side of anything a finger has to hit, in points. Apple's guideline is 44 and
## Google's is 48dp; this is the smaller of the two, and nothing is allowed under it.
const TOUCH: int = int(44 * UNITS_PER_POINT)
const RADIUS: int = int(12 * UNITS_PER_POINT)
const FONT_BODY: int = int(15 * UNITS_PER_POINT)
const FONT_SMALL: int = int(12 * UNITS_PER_POINT)
const FONT_TITLE: int = int(20 * UNITS_PER_POINT)

## Points -> units, for the paddings and gaps that are not worth their own constant.
static func pt(points: float) -> int:
	return int(round(points * UNITS_PER_POINT))

func _initialize() -> void:
	var theme := Theme.new()
	theme.default_font_size = FONT_BODY

	_label(theme)
	_button(theme)
	_icon_button(theme)
	_picker_tile(theme)
	_panels(theme)
	_dialogs(theme)
	_misc(theme)

	var path := "res://resources/ui/aquarium_theme.tres"
	DirAccess.make_dir_recursive_absolute("res://resources/ui")
	print("theme -> %s (err %d)" % [path, ResourceSaver.save(theme, path)])
	quit()

## A StyleBoxFlat with one hairline border. Every surface in the app is this shape, so
## the rounding and the edge are set in one place.
func _box(bg: Color, radius: int = RADIUS, border: Color = EDGE, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.set_border_width_all(width)
	box.border_color = border
	box.set_content_margin_all(pt(7))
	return box

func _label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT)
	theme.set_font_size("font_size", "Label", FONT_BODY)

	theme.set_type_variation("Caption", "Label")
	theme.set_color("font_color", "Caption", TEXT_DIM)
	theme.set_font_size("font_size", "Caption", FONT_SMALL)

	theme.set_type_variation("Title", "Label")
	theme.set_color("font_color", "Title", TEXT)
	theme.set_font_size("font_size", "Title", FONT_TITLE)

func _button(theme: Theme) -> void:
	var normal := _box(GLASS)
	normal.content_margin_left = pt(14)
	normal.content_margin_right = pt(14)
	normal.content_margin_top = pt(9)
	normal.content_margin_bottom = pt(9)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = GLASS.blend(LIFT)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = ACCENT
	pressed.border_color = ACCENT

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(GLASS.r, GLASS.g, GLASS.b, 0.45)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", WATER_DEEP)
	theme.set_color("font_hover_pressed_color", "Button", WATER_DEEP)
	theme.set_color("font_disabled_color", "Button", Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.5))
	theme.set_font_size("font_size", "Button", FONT_BODY)
	theme.set_constant("h_separation", "Button", pt(6))

	# The tank you are in. A solid accent fill is what a Button's pressed state is for —
	# a momentary press — and leaving it lit turned a quiet card into a traffic light.
	# Tinted, bordered and accent-lettered says "this one" at the same glance.
	theme.set_type_variation("RowButton", "Button")
	var selected := normal.duplicate() as StyleBoxFlat
	selected.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16)
	selected.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.70)
	theme.set_stylebox("pressed", "RowButton", selected)
	theme.set_stylebox("hover_pressed", "RowButton", selected)
	theme.set_color("font_pressed_color", "RowButton", ACCENT)
	theme.set_color("font_hover_pressed_color", "RowButton", ACCENT)

	# Secondary actions sitting beside a name that must stay readable. Narrower, not
	# shorter: the height is what a thumb has to hit, and it stays at TOUCH.
	theme.set_type_variation("SmallButton", "Button")
	var small := normal.duplicate() as StyleBoxFlat
	small.content_margin_left = pt(9)
	small.content_margin_right = pt(9)
	theme.set_stylebox("normal", "SmallButton", small)
	var small_hover := small.duplicate() as StyleBoxFlat
	small_hover.bg_color = GLASS.blend(LIFT)
	theme.set_stylebox("hover", "SmallButton", small_hover)
	theme.set_font_size("font_size", "SmallButton", FONT_SMALL)

	# A destructive row button reads as destructive before it is pressed, not after.
	theme.set_type_variation("DangerButton", "Button")
	var danger := normal.duplicate() as StyleBoxFlat
	danger.bg_color = Color(DANGER.r, DANGER.g, DANGER.b, 0.18)
	danger.border_color = Color(DANGER.r, DANGER.g, DANGER.b, 0.55)
	theme.set_stylebox("normal", "DangerButton", danger)
	var danger_hover := danger.duplicate() as StyleBoxFlat
	danger_hover.bg_color = Color(DANGER.r, DANGER.g, DANGER.b, 0.30)
	theme.set_stylebox("hover", "DangerButton", danger_hover)
	danger.content_margin_left = pt(9)
	danger.content_margin_right = pt(9)
	theme.set_font_size("font_size", "DangerButton", FONT_SMALL)
	theme.set_color("font_color", "DangerButton", DANGER)
	theme.set_color("font_hover_color", "DangerButton", TEXT)

## Round, icon-only, TOUCH across. Square content margins are what keep it circular:
## the radius is half the side, so any horizontal padding would make it a pill.
func _icon_button(theme: Theme) -> void:
	theme.set_type_variation("IconButton", "Button")
	var normal := _box(GLASS, TOUCH / 2)
	normal.set_content_margin_all(pt(11))
	theme.set_stylebox("normal", "IconButton", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = GLASS.blend(LIFT)
	theme.set_stylebox("hover", "IconButton", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = ACCENT
	pressed.border_color = ACCENT
	theme.set_stylebox("pressed", "IconButton", pressed)
	theme.set_stylebox("focus", "IconButton", StyleBoxEmpty.new())
	# Without this the glyph draws at its own 96px and the button becomes 120px across.
	theme.set_constant("icon_max_width", "IconButton", pt(20))
	theme.set_color("icon_normal_color", "IconButton", TEXT)
	theme.set_color("icon_hover_color", "IconButton", TEXT)
	theme.set_color("icon_pressed_color", "IconButton", WATER_DEEP)

## The picker's tiles: art above a name, and a selected state that is unmistakable at
## arm's length. Selection used to be the default theme's pressed shade against its
## normal shade, which differ by about 8% brightness — on a phone in daylight the armed
## species was a guess.
func _picker_tile(theme: Theme) -> void:
	theme.set_type_variation("PickerTile", "Button")
	var normal := _box(Color(1.0, 1.0, 1.0, 0.05), pt(10), Color(1.0, 1.0, 1.0, 0.08))
	normal.content_margin_left = pt(5)
	normal.content_margin_right = pt(5)
	normal.content_margin_top = pt(7)
	normal.content_margin_bottom = pt(5)
	theme.set_stylebox("normal", "PickerTile", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.11)
	theme.set_stylebox("hover", "PickerTile", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.26)
	pressed.border_color = ACCENT
	pressed.set_border_width_all(2)
	theme.set_stylebox("pressed", "PickerTile", pressed)
	theme.set_stylebox("hover_pressed", "PickerTile", pressed)
	theme.set_stylebox("focus", "PickerTile", StyleBoxEmpty.new())

	theme.set_color("font_color", "PickerTile", TEXT_DIM)
	theme.set_color("font_hover_color", "PickerTile", TEXT)
	theme.set_color("font_pressed_color", "PickerTile", TEXT)
	theme.set_color("font_hover_pressed_color", "PickerTile", TEXT)
	theme.set_font_size("font_size", "PickerTile", FONT_SMALL)
	theme.set_constant("h_separation", "PickerTile", 0)

func _panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", _box(GLASS))

	# The bottom bar. Square-bottomed and edgeless along the screen edge so it reads as
	# attached to it rather than as a floating card that has slipped off.
	theme.set_type_variation("Dock", "PanelContainer")
	var dock := _box(GLASS_DEEP, RADIUS)
	dock.corner_radius_bottom_left = 0
	dock.corner_radius_bottom_right = 0
	dock.content_margin_left = pt(8)
	dock.content_margin_right = pt(8)
	dock.content_margin_top = pt(7)
	dock.content_margin_bottom = pt(7)
	theme.set_stylebox("panel", "Dock", dock)

	# The population readout: a pill, sized by its contents.
	theme.set_type_variation("Chip", "PanelContainer")
	var chip := _box(GLASS, TOUCH / 2)
	chip.content_margin_left = pt(12)
	chip.content_margin_right = pt(14)
	chip.content_margin_top = pt(7)
	chip.content_margin_bottom = pt(7)
	theme.set_stylebox("panel", "Chip", chip)

	# The tank switcher's card: opaque enough to read a list against moving fish.
	theme.set_type_variation("Sheet", "PanelContainer")
	var sheet := _box(GLASS_DEEP, pt(18), Color(1.0, 1.0, 1.0, 0.16))
	sheet.set_content_margin_all(pt(16))
	sheet.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	sheet.shadow_size = pt(14)
	theme.set_stylebox("panel", "Sheet", sheet)

	# One saved tank's row inside that card.
	theme.set_type_variation("Row", "PanelContainer")
	var row := _box(Color(1.0, 1.0, 1.0, 0.05), pt(10), Color(1.0, 1.0, 1.0, 0.07))
	row.set_content_margin_all(pt(7))
	theme.set_stylebox("panel", "Row", row)

func _dialogs(theme: Theme) -> void:
	# Confirm and rename are AcceptDialog windows, which draw with the *default* theme
	# unless the panel style is set here: skipping this leaves two grey editor-looking
	# boxes in an app that has none anywhere else.
	var panel := _box(GLASS_DEEP, pt(16), Color(1.0, 1.0, 1.0, 0.16))
	panel.set_content_margin_all(pt(14))
	theme.set_stylebox("panel", "AcceptDialog", panel)
	theme.set_color("font_color", "AcceptDialog", TEXT)
	theme.set_constant("buttons_separation", "AcceptDialog", pt(8))

	var field := _box(Color(0.0, 0.0, 0.0, 0.30), pt(9), Color(1.0, 1.0, 1.0, 0.14))
	field.content_margin_left = pt(10)
	field.content_margin_right = pt(10)
	theme.set_stylebox("normal", "LineEdit", field)
	var focused := field.duplicate() as StyleBoxFlat
	focused.border_color = ACCENT
	theme.set_stylebox("focus", "LineEdit", focused)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35))

func _misc(theme: Theme) -> void:
	# The picker scrolls horizontally, so its grabber must not sit on top of the tiles.
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(1.0, 1.0, 1.0, 0.22)
	grabber.set_corner_radius_all(pt(2))
	grabber.content_margin_top = pt(2)
	grabber.content_margin_bottom = pt(2)
	theme.set_stylebox("grabber", "HScrollBar", grabber)
	var grabber_hover := grabber.duplicate() as StyleBoxFlat
	grabber_hover.bg_color = Color(1.0, 1.0, 1.0, 0.38)
	theme.set_stylebox("grabber_highlight", "HScrollBar", grabber_hover)
	theme.set_stylebox("grabber_pressed", "HScrollBar", grabber_hover)
	theme.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())

	var separator := StyleBoxFlat.new()
	separator.bg_color = Color(1.0, 1.0, 1.0, 0.13)
	separator.content_margin_left = 1
	theme.set_stylebox("separator", "VSeparator", separator)
	theme.set_constant("separation", "VSeparator", pt(8))
