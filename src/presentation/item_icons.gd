class_name ItemIcons
extends RefCounted
## The picture of every item (D-070): 16x16 pixel art, authored as text in
## `data/item_icons.json` and painted into textures here.
##
## The file has a palette (one letter per colour), named pieces of art (16 rows
## of 16 letters, `.` clear) and, per item, the pieces stacked to make its icon,
## each with optional colour overrides. Stacking is how a spoon with brown
## powder, a syringe with something in it and three kinds of baggie are drawn
## once and coloured many times. An item with no icon gets a question mark
## rather than nothing.
##
## Pure presentation: no rule reads an icon, and the tests only check that
## every item has one and that each is well formed.

const PATH := "res://data/item_icons.json"
const SIZE := 16
const FALLBACK := "unknown"

static var _loaded := false
static var _palette: Dictionary = {}
static var _art: Dictionary = {}
static var _icons: Dictionary = {}
static var _cache: Dictionary = {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		Log.error("art", "Item icons missing", {"path": PATH})
		return
	var parsed := SafeJson.parse_dict(file.get_as_text())
	_palette = parsed.get("palette", {})
	_art = parsed.get("art", {})
	_icons = parsed.get("icons", {})


## Forgets what was read and painted, so a test can start from the file.
static func reset() -> void:
	_loaded = false
	_cache.clear()
	_palette = {}
	_art = {}
	_icons = {}


static func has_icon(item_id: String) -> bool:
	_ensure_loaded()
	return _icons.has(item_id)


## Every item that has an icon.
static func icon_ids() -> Array:
	_ensure_loaded()
	return _icons.keys()


## What is wrong with the icon file, as plain sentences; empty when it is sound.
static func problems() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for name: String in _art:
		var rows: Array = _art[name]
		if rows.size() != SIZE:
			out.append("art '%s' has %d rows, not %d" % [name, rows.size(), SIZE])
			continue
		for i in rows.size():
			var row := str(rows[i])
			if row.length() != SIZE:
				out.append("art '%s' row %d is %d wide, not %d" % [name, i, row.length(), SIZE])
			for ch in row:
				if ch != "." and not _palette.has(ch):
					out.append("art '%s' uses '%s', which is not in the palette" % [name, ch])
	for item_id: String in _icons:
		for layer: Variant in _icons[item_id]:
			var art_name := _layer_art(layer)
			if not _art.has(art_name):
				out.append("icon '%s' uses unknown art '%s'" % [item_id, art_name])
	if not _art.has(FALLBACK):
		out.append("there is no '%s' art for items without one" % FALLBACK)
	return out


## The texture for an item, painted once and kept.
static func texture(item_id: String) -> Texture2D:
	_ensure_loaded()
	var key := item_id if _icons.has(item_id) else FALLBACK
	if _cache.has(key):
		var kept: Texture2D = _cache[key]
		return kept
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var layers: Array = _icons.get(key, [FALLBACK])
	for layer: Variant in layers:
		_paint(image, _layer_art(layer), _layer_colors(layer))
	var made := ImageTexture.create_from_image(image)
	_cache[key] = made
	return made


## A layer is an art name, or {"art": name, "colors": {letter: "#rrggbb"}}.
static func _layer_art(layer: Variant) -> String:
	if typeof(layer) == TYPE_DICTIONARY:
		var spec: Dictionary = layer
		return str(spec.get("art", ""))
	return str(layer)


static func _layer_colors(layer: Variant) -> Dictionary:
	if typeof(layer) == TYPE_DICTIONARY:
		var spec: Dictionary = layer
		return spec.get("colors", {})
	return {}


static func _paint(image: Image, art_name: String, colors: Dictionary) -> void:
	var rows: Array = _art.get(art_name, [])
	for y in mini(rows.size(), SIZE):
		var row := str(rows[y])
		for x in mini(row.length(), SIZE):
			var ch := row[x]
			if ch == ".":
				continue
			var html := str(colors.get(ch, _palette.get(ch, "")))
			if html != "":
				image.set_pixel(x, y, Color.html(html))


## The item's name in the player's language; "" for no item.
static func name_of(item_id: String) -> String:
	if item_id == "":
		return ""
	return Localization.t(str(Game.data.get_entry("items", item_id).get("name_key", item_id)))


## A picture of an item on a dark tile, for lists that only show it. `size` is
## the tile's side in pixels; the 16-pixel art is drawn at the largest whole
## multiple inside it, never blurred.
static func tile(item_id: String, size: int = 40) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(size, size)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", slot_style(Color(0.10, 0.10, 0.16, 0.9)))
	var picture := TextureRect.new()
	picture.texture = texture(item_id)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	return frame


static func slot_style(fill: Color, border: Color = Color(0.32, 0.31, 0.42, 1.0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.set_content_margin_all(3)
	return box
