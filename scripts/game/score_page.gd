extends Panel

signal restart_click
signal continue_click

@onready var now_score_label: Label = %NowScoreLabel
@onready var history_score_label: Label = %HistoryScoreLabel
@onready var best_score_label: Label = %BestScoreLabel
@onready var restart_button: Button = %RestartButton
@onready var continue_button: Button = %ContinueButton

func _ready() -> void:
	restart_button.pressed.connect(_on_restart)
	continue_button.pressed.connect(_on_continue)

func show_score_page(move_times: int, push_times: int, \
		history_move: int, history_push: int, \
		best_move:int, best_push: int) -> void:
	visible = true
	now_score_label.text = "本次解答   Move %d   Push %d" % [move_times, push_times]
	history_score_label.text = "历史解答   Move %d   Push %d" % [history_move, history_push]
	best_score_label.text = "最佳解答   Move %d   Push %d" % [best_move, best_push]

func hide_score_page() -> void:
	visible = false

func _on_restart() -> void:
	visible = false
	restart_click.emit()
	
func _on_continue() -> void:
	visible = false
	continue_click.emit()
