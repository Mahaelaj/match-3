class_name Piece
extends Node2D

## Reference to a Sprite node
@onready var sprite = $Sprite2D

signal pressed
signal released
signal mouseEntered

var lastRoundMoved = 0
var isInReserve = false
var isMatched = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass # Replace with function body.
	
# Move the Piece instance to the position passed in the target argument
func move(target):
	position = target

func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if (event.is_action_pressed("touch") && !isInReserve):
		pressed.emit()
	if(event.is_action_released("touch")):
		released.emit()

func _on_mouse_entered() -> void:
	if (!isInReserve):
		mouseEntered.emit()
		
func make_matched():
	isMatched = true
	sprite.modulate = Color(1,1,1,.5)
