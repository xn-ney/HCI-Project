extends Panel

@onready var title_label = $TitleLabel
@onready var choice_container = $ChoiceContainer
@onready var rest_btn = $ChoiceContainer/RestButton
@onready var exit_btn = $ExitButton

var campfire: Node = null
var choice_made: bool = false

func _ready():
	rest_btn.pressed.connect(_on_rest)
	exit_btn.pressed.connect(_on_exit)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		close()

func setup(fire: Node):
	campfire = fire

func _on_rest():
	if choice_made:
		return
	choice_made = true
	if campfire and campfire.has_method("rest"):
		campfire.rest()
	close_and_advance()

func _on_exit():
	close()

func close():
	if campfire and campfire.has_method("close_ui"):
		campfire.close_ui()
	else:
		GameManager.ui_open = false
		var parent = get_parent()
		if parent:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			parent.queue_free()

func close_and_advance():
	close()
	if campfire and campfire.has_method("advance_floor"):
		campfire.advance_floor()
