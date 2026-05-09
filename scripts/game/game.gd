extends Node2D

const MOVER_SPEED := 0.125  # 移动动画时长（秒）
const KEEP_MOVE_DELAY: float = 0.5
const AUTO_ROLLBACK_DELAY: float = 0.375

@onready var play_content_node: Node2D = %PlayContentNode
@onready var level_label: Label = %LevelLabel
@onready var move_label: Label = %MoveLabel
@onready var push_label: Label = %PushLabel
@onready var restart_button: Button = %RestartButton
@onready var undo_button: Button = %UndoButton
@onready var level_button: Button = %LevelButton
@onready var solution_button: Button = %SolutionButton
@onready var sfx_button: CheckButton = %SFXButton
@onready var editor_button: Button = %EditorButton

@onready var score_page: Panel = %ScorePage
@onready var level_select_page: Panel = %LevelSelectPage

# ========== 运行时变量 ==========
var level: int = 1:
	set(val):
		level = val
		level_label.text = "关卡: %d(%d*%d)" % [level,GameData.map_width, GameData.map_height]
var move_times: int = 0:
	set(val):
		move_times = val
		move_label.text = "步数: %d" % move_times
var push_times: int = 0:
	set(val):
		push_times = val
		push_label.text = "移动: %d" % push_times

var history_move: int = 0
var history_push: int = 0
var move_records: Array = []
var move_locked: bool = false
var current_direction: int = GameData.MoveDirection.HOLD
var key_hold_time: float = 0.0
var rollback_hold_time: float = 0.0
var keep_rollback: bool = false
var is_game_over: bool = false

# 地图据(从GameData获取后覆盖,方便直接使用)
var map_width: int = 0
var map_height: int = 0
var map_rotated: bool = false
var best_solution: Array = []
var map_cells: Array = []
var mover_node = null
var best_move: int = 0
var best_push: int = 0

func _ready() -> void:
	level_select_page.level_select_changed.connect(_on_change_level)
	score_page.restart_click.connect(_on_restart_game)
	score_page.continue_click.connect(_on_continue_game)
	restart_button.pressed.connect(_on_restart_game)
	undo_button.pressed.connect(rollback)
	level_button.pressed.connect(_show_level_page)
	solution_button.pressed.connect(_show_solution_page)
	sfx_button.toggled.connect(func(enable): AudioManager.set_sfx(enable))
	level = SaveManager.get_int("level", 1)
	sfx_button.set_pressed_no_signal(AudioManager.get_sfx())
	editor_button.pressed.connect(_show_editor_page)
	play(level)

func reset_state(select_level: int):
	GameData.load_level(select_level, play_content_node)
	level = select_level
	move_times = 0
	push_times = 0
	history_move = SaveManager.get_int("scoremove" + str(level), 0)
	history_push = SaveManager.get_int("scorepush" + str(level), 0)
	move_records.clear()
	move_locked = false
	current_direction = GameData.MoveDirection.HOLD
	key_hold_time = 0.0
	rollback_hold_time = 0.0
	keep_rollback = false
	is_game_over = false
	
	map_width = GameData.map_width
	map_height = GameData.map_height
	map_rotated = GameData.map_rotated
	best_move = GameData.best_move
	best_push = GameData.best_push
	best_solution = GameData.best_solution
	map_cells = GameData.map_cells
	mover_node = GameData.get_mover_node()

func _process(delta: float) -> void:
	if move_locked or is_game_over:
		return
	# 优先检查回退（避免移动和回退同时触发）
	if Input.is_action_pressed("undo"):
		_process_rollback_input(delta)
		return
	# 重置回退状态
	rollback_hold_time = 0.0
	keep_rollback = false

	var direction := get_input_direction()
	# 没有按键，重置状态
	if direction == GameData.MoveDirection.HOLD:
		current_direction = GameData.MoveDirection.HOLD
		key_hold_time = 0.0
		return
   
   # 方向变化，首次移动
	if direction != current_direction:
		current_direction = direction
		key_hold_time = 0.0
		var actual_direction := direction
		if map_rotated:
			actual_direction = GameData.rotate_direction(direction)
		move(actual_direction)
		return
	# 同方向长按，累加时间
	key_hold_time += delta
	if key_hold_time >= KEEP_MOVE_DELAY:
		var actual_direction := direction
		if map_rotated:
			actual_direction = GameData.rotate_direction(direction)
		move(actual_direction, true)

