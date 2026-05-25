extends RigidBody2D

@onready var drag_icon = $Pointer
@onready var main = $".."

func _ready():
	drag_icon.texture = load("res://assets/pointing.png")
	drag_icon.hide()

func _process(_delta):
	# Show the hand icon only while the striker is being moved.
	if main.dragging_puck or main.ai_moving_puck:
		drag_icon.show()
	else:
		drag_icon.hide()
