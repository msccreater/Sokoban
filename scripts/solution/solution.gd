extends Node2D

@export var level_label: Label
@export var move_label: Label
@export var push_label: Label
@export var play_content: Node2D
@export var tips_panel: Panel
@export var tips_label: Label
@export var func_layout: VBoxContainer
@export var func_play_button: Button
@export var debug_mode: bool = false
@export var debug_level: int = 1

const MOVER_SPEED: float = 0.3  # 秒

# ========== 运行时变量 ==========
var move_times: int = 0:
	set(val):
		move_times = val
		move_label.text = "步数: %d" % move_times
var push_times: int = 0:
	set(val):
		push_times = val
		push_label.text = "移动: %d" % push_times
var move_records: Array = []  # 记录移动历史
var move_locked: bool = false
var forward_play: bool = false  # 正向自动播放
var rewind_play: bool = false   # 回退自动播放
var speed_up: bool = false      # 2倍速
var msg_tip_tween: Tween = null

# 地图数据（从GameData 获取后覆盖方便地直接使用）
var map_width: int = 10
var map_height: int = 10
var map_rotated: bool = false
var best_solution: Array = []
var map_cells: Array = []
var mover_node: Node2D = null

# ========== 初始化 ==========
func _ready():
	_setup_buttons()
	tips_panel.gui_input.connect(_on_tips_clicked)

func _setup_buttons():
	var buttons = func_layout.get_children()
	for i in range(buttons.size()):
		var btn = buttons[i] as Button
		if btn:
			btn.pressed.connect(_on_func_button_pressed.bind(i))