func get_input_direction() -> GameData.MoveDirection:
	if Input.is_action_pressed("move_up"):    return GameData.MoveDirection.UP
	if Input.is_action_pressed("move_down"):  return GameData.MoveDirection.DOWN
	if Input.is_action_pressed("move_left"):  return GameData.MoveDirection.LEFT
	if Input.is_action_pressed("move_right"): return GameData.MoveDirection.RIGHT
	return GameData.MoveDirection.HOLD

func _process_rollback_input(delta: float) -> void:
	rollback_hold_time += delta
	# 单击：立即回退一步
	if Input.is_action_just_pressed("undo"):
		rollback()
		return
	# 长按：进入持续回退
	if rollback_hold_time >= AUTO_ROLLBACK_DELAY and not keep_rollback:
		keep_rollback = true
	if keep_rollback:
		rollback()

func _reset_keep_move() -> void:
	current_direction = GameData.MoveDirection.HOLD
	key_hold_time = 0.0


func _on_change_level(new_level: int) -> void:
	AudioManager.play_sfx("click")
	level = new_level
	play(level)

func _on_restart_game() -> void:
	AudioManager.play_sfx("click")
	score_page.hide_score_page()
	play(level)

func _on_continue_game() -> void:
	AudioManager.play_sfx("click")
	score_page.hide_score_page()
	play(level + 1)

func _show_level_page() -> void:
	AudioManager.play_sfx("click")
	level_select_page.show_level_select(level, GameData.max_level)

func _show_solution_page() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://scenes/solution/solution.tscn")

func _show_editor_page() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://scenes/editor/level_editor.tscn")

func play(select_level: int) -> void:
	var file_path = "res://assets/levels/%d" % select_level
	if not FileAccess.file_exists(file_path):
		print("Level file not found: ", file_path)
		return

	select_level = clampi(select_level, 1, GameData.max_level)
	SaveManager.set_int("level", select_level)
	reset_state(select_level)

# 简化回放函数（无动画，直接瞬移）
func replay_move(record_direction: int) -> void:
	if record_direction == GameData.MoveDirection.HOLD or mover_node == null:
		return
	var is_push_record: bool = record_direction > GameData.MoveDirection.DOWN
	var direction = record_direction - 4 if is_push_record else record_direction
	
	var player_index: int = mover_node.get_meta("tag")
	var player_row: int = floor(player_index / map_width)
	var player_col: int = player_index % map_width
	
	# 设置朝向
	mover_node.rotation_degrees = GameData.direction_to_rotation(direction)
	
	var target_index: int = -1
	
	match direction:
		GameData.MoveDirection.UP:
			if player_row > 0:
				target_index = player_index - map_width
		GameData.MoveDirection.DOWN:
			if player_row < map_height - 1:
				target_index = player_index + map_width
		GameData.MoveDirection.LEFT:
			if player_col > 0:
				target_index = player_index - 1
		GameData.MoveDirection.RIGHT:
			if player_col < map_width - 1:
				target_index = player_index + 1
	
	if target_index < 0:
		return
	
	var target_cell = map_cells[target_index]
	
	if target_cell["type"] == GameData.ObjectInMap.WALL:
		return
	
	# 处理推箱子
	var is_push: bool = false
	if target_cell["objectNode"] != null:
		var push_target_index: int = -1
		
		match direction:
			GameData.MoveDirection.UP:
				if player_row > 1:
					push_target_index = target_index - map_width
			GameData.MoveDirection.DOWN:
				if player_row < map_height - 2:
					push_target_index = target_index + map_width
			GameData.MoveDirection.LEFT:
				if player_col > 1:
					push_target_index = target_index - 1
			GameData.MoveDirection.RIGHT:
				if player_col < map_width - 2:
					push_target_index = target_index + 1
		
		if push_target_index >= 0:
			var push_target_cell = map_cells[push_target_index]
			
			if push_target_cell["type"] != GameData.ObjectInMap.WALL and push_target_cell["objectNode"] == null:
				is_push = true
				
				push_target_cell["objectNode"] = target_cell["objectNode"]
				target_cell["objectNode"] = null
				push_target_cell["objectNode"].position = push_target_cell["pos"]
	
	# 移动玩家
	mover_node.position = target_cell["pos"]
	mover_node.set_meta("tag", target_index)
	
	# 更新统计
	move_times += 1
	if is_push:
		push_times += 1
	
	# 记录到 move_records（用于后续回退）
	move_records.append(record_direction)

