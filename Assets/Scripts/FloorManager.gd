extends Node

const CONDITION_PREVIEW_TIME: float = 3.0

# State --------------------------------------------
var current_condition: BaseCondition = null
var is_active: bool = false
var _is_previewing: bool = false

# Init ---------------------------------------------
func _ready():
	GameManager.floor_cleared.connect(_on_floor_cleared)
	call_deferred("_show_condition_preview")

func _show_condition_preview() -> void:
	_is_previewing = true

	var condition_name = GameManager.get_condition_name()
	print("Condition preview: ", condition_name)

	var overlay = ColorRect.new()
	overlay.name = "ConditionPreviewOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var label = Label.new()
	label.name = "ConditionPreviewLabel"
	label.text = condition_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(label)

	var font_size = 80
	var theme = Theme.new()
	var font = FontFile.new()
	var font_path = "res://textures/Pixelmax-Regular.otf"
	if ResourceLoader.exists(font_path):
		font = load(font_path)
		var font_var = theme
		font_var.set_default_font(font)
		font_var.set_default_font_size(font_size)
		label.theme = font_var
	else:
		label.add_theme_font_size_override("font_size", font_size)

	var tween = create_tween()
	tween.tween_interval(CONDITION_PREVIEW_TIME)
	await tween.finished

	overlay.queue_free()
	_auto_start()

func _auto_start() -> void:
	var script = GameManager.get_condition_script()
	var condition: BaseCondition = script.new()
	start_condition(condition)

# Start --------------------------------------------
func start_condition(condition: BaseCondition) -> void:
	if current_condition:
		current_condition.queue_free()
	current_condition = condition
	add_child(current_condition)
	current_condition.start_condition()
	is_active = true
	print("Condition started: ", condition.get_class())

# Process loop -------------------------------------
func _process(delta: float) -> void:
	if not is_active or not current_condition:
		return
	current_condition.process_condition(delta)
	if current_condition.is_complete():
		is_active = false
		GameManager.on_floor_cleared()

# Floor clear hook ---------------------------------
func _on_floor_cleared(_floor_number: int) -> void:
	pass