func _on_tips_clicked(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		tips_panel.hide()
		# 停止动画
		if msg_tip_tween and msg_tip_tween.is_valid():
			msg_tip_tween.kill()

func _on_func_button_pressed(index: int):
	AudioManager.play_sfx("click")
	match index:
		0:  # 重置并回退一步
			reset_play()
			rollback()
		1:  # 自动回退（加速）
			if forward_play:
				reset_play()
			else:
				forward_play = false
				rewind_play = true
				speed_up = true
				func_play_button.text = "暂停"
				rollback()
		2:  # 自动播放（正常速度）
			if forward_play or rewind_play:
				reset_play()
			else:
				forward_play = true
				rewind_play = false
				speed_up = false
				func_play_button.text = "暂停"
				move_step()
		3:  # 自动播放（加速）
			if rewind_play:
				reset_play()
			else:
				forward_play = true
				rewind_play = false
				speed_up = true
				func_play_button.text = "暂停"
				move_step()
		4:  # 重置并播放一步
			reset_play()
			move_step()
		5:  # 返回游戏
			get_tree().change_scene_to_file("res://scenes/game/game.tscn")

func _input(_event: InputEvent) -> void:
	if not debug_mode: return
	if Input.is_action_pressed("ui_page_up"):
		debug_level = clampi(debug_level-1, 1, GameData.max_level)
		reset_state()
	if Input.is_action_pressed("ui_page_down"):
		debug_level = clampi(debug_level+1, 1, GameData.max_level)
		reset_state()
	if Input.is_action_pressed("ui_accept"):
		forward_play = true
		rewind_play = false
		speed_up = true
		func_play_button.text = "暂停"
		move_step()

# ========== 生命周期 ==========
func _enter_tree():
	reset_state()

func reset_state():
	var select_level = GameData.level
	if debug_mode:
		select_level = debug_level
	GameData.load_level(select_level, play_content)
	move_times = 0
	push_times = 0
	map_cells = GameData.map_cells
	move_records.clear()
	move_locked = false
	forward_play = false
	rewind_play = false
	speed_up = false
	mover_node = GameData.get_mover_node()
	map_width = GameData.map_width
	map_height = GameData.map_height
	map_rotated = GameData.map_rotated
	best_solution = GameData.best_solution
	level_label.text = "关卡: %d" % GameData.level

# ========== 移动逻辑 ==========
func rollback():
	if not mover_node or move_locked:
		return

	if move_records.is_empty():
		show_msg("已回到初始状态!")
		reset_play()
		return

	var record = move_records.pop_back()
	var box_original_index: int = -1  # 箱子被推出前的位置（即玩家当前位置）o
	var mover_idx: int = mover_node.get_meta("tag")
	var mover_row: int = mover_idx / map_width
	var mover_col: int = mover_idx % map_width
	
	# 判断是否是推箱子（记录值 > 3 表示推了箱子）
	var is_push: bool = record > GameData.MoveDirection.DOWN
	var dir = record
	
	if is_push:
		dir -= 4
		match dir:
			GameData.MoveDirection.UP:
				if mover_row > 0: box_original_index = mover_idx - map_width
			GameData.MoveDirection.DOWN:
				if mover_row < map_height - 1: box_original_index = mover_idx + map_width
			GameData.MoveDirection.LEFT:
				if mover_col > 0: box_original_index = mover_idx - 1
			GameData.MoveDirection.RIGHT:
				if mover_col < map_width - 1: box_original_index = mover_idx + 1
	
	# 设置朝向（反向）
	mover_node.rotation_degrees = GameData.direction_to_rotation(dir)
	
	# 反向移动方向
	var reverse_dir: int
	match dir:
		GameData.MoveDirection.UP: reverse_dir = GameData.MoveDirection.DOWN
		GameData.MoveDirection.DOWN: reverse_dir = GameData.MoveDirection.UP
		GameData.MoveDirection.RIGHT: reverse_dir = GameData.MoveDirection.LEFT
		GameData.MoveDirection.LEFT: reverse_dir = GameData.MoveDirection.RIGHT
	
	# 计算目标位置
	var target_index: int = -1
	match reverse_dir:
		GameData.MoveDirection.UP:
			if mover_row > 0: target_index = mover_idx - map_width
		GameData.MoveDirection.DOWN:
			if mover_row < map_height - 1: target_index = mover_idx + map_width
		GameData.MoveDirection.LEFT:
			if mover_col > 0: target_index = mover_idx - 1
		GameData.MoveDirection.RIGHT:
			if mover_col < map_width - 1: target_index = mover_idx + 1
	
	if target_index < 0:
		return
	
	var target_cell = map_cells[target_index]
	if target_cell.type == GameData.ObjectInMap.WALL or target_cell.objectNode:
		return
	
	# 执行回退
	move_locked = true
	move_times -= 1
	
	var duration: float = MOVER_SPEED / (2.0 if speed_up else 1.0)
	var tween = create_tween()
	
	# 如果有推箱子，箱子也要回去
	if box_original_index >= 0:
		var box_cell = map_cells[box_original_index]
		if box_cell.objectNode:
			var current_cell = map_cells[mover_idx]
			current_cell.objectNode = box_cell.objectNode
			box_cell.objectNode = null
			
			# 箱子移动动画
			var box_tween = create_tween()
			box_tween.tween_property(current_cell.objectNode, "position", current_cell.pos, duration)
			
			push_times -= 1
			AudioManager.play_sfx("rollbackpush")
			
			# 玩家和箱子同时移动
			tween.set_parallel()
			tween.tween_property(mover_node, "position", target_cell.pos, duration)
			# 箱子动画已在上面创建
	else:
		AudioManager.play_sfx("rollbackmove")
		tween.tween_property(mover_node, "position", target_cell.pos, duration)
	
	# 播放动画
	var anim = mover_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim:
		anim.play("MoverPush" if box_original_index >= 0 else "MoverWalk")
	
	mover_node.set_meta("tag", target_index)
	
	await tween.finished
	
	if anim:
		anim.play("MoverNormal")
	
	check_is_finished()
	move_locked = false
	
	if move_records.is_empty():
		show_msg("已回到初始状态!")
		reset_play()
	elif rewind_play:
		rollback()  # 继续自动回退

func move_step():
	if not mover_node or move_locked:
		return

	if move_records.size() >= best_solution.size():
		show_msg("解答完毕")
		reset_play()
		return

	var dir = best_solution[move_records.size()]
	#if map_rotated:
		#dir = GameData.rotate_direction(dir)
	var rotation_deg: float = 0
	var target_idx: int = -1
	var mover_idx: int = mover_node.get_meta("tag")
	var mover_row: int = mover_idx / map_width
	var mover_col: int = mover_idx % map_width

	match dir:
		GameData.MoveDirection.UP:
			rotation_deg = -90
			if mover_row > 0: target_idx = mover_idx - map_width
		GameData.MoveDirection.DOWN:
			rotation_deg = 90
			if mover_row < map_height - 1: target_idx = mover_idx + map_width
		GameData.MoveDirection.LEFT:
			rotation_deg = 180
			if mover_col > 0: target_idx = mover_idx - 1
		GameData.MoveDirection.RIGHT:
			if mover_col < map_width - 1: target_idx = mover_idx + 1

	mover_node.rotation_degrees = rotation_deg
	
	if target_idx < 0:
		return

	var target_cell = map_cells[target_idx]
	if target_cell.type == GameData.ObjectInMap.WALL:
		return
	
	var can_move: bool = true
	var box_tween: Tween = null
	
	# 检查是否推箱子
	if target_cell.objectNode:
		can_move = false
		var push_target_idx: int = -1
		
		match dir:
			GameData.MoveDirection.UP:
				if mover_row > 1: push_target_idx = target_idx - map_width
			GameData.MoveDirection.DOWN:
				if mover_row < map_height - 2: push_target_idx = target_idx + map_width
			GameData.MoveDirection.LEFT:
				if mover_col > 1: push_target_idx = target_idx - 1
			GameData.MoveDirection.RIGHT:
				if mover_col < map_width - 2: push_target_idx = target_idx + 1
		
		if push_target_idx >= 0:
			var next_cell = map_cells[push_target_idx]
			if next_cell.type != GameData.ObjectInMap.WALL and not next_cell.objectNode:
				can_move = true
				next_cell.objectNode = target_cell.objectNode
				target_cell.objectNode = null
				
				box_tween = create_tween()
				box_tween.tween_property(next_cell.objectNode, "position", next_cell.pos, MOVER_SPEED / (2.0 if speed_up else 1.0))
	
	if not can_move:
		return
	
	# 执行移动
	move_locked = true
	move_times += 1
	
	var duration: float = MOVER_SPEED / (2.0 if speed_up else 1.0)
	var tween = create_tween()
	var anim = mover_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if box_tween:
		# 推箱子：玩家和箱子同时移动
		tween.set_parallel()
		tween.tween_property(mover_node, "position", target_cell.pos, duration)
		# 箱子 tween 在上面已创建
		
		push_times += 1
		move_records.append(dir + 4)  # +4 标记为推箱子
		AudioManager.play_sfx("push")
		if anim:
			anim.play("MoverPush")
	else:
		tween.tween_property(mover_node, "position", target_cell.pos, duration)
		move_records.append(dir)
		AudioManager.play_sfx("move")
		if anim:
			anim.play("MoverWalk")
	
	mover_node.set_meta("tag", target_idx)
	
	await tween.finished
	if anim:
		anim.play("MoverNormal")
	
	check_is_finished()
	move_locked = false
	
	if move_records.size() == best_solution.size():
		show_msg("解答完毕")
		reset_play()
	elif forward_play:
		move_step()  # 继续自动播放

func reset_play():
	forward_play = false
	rewind_play = false
	speed_up = false
	func_play_button.text = "自动播放"

func check_is_finished():
	for cell in map_cells:
		if cell.type == GameData.ObjectInMap.TARGET:
			if cell.objectNode:
				var sprite = cell.objectNode as Sprite2D
				if sprite:
					sprite.texture = GameData.game_box_r_texture
		elif cell.type == GameData.ObjectInMap.GROUND:
			if cell.objectNode:
				var sprite = cell.objectNode as Sprite2D
				if sprite:
					sprite.texture = GameData.game_box_texture

func show_msg(text: String, duration: float = 1.0):
	tips_label.text = text
	tips_panel.show()
	if msg_tip_tween and msg_tip_tween.is_valid():
		msg_tip_tween.kill()
	msg_tip_tween = create_tween()
	msg_tip_tween.tween_interval(duration)
	msg_tip_tween.tween_callback(func(): tips_panel.hide())