func check_is_finished() -> bool:
	var all_targets_filled := true
	for cell in map_cells:
		var cell_type: int = cell["type"]
		var object_node = cell["objectNode"]
		if cell_type == GameData.ObjectInMap.TARGET:
			if object_node != null:
				# 目标点上有箱子 -> 显示完成态
				object_node.texture = GameData.game_box_r_texture
			else:
				# 目标点上没有箱子 -> 关卡未完成
				all_targets_filled = false
				
		elif cell_type == GameData.ObjectInMap.GROUND:
			if object_node != null:
				# 普通地板上的箱子 -> 显示普通态
				object_node.texture = GameData.game_box_texture
	
	if all_targets_filled:
		is_game_over = true
		clear_data()
		
		# 保存最佳记录
		update_best_score()
		
		# 通关音效
		AudioManager.play_sfx("result", 0.5)
		
		# 显示通关界面
		score_page.show_score_page(move_times, push_times, 
			history_move, history_push,
			best_move, best_push)
		
		print("Level ", level, " completed! Moves: ", move_times, " Pushes: ", push_times)
	else:
		save_data()
	
	return all_targets_filled

func update_best_score() -> void:
	# 首次通关 或 步数更少 或 步数相同但推数更少
	var is_new_record := false
	
	if history_move == 0:
		# 首次通关
		is_new_record = true
	elif history_move > move_times:
		# 步数更少
		is_new_record = true
	elif history_move == move_times and history_push > push_times:
		# 步数相同，推数更少
		is_new_record = true
	
	if is_new_record:
		history_move = move_times
		history_push = push_times
		
		# 保存到本地
		SaveManager.set_int("scoremove" + str(level), move_times)
		SaveManager.set_int("scorepush" + str(level), push_times)
		
		print("New record! Move: ", move_times, " Push: ", push_times)

func clear_data() -> void:
	SaveManager.set_string("gdata" + str(level), "")

func save_data() -> void:
	if is_game_over:
		return
	SaveManager.set_string("gdata" + str(level), JSON.stringify(move_records))

