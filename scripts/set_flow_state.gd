extends RefCounted
class_name SetFlowState

# This helper stores set-level rules between shots.
# It keeps track of opener rules and the answer phase.
var set_opener := 1
var opener_perfect_run := true
var answer_phase := false
var answer_winner := 0
var answer_source_player := 0
var next_set_starter := 1
var opener_cleared_with_nopfoul := false
var last_shot_was_nopfoul := false
var opener_perfect_nopfoul_clear := false
var opener_perfect_opp_disc_clear := false
var opener_cleared_with_opp_disc := false
var opening_turn_player := 0
var opening_turn_perfect_run := false
var opening_turn_remaining: Array = []

func reset_for_new_set(starter: int, num_players: int) -> void:
	set_opener = starter
	next_set_starter = 1
	opener_perfect_run = true
	answer_phase = false
	answer_winner = 0
	answer_source_player = 0
	opener_cleared_with_nopfoul = false
	opener_perfect_nopfoul_clear = false
	opener_perfect_opp_disc_clear = false
	opener_cleared_with_opp_disc = false
	last_shot_was_nopfoul = false
	_init_opening_turn_state(starter, num_players)

func _init_opening_turn_state(starter: int, num_players: int) -> void:
	if num_players == 4:
		opening_turn_player = starter
		opening_turn_perfect_run = true
		opening_turn_remaining = [1, 2, 3, 4]
	else:
		opening_turn_player = 0
		opening_turn_perfect_run = false
		opening_turn_remaining.clear()

func is_set_opener_shot(player: int) -> bool:
	return not answer_phase and player == set_opener

func is_opening_turn_active_for(player: int, num_players: int) -> bool:
	return (
		num_players == 4
		and not answer_phase
		and opening_turn_player == player
		and opening_turn_remaining.has(player)
	)

func is_opening_turn_shot(player: int, num_players: int) -> bool:
	return is_opening_turn_active_for(player, num_players)

func clear_answer_source_player(player: int, num_players: int) -> int:
	if num_players == 4 and is_opening_turn_shot(player, num_players):
		return player
	return set_opener

func record_clear_answer_flags(
	num_players: int,
	shooter: int,
	foul: bool,
	keep_turn: bool,
	award_penalty: bool,
	opponent_disc_potted: bool,
	valid_hit: bool
) -> void:
	var set_opener_shot := is_set_opener_shot(shooter)
	var opening_turn_shot := is_opening_turn_shot(shooter, num_players)
	var set_opener_was_perfect := opener_perfect_run
	var opening_turn_was_perfect := opening_turn_perfect_run

	if set_opener_shot and (foul or not keep_turn):
		opener_perfect_run = false
	if opening_turn_shot and (foul or not keep_turn):
		opening_turn_perfect_run = false

	opener_perfect_nopfoul_clear = (
		((set_opener_shot and set_opener_was_perfect) or (opening_turn_shot and opening_turn_was_perfect))
		and foul
		and not award_penalty
	)
	opener_perfect_opp_disc_clear = (
		((set_opener_shot and set_opener_was_perfect) or (opening_turn_shot and opening_turn_was_perfect))
		and not foul
		and opponent_disc_potted
		and valid_hit
	)

func advance_opening_turn_state(
	num_players: int,
	shooter: int,
	current_player: int,
	keep_turn: bool,
	game_over: bool
) -> void:
	if num_players != 4 or answer_phase or game_over or keep_turn:
		return
	if not opening_turn_remaining.has(shooter):
		return
	opening_turn_remaining.erase(shooter)
	if opening_turn_remaining.has(current_player):
		opening_turn_player = current_player
		opening_turn_perfect_run = true
	else:
		opening_turn_player = 0
		opening_turn_perfect_run = false

func begin_answer_phase(winner_if_fail: int, source_player: int) -> void:
	answer_phase = true
	answer_winner = winner_if_fail
	answer_source_player = source_player

func clear_answer_phase() -> void:
	answer_phase = false
	answer_winner = 0
	answer_source_player = 0
	opener_cleared_with_nopfoul = false
	opener_cleared_with_opp_disc = false

func replay_starter(next_starter: int = -1) -> int:
	if next_starter >= 1:
		return next_starter
	if answer_source_player >= 1:
		return answer_source_player
	return set_opener

func snapshot() -> Dictionary:
	return {
		"set_opener": set_opener,
		"opener_perfect_run": opener_perfect_run,
		"answer_phase": answer_phase,
		"answer_winner": answer_winner,
		"answer_source_player": answer_source_player,
		"next_set_starter": next_set_starter,
		"opener_cleared_with_nopfoul": opener_cleared_with_nopfoul,
		"last_shot_was_nopfoul": last_shot_was_nopfoul,
		"opener_perfect_nopfoul_clear": opener_perfect_nopfoul_clear,
		"opener_perfect_opp_disc_clear": opener_perfect_opp_disc_clear,
		"opener_cleared_with_opp_disc": opener_cleared_with_opp_disc,
		"opening_turn_player": opening_turn_player,
		"opening_turn_perfect_run": opening_turn_perfect_run,
		"opening_turn_remaining": opening_turn_remaining.duplicate(),
	}

func restore(data: Dictionary) -> void:
	set_opener = data["set_opener"]
	opener_perfect_run = data["opener_perfect_run"]
	answer_phase = data["answer_phase"]
	answer_winner = data["answer_winner"]
	answer_source_player = data["answer_source_player"]
	next_set_starter = data["next_set_starter"]
	opener_cleared_with_nopfoul = data["opener_cleared_with_nopfoul"]
	last_shot_was_nopfoul = data["last_shot_was_nopfoul"]
	opener_perfect_nopfoul_clear = data["opener_perfect_nopfoul_clear"]
	opener_perfect_opp_disc_clear = data["opener_perfect_opp_disc_clear"]
	opener_cleared_with_opp_disc = data["opener_cleared_with_opp_disc"]
	opening_turn_player = data["opening_turn_player"]
	opening_turn_perfect_run = data["opening_turn_perfect_run"]
	opening_turn_remaining = data["opening_turn_remaining"].duplicate()
