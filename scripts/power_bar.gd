extends ProgressBar

# This file updates the power bar under the striker.
@onready var main: Node = $".."
@onready var cue: Sprite2D = $"../Cue"

func _process(_delta: float) -> void:
	# Do not update while pieces are still moving.
	if main.moving:
		return

	# Convert cue power into a 0 to 100 bar value.
	var ratio: float = cue.power / main.MAX_POWER
	value = ratio * 100.0

	# The bar gets more red as the shot gets stronger.
	modulate = Color(1.0, 1.0 - 0.35 * ratio, 1.0 - 0.7 * ratio, 1.0)