# 玩家移动核心逻辑
func move(direction: int, is_keep_move: bool = false) -> void:
	# 有效性检查
	if direction == GameData.MoveDirection.HOLD or mover_node == null or move_locked:
		return
	
	# 获取当前位置
	var player_index: int = mover_node.get_meta("tag")
	var player_row: int = floor(player_index / map_width)
	var player_col: int = player_index % map_width
	
	# 1. 计算目标位置和旋转角度
	var rotation_angle: int = 0
	var target_index: int = -1
	
	match direction:
		GameData.MoveDirection.UP:
			rotation_angle = -90
			if player_row > 0:
				target_index = player_index - map_width
		
		GameData.MoveDirection.DOWN:
			rotation_angle = 90
			if player_row < map_height - 1:
				target_index = player_index + map_width
		
		GameData.MoveDirection.LEFT:
			rotation_angle = 180
			if player_col > 0:
				target_index = player_index - 1
		
		GameData.MoveDirection.RIGHT:
			if player_col < map_width - 1:
				target_index = player_index + 1
	
	# 2. 设置朝向
	mover_node.rotation_degrees = rotation_angle
	
	# 目标位置无效
	if target_index < 0:
		_reset_keep_move()
		return
	
	var target_cell = map_cells[target_index]
	
	# 3. 墙壁碰撞检测
	if target_cell["type"] == GameData.ObjectInMap.WALL:
		_reset_keep_move()
		return
	
	if is_keep_move and target_cell["objectNode"] != null:
		_reset_keep_move()
		return
	
	var can_move: bool = true
	var box_push_tween: Tween = null  # 推箱子动画
	
	# 4. 推箱子检测
	if target_cell["objectNode"] != null:
		can_move = false
		
		var push_target_index: int = -1
		
		match direction:
			GameData.MoveDirection.UP:
				if player_row > 1:
					push_target_index = target_index - map_width
			
			GameData.MoveDirection.DOWN:
				if player_row < map_height - 2:
					push_target_index = target_index + map_width
			
			GameData.MoveDirection.LEFT:
				if player_col > 1:
					push_target_index = target_index - 1
			
			GameData.MoveDirection.RIGHT:
				if player_col < map_width - 2:
					push_target_index = target_index + 1
		
		# 检查箱子后方是否可以推动
		if push_target_index >= 0:
			var push_target_cell = map_cells[push_target_index]
			
			
			# 后方不是墙且没有箱子，且不是触摸滑动状态（防止误触）
			if push_target_cell["type"] != GameData.ObjectInMap.WALL and push_target_cell["objectNode"] == null:
				can_move = true
				
				# 移动箱子数据
				push_target_cell["objectNode"] = target_cell["objectNode"]
				target_cell["objectNode"] = null
				
				# 创建推箱子动画
				box_push_tween = _create_box_push_tween(
					push_target_cell["objectNode"],
					push_target_cell["pos"]
				)
	
	# 5. 执行移动
	if not can_move:
		_reset_keep_move()
		return
	
	move_locked = true
	move_times += 1
	
	# 6. 创建移动动画
	var player_tween := _create_player_tween(target_cell["pos"])
	
	var is_push := (box_push_tween != null)
	
	if is_push:
		# 推箱子：同时播放玩家和箱子动画
		_play_animation("MoverPush")
		push_times += 1
		move_records.append(direction + 4)  # Push 记录偏移 +4
		AudioManager.play_sfx("push")
	else:
		# 普通移动
		_play_animation("MoverWalk")
		move_records.append(direction)
		AudioManager.play_sfx("move")
	
	# 7. 更新玩家索引
	mover_node.set_meta("tag", target_index)
	
	# 8. 动画完成回调
	await player_tween.finished
	
	# 恢复静止动画
	_play_animation("MoverNormal")
	
	# 检查通关
	if check_is_finished():
		_reset_keep_move()
		return
	
	# 解锁，允许下一次移动
	move_locked = false


# 辅助函数
func _create_player_tween(target_pos: Vector2) -> Tween:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(mover_node, "position", target_pos, MOVER_SPEED)
	return tween

func _create_box_push_tween(box_node: Node2D, target_pos: Vector2) -> Tween:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(box_node, "position", target_pos, MOVER_SPEED)
	return tween

func _play_animation(anim_name: String) -> void:
	# 根据你的动画系统选择
	var anim_sprite := mover_node.get_node("AnimationPlayer") as AnimationPlayer
	if anim_sprite:
		anim_sprite.play(anim_name)

# ============================================
# 回退功能
# ============================================

