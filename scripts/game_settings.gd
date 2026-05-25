extends Node

# This file stores menu choices before the game scene opens.
enum Mode { ONE_PLAYER, TWO_PLAYER, FOUR_PLAYER }

var mode: Mode = Mode.TWO_PLAYER
var single_color: int = 1
var best_of: int = 3
var ai_enabled: bool = false
# 1 means the human starts. 2 means the AI starts.
var human_player: int = 1
