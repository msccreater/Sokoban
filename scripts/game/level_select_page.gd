extends Panel

signal level_select_changed(new_level: int)

@onready var sub_button: Button = %SubButton
@onready var level_label: Label = %LevelLabel
@onready var add_button: Button = %AddButton
@onready var confirm_button: Button = %ConfirmButton
@onready var close_button: Button = %CloseButton
@onready var adjust_timer: Timer = %AdjustTimer

var current_level: int = 1
var max_level: int = 6000

# 长按连续调整
var adjust_direction: int = 0  # -1=减, 1=加
var adjust_step: int = 1
var adjust_count: int = 0

func _ready() -> void:
	adjust_timer.timeout.connect(_on_adjust_timeout)
	
	# 连接信号
	sub_button.button_down.connect(_on_sub_pressed)
	sub_button.button_up.connect(_on_sub_released)
	add_button.button_down.connect(_on_add_pressed)
	add_button.button_up.connect(_on_add_released)
	confirm_button.pressed.connect(_on_confirm)
	close_button.pressed.connect(_on_close)

func show_level_select(current: int, max_lvl: int) -> void:
	current_level = current
	max_level = max_lvl
	refresh()
	visible = true

func refresh() -> void:
	level_label.text = str(current_level)

func _on_sub_pressed() -> void:
	adjust_direction = -1
	adjust_step = 1
	adjust_count = 0
	
	# 立即减1
	adjust_level(-1)
	
	# 0.5秒后开始连续递减
	get_tree().create_timer(0.5).timeout.connect(_start_continuous_adjust)

func _on_sub_released() -> void:
	adjust_timer.stop()

# 加号按钮
func _on_add_pressed() -> void:
	adjust_direction = 1
	adjust_step = 1
	adjust_count = 0
	
	# 立即加1
	adjust_level(1)
	
	# 0.5秒后开始连续递增
	get_tree().create_timer(0.5).timeout.connect(_start_continuous_adjust)

func _on_add_released() -> void:
	adjust_timer.stop()

# 连续调整
func _start_continuous_adjust() -> void:
	# 检查按钮是否仍然按下
	if (adjust_direction == -1 and sub_button.is_pressed()) or \
	   (adjust_direction == 1 and add_button.is_pressed()):
		adjust_timer.start()

func _on_adjust_timeout() -> void:
	adjust_count += 1
	
	# 每10步加速
	if adjust_count % 10 == 0:
		adjust_step *= 10
		adjust_step = min(adjust_step, 1000)  # 最大1000
	
	adjust_level(adjust_direction * adjust_step)

func adjust_level(delta: int) -> void:
	var new_level := clampi(current_level + delta, 1, max_level)
	if new_level != current_level:
		current_level = new_level
		refresh()
		AudioManager.play_sfx("click")

# 确认/关闭
func _on_confirm() -> void:
	AudioManager.play_sfx("click")
	visible = false
	level_select_changed.emit(current_level)

func _on_close() -> void:
	AudioManager.play_sfx("click")
	visible = false