func rollback() -> void:
	# 有效性检查
	if mover_node == null or move_locked:
		return
	
	# 没有可回退的步数
	if move_records.size() == 0:
		show_msg("Has been rolled back over!")  # RollbackEnd
		keep_rollback = false
		return
	
	# 弹出最后一步记录
	var last_record: int = move_records.pop_back()
	
	# 获取玩家当前位置
	var player_index: int = mover_node.get_meta("tag")
	var player_row: int = floor(player_index / map_width)
	var player_col: int = player_index % map_width
	
	# ============================================
	# 1. 判断是否是推箱子，计算箱子原始位置
	# ============================================
	
	var box_original_index: int = -1  # 箱子被推出前的位置（即玩家当前位置）
	var base_direction: int = last_record
	
	if last_record > GameData.MoveDirection.DOWN:
		# 推箱子记录，减去4得到基础方向
		base_direction = last_record - 4
		
		match base_direction:
			GameData.MoveDirection.UP:
				if player_row > 0:
					box_original_index = player_index - map_width
			
			GameData.MoveDirection.DOWN:
				if player_row < map_height - 1:
					box_original_index = player_index + map_width
			
			GameData.MoveDirection.LEFT:
				if player_col > 0:
					box_original_index = player_index - 1
			
			GameData.MoveDirection.RIGHT:
				if player_col < map_width - 1:
					box_original_index = player_index + 1
	
	# ============================================
	# 2. 设置玩家朝向（面向原来的方向）
	# ============================================
	
	var rotation_angle: int = GameData.direction_to_rotation(base_direction)
	mover_node.rotation_degrees = rotation_angle
	
	# ============================================
	# 3. 反转方向（回退方向 = 原方向的反方向）
	# ============================================
	
	var rollback_direction: int = GameData.reverse_direction(base_direction)
	
	# ============================================
	# 4. 计算玩家回退后的目标位置
	# ============================================
	
	var target_index: int = -1
	
	match rollback_direction:
		GameData.MoveDirection.UP:
			if player_row > 0:
				target_index = player_index - map_width
		
		GameData.MoveDirection.DOWN:
			if player_row < map_height - 1:
				target_index = player_index + map_width
		
		GameData.MoveDirection.LEFT:
			if player_col > 0:
				target_index = player_index - 1
		
		GameData.MoveDirection.RIGHT:
			if player_col < map_width - 1:
				target_index = player_index + 1
	
	# 目标位置无效
	if target_index < 0:
		return
	
	var target_cell = map_cells[target_index]
	
	# 目标必须是空地（不能是墙，也不能有箱子）
	if target_cell["type"] == GameData.ObjectInMap.WALL or target_cell["objectNode"] != null:
		return
	
	# ============================================
	# 5. 拉回箱子（如果有）
	# ============================================
	
	var box_pull_tween: Tween = null
	var is_pull: bool = false
	
	if box_original_index >= 0:
		var box_original_cell = map_cells[box_original_index]
		
		if box_original_cell["objectNode"] != null:
			is_pull = true
			
			# 箱子拉回：从箱子当前位置 -> 玩家当前位置
			var player_current_cell = map_cells[player_index]
			
			# 移动箱子数据
			player_current_cell["objectNode"] = box_original_cell["objectNode"]
			box_original_cell["objectNode"] = null
			
			# 创建箱子拉回动画
			box_pull_tween = _create_box_pull_tween(
				player_current_cell["objectNode"],
				player_current_cell["pos"]
			)
	
	# ============================================
	# 6. 执行回退动画
	# ============================================
	
	move_locked = true
	move_times -= 1
	
	var player_tween := _create_player_tween(target_cell["pos"])
	
	if is_pull:
		# 拉回箱子
		_play_animation("MoverPush")
		push_times -= 1
		AudioManager.play_sfx("rollbackpush")
	else:
		# 普通回退
		_play_animation("MoverWalk")
		AudioManager.play_sfx("rollbackmove")
	
	# 更新玩家索引
	mover_node.set_meta("tag", target_index)
	
	# ============================================
	# 7. 动画完成回调
	# ============================================
	await box_pull_tween.finished
	await player_tween.finished
	
	# 恢复静止动画
	_play_animation("MoverNormal")
	
	# 检查通关状态（回退后可能从完成变为未完成）
	check_is_finished()
	
	# 解锁
	move_locked = false
	
	# 持续回退
	if keep_rollback:
		rollback()

func _create_box_pull_tween(box_node: Node2D, target_pos: Vector2) -> Tween:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(box_node, "position", target_pos, MOVER_SPEED)
	return tween

func show_msg(_text: String, _duration: float = 1.0) -> void:
	# 显示提示信息
	pass
