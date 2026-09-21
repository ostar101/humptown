class_name ItemSlot
extends Button
## One square that holds a picture of a thing and, past one, how many (D-070):
## the cell of the crafting grid, of the bag beside it, and the output. It is a
## button so the keyboard reaches it; an empty slot is a button with no picture.
##
## Presentation only. It knows an item id and a number, not what either means.

const COLOUR_FILL := Color(0.10, 0.10, 0.16, 0.92)
const COLOUR_EDGE := Color(0.32, 0.31, 0.42, 1.0)
const COLOUR_HOVER := Color(0.16, 0.16, 0.25, 0.95)
const COLOUR_FOCUS := Color(0.95, 0.80, 0.35, 1.0)

var item_id := ""
var count := 0

var _count_label: Label = null


func _init(side: float = 56.0) -> void:
	custom_minimum_size = Vector2(side, side)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_stylebox_override("normal", ItemIcons.slot_style(COLOUR_FILL, COLOUR_EDGE))
	add_theme_stylebox_override("pressed", ItemIcons.slot_style(COLOUR_HOVER, COLOUR_EDGE))
	add_theme_stylebox_override("hover", ItemIcons.slot_style(COLOUR_HOVER, COLOUR_FOCUS))
	add_theme_stylebox_override("hover_pressed", ItemIcons.slot_style(COLOUR_HOVER, COLOUR_FOCUS))
	add_theme_stylebox_override("disabled", ItemIcons.slot_style(COLOUR_FILL, COLOUR_EDGE))
	var focus := ItemIcons.slot_style(Color(0, 0, 0, 0), COLOUR_FOCUS)
	add_theme_stylebox_override("focus", focus)
	_count_label = Label.new()
	_count_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count_label.offset_right = -4.0
	_count_label.offset_bottom = -1.0
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.add_theme_font_size_override("font_size", 15)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	_count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_count_label.add_theme_constant_override("outline_size", 4)
	add_child(_count_label)


## Puts a thing in the slot; "" empties it. The number shows from two up.
func show_item(p_item_id: String, p_count: int = 1) -> void:
	item_id = p_item_id
	count = p_count if p_item_id != "" else 0
	icon = ItemIcons.texture(p_item_id) if p_item_id != "" else null
	tooltip_text = ItemIcons.name_of(p_item_id)
	_count_label.text = str(count) if count > 1 else ""


func is_empty() -> bool:
	return item_id == ""
