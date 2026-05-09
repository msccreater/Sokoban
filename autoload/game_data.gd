extends Node

var game_box_texture: Texture2D = preload("res://assets/images/game-block-box.png")
var game_box_r_texture: Texture2D = preload("res://assets/images/game-block-box2.png")
var game_floor_texture: Texture2D = preload("res://assets/images/game-block-floor.png")
var game_target_bg_texture: Texture2D = preload("res://assets/images/game-block-targetbg.png")
var game_target_texture: Texture2D = preload("res://assets/images/game-block-target.png")
var game_wall_texture: Texture2D = preload("res://assets/images/game-block-wall.png")
var game_mover_texture: Texture2D = preload("res://assets/images/game-role-walk-1.png")
var game_mover_target_texture: Texture2D = preload("res://assets/images/game-role-target.png")
var mover_node_prefab: PackedScene = preload("res://scenes/mover.tscn")

enum ObjectInMap {
	WALL = 0,
	GROUND = 1,
	TARGET = 2,
	OBJECT = 3,
	MOVER = 4
}

enum MoveDirection {
	HOLD = 0,
	LEFT = 1,
	RIGHT = 2,
	UP = 3,
	DOWN = 4,
	LEFTPUSH = 5,
	RIGHTPUSH = 6,
	UPPUSH = 7,
	DOWNPUSH = 8
}

var max_level: int = 6000
var level: int = 1
var map_width: int = 0
var map_height: int = 0
var map_rotated: bool = false
var cell_wah: int = 0
var map_scale: float = 1.0
var map_original_str: String = ""
var best_solution: Array = []
var best_move: int = 0
var best_push: int = 0

var map_cells: Array = []
var play_content_node: Node2D = null
var mover_node: Node2D = null

var test_map: String = ""

func set_test_map(map_str: String = "") -> void:
	test_map = map_str

func rotate_direction(direction: MoveDirection) -> MoveDirection:
	match direction:
		MoveDirection.UP:    return MoveDirection.RIGHT
		MoveDirection.DOWN:  return MoveDirection.LEFT
		MoveDirection.RIGHT: return MoveDirection.DOWN
		MoveDirection.LEFT:  return MoveDirection.UP
	return MoveDirection.HOLD

func reverse_direction(direction: MoveDirection) -> MoveDirection:
	match direction:
		MoveDirection.UP:    return MoveDirection.DOWN
		MoveDirection.DOWN:  return MoveDirection.UP
		MoveDirection.LEFT:  return MoveDirection.RIGHT
		MoveDirection.RIGHT: return MoveDirection.LEFT
	return MoveDirection.HOLD

func direction_to_rotation(direction: MoveDirection) -> int:
	match direction:
		MoveDirection.UP:    return -90
		MoveDirection.DOWN:  return 90
		MoveDirection.LEFT:  return 180
		MoveDirection.RIGHT: return 0
	return 0

func load_level(map_level: int, content_node: Node2D) -> void:
	var file_path = "res://assets/levels/%d" % map_level
	if not FileAccess.file_exists(file_path):
		print("Level file not found: ", file_path)
		return
	var file = FileAccess.open(file_path, FileAccess.READ)
	var level_data = file.get_as_text()
	file.close()
	
	if not test_map.is_empty():
		level_data = test_map
		test_map = ""

	level = map_level
	map_width = 0
	map_height = 0
	map_rotated = false
	cell_wah = 0
	map_original_str = ""
	best_solution.clear()
	best_move = 0
	best_push = 0
	play_content_node = content_node
	_analyze(level_data)
	_generate_map()
	_init_mover_rotation()
	_add_boarder_walls()
	
	if map_cells.size() != map_width * map_height or mover_node == null:
		map_cells.clear()
		return
	play_content_node.scale = Vector2(map_scale, map_scale)
	play_content_node.position = get_viewport().get_visible_rect().size / 2.0

func get_mover_node() -> Node2D:
	return mover_node

func _generate_map() -> void:
	for item in play_content_node.get_children():
		item.queue_free()
	map_cells.clear()
	
	if map_rotated:
		play_content_node.rotation_degrees = -90
	else:
		play_content_node.rotation_degrees = 0
	
	# 初始化解析变量
	var char_index: int = 0
	var current_char: String = _get_char_at(map_original_str, char_index)
	var repeat_count: int = 0
	var col: int
	#var row: int
	
	# 逐行逐列生成地图
	for row in range(map_height):
		col = 0
		while col < map_width:
			repeat_count = 1
			# 内部区域（非边框）：解析地图字符串
			if row > 0 and row < map_height - 1 and col > 0 and col < map_width - 1:
				# 处理大写字母重复计数
				if current_char >= "A" and current_char <= "Z":
					repeat_count += _calculate_val(current_char)
					char_index += 1
					current_char = _get_char_at(map_original_str, char_index)
				
				# 根据字符确定单元格类型
				var cell_type = GameData.ObjectInMap.WALL
				var is_combined_type: bool = false  # 是否为组合类型（如+、*）
				
				match current_char:
					"!", "\\0":  # 行结束或字符串结束，填充剩余为墙
						repeat_count = map_width - 1 - col
						cell_type = GameData.ObjectInMap.WALL
					
					"#":
						cell_type = GameData.ObjectInMap.WALL
					
					"+":  # 玩家在目标点上
						cell_type = GameData.ObjectInMap.MOVER
						is_combined_type = true
					
					"@":  # 玩家
						cell_type = GameData.ObjectInMap.MOVER
					
					"*":  # 箱子在目标点上
						cell_type = GameData.ObjectInMap.OBJECT
						is_combined_type = true
					
					"$":  # 箱子
						cell_type = GameData.ObjectInMap.OBJECT
					
					".":  # 目标点
						cell_type = GameData.ObjectInMap.TARGET
					
					" ":  # 空地/地板
						cell_type = GameData.ObjectInMap.GROUND
				
				# 读取下一个字符
				char_index += 1
				current_char = _get_char_at(map_original_str, char_index)
				
				# 生成 repeat_count 个单元格
				for offset in range(repeat_count):
					var cell_index: int = row * map_width + col + offset
					
					# 计算单元格在场景中的位置
					# 坐标系：左下角为原点，向上向右为正
					var cell_pos: Vector2 = Vector2(
						-cell_wah * map_width / 2.0 + cell_wah / 2.0 + cell_wah * (col + offset),
						-cell_wah * map_height / 2.0 + cell_wah / 2.0 + cell_wah * row #cell_wah * (map_height - 1 - row)
					)
					
					# 最终存储的类型（可能与初始类型不同，如箱子/玩家下面其实是地板）
					var final_type = cell_type
					var object_node: Sprite2D = null  # 箱子或玩家等动态对象
					
					# 非墙单元格：创建视觉元素
					if cell_type != GameData.ObjectInMap.WALL:
						
						# 处理箱子
						if cell_type == GameData.ObjectInMap.OBJECT:
							final_type = GameData.ObjectInMap.GROUND
							
							var box_texture = game_box_r_texture if is_combined_type else game_box_texture
							object_node = _create_sprite(box_texture, cell_wah)
							play_content_node.add_child(object_node)
							object_node.position = cell_pos
							object_node.z_index = 2
							if map_rotated:
								object_node.rotation_degrees = 90
						
						# 处理玩家
						elif cell_type == GameData.ObjectInMap.MOVER:
							final_type = GameData.ObjectInMap.GROUND
							
							mover_node = mover_node_prefab.instantiate()
							mover_node.scale = Vector2.ONE * cell_wah / mover_node.get_node("Sprite2D").texture.get_size().x
							play_content_node.add_child(mover_node)
							mover_node.position = cell_pos
							mover_node.z_index = 1
							mover_node.set_meta("tag", cell_index)
						
						# 普通地板（非组合类型）
						if not is_combined_type:
							var floor_node = _create_sprite(game_floor_texture, cell_wah)
							play_content_node.add_child(floor_node)
							floor_node.position = cell_pos
							
							if map_rotated:
								floor_node.rotation_degrees = 90
						
						# 目标点（单独处理或作为组合类型的底层）
						if cell_type == GameData.ObjectInMap.TARGET or is_combined_type:
							final_type = GameData.ObjectInMap.TARGET
							
							# 目标点背景
							var target_bg = _create_sprite(game_target_bg_texture, cell_wah)
							play_content_node.add_child(target_bg)
							target_bg.position = cell_pos
							
							if map_rotated:
								target_bg.rotation_degrees = 90
							
							# 目标点标记（子节点）
							var target_mark = _create_sprite(game_target_texture, cell_wah)
							target_bg.add_child(target_mark)
					
					# 存储单元格数据
					map_cells.append({
						"idx": cell_index,
						"rowIdx": row,
						"colIdx": col + offset,
						"pos": cell_pos,
						"type": final_type,
						"objectNode": object_node
					})
				
			# 边框区域：直接填充为墙
			else:
				var border_pos: Vector2 = Vector2(
					-cell_wah * map_width / 2.0 + cell_wah / 2.0 + cell_wah * col,
					-cell_wah * map_height / 2.0 + cell_wah / 2.0 + cell_wah * row #cell_wah * (map_height - 1 - row)
				)
				
				map_cells.append({
					"idx": row * map_width + col,
					"rowIdx": row,
					"colIdx": col,
					"pos": border_pos,
					"type": GameData.ObjectInMap.WALL,
					"objectNode": null
				})
			
			col += repeat_count
		
		# 跳过行结束符 "!"
		if current_char == "!":
			char_index += 1
			current_char = _get_char_at(map_original_str, char_index)

func _get_char_at(s: String, idx: int) -> String:
	if idx >= 0 and idx < s.length():
		return s[idx]
	return ""

func _analyze(level_data: String) -> void:
	if level_data == null or level_data.length() == 0:
		return
	var parts = level_data.split(";")
	var map_string = parts[0]      # 地图编码字符串
	var solution_string = parts[1] # 解法编码字符串
	if map_string.length() == 0 or solution_string.length() == 0:
		return
	map_original_str = map_string
	_analyze_map_size(map_string)
	_analyze_scale()
	_analyze_solution(solution_string)

func _calculate_val(char_str: String) -> int:
	return char_str.unicode_at(0) - "A".unicode_at(0)

func _create_sprite(texture: Texture2D, size: float) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.texture = texture
	# 按尺寸缩放
	sprite.scale = Vector2.ONE * size / max(texture.get_size().x, texture.get_size().y)
	return sprite

func _analyze_map_size(map_string: String) -> void:
	var current_row_width: int = 0
	var max_row_width: int = 0
	var row_count: int = 0
	
	var char_index: int = 0
	var current_char
	while char_index < map_string.length():
		var cell_count: int = 1  # 默认每个字符代表1个单元格
		current_char = map_string[char_index]
		# 大写字母 A-Z 表示多个连续的空单元格
		if current_char >= "A" and current_char <= "Z":
			cell_count += _calculate_val(current_char)
			char_index += 1
			current_char = map_string[char_index]
		# "!" 表示换行（行结束）
		if current_char == "!":
			max_row_width = max(max_row_width, current_row_width)
			current_row_width = 0
			row_count += 1
		else:
			current_row_width += cell_count
		char_index += 1
	# 处理最后一行（如果没有以"!"结尾）
	max_row_width = max(max_row_width, current_row_width)
	if current_char != "!":
		row_count += 1
	# 地图尺寸 = 内容尺寸 + 2（外围边框）
	map_width = max_row_width + 2
	map_height = row_count + 2
	
	# 根据地图尺寸计算单元格像素大小
	var dimension_for_calculation: int = map_width
	if map_width > map_height:
		map_rotated = true
		if float(map_width) / map_height > 1.3:
			dimension_for_calculation = ceil(map_width / 1.3)
		else:
			dimension_for_calculation = map_height
	else:
		map_rotated = false
		if float(map_height) / map_width > 1.3:
			dimension_for_calculation = ceil(map_height / 1.3)
	
	# 根据计算出的维度确定单元格大小
	match dimension_for_calculation:
		11: cell_wah = 70
		12: cell_wah = 64
		13: cell_wah = 59
		14: cell_wah = 55
		15: cell_wah = 51
		16: cell_wah = 48
		17: cell_wah = 45
		18: cell_wah = 42
		19: cell_wah = 40
		_:
			if dimension_for_calculation > 19:
				cell_wah = 38
			else:
				cell_wah = 77  # dimension < 11 的情况
	
	# 单元格大小翻倍（可能是视网膜屏适配）
	cell_wah *= 2

func _analyze_scale() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	# 地图总尺寸
	var map_total_width := float(cell_wah * map_width)
	var map_total_height := float(cell_wah * map_height)
	# 计算适配缩放（留 10% 边距）
	var margin := 0.9
	var max_map_size = max(map_total_width, map_total_height)
	var min_viewport = min(viewport_size.x, viewport_size.y)
	map_scale = (min_viewport * margin) / max_map_size

func _analyze_solution(solution_string: String) -> void:
	best_solution.clear()
	best_move = 0
	best_push = 0
	var total_moves: int = 0      # 总步数（包括推和走）
	var total_pushes: int = 0     # 推箱子次数
	var i: int = 0
	while i < solution_string.length():
		var step_count: int = 1
		var ch = solution_string[i]
		if ch >= "A" and ch <= "Z":
			step_count += _calculate_val(ch)
			i += 1
			ch = solution_string[i]
		total_moves += step_count
		# 方向编码：0=左, 1=右, 2=上, 3=下
		# 如果方向值 > 3，说明是推箱子（编码方式：方向 + 4 = 推）
		var direction_code = ch.to_int()  # 字符转数字
		if direction_code > 3:
			total_pushes += step_count
		i += 1
	var j: int = 0
	while j < solution_string.length():
		var repeat_count: int = 1
		var ch = solution_string[j]
		if ch >= "A" and ch <= "Z":
			repeat_count += _calculate_val(ch)
			j += 1
			ch = solution_string[j]
		var direction_code = ch.to_int()
		# 将数字编码转换为方向枚举
		var direction: MoveDirection = MoveDirection.HOLD  # 默认不动
		match direction_code % 4:  # 取模4得到基础方向
			0: direction = MoveDirection.LEFT
			1: direction = MoveDirection.RIGHT
			2: direction = MoveDirection.UP
			3: direction = MoveDirection.DOWN
		# 展开重复步数，加入最佳解法数组
		if direction != MoveDirection.HOLD:
			for repeat in range(repeat_count):
				best_solution.append(direction)
		j += 1
	# 验证解法长度是否匹配
	if best_solution.size() != total_moves:
		best_solution.clear()
		return
	# 记录最佳成绩
	best_move = total_moves
	best_push = total_pushes

func _init_mover_rotation() -> void:
	if not mover_node:
		return
	var player_idx: int = mover_node.get_meta("tag")
	var player_row: int = floor(player_idx / map_width)
	var player_col: int = player_idx % map_width
	
	# 检查四个方向，找到最近的箱子或空地来决定朝向
	for direction in range(4):  # 0=上, 1=下, 2=左, 3=右
		var neighbor_idx: int = -1
		
		match direction:
			0:  # 上
				if player_row > 0:
					neighbor_idx = player_idx - map_width
			1:  # 下
				if player_row < map_height - 1:
					neighbor_idx = player_idx + map_width
			2:  # 左
				if player_col > 0:
					neighbor_idx = player_idx - 1
			3:  # 右
				if player_col < map_width - 1:
					neighbor_idx = player_idx + 1
		
		if neighbor_idx >= 0:
			var neighbor_cell = map_cells[neighbor_idx]
			
			# 如果旁边有箱子，朝向箱子
			if neighbor_cell.get("object_node"):
				match direction:
					0: mover_node.rotation_degrees = -90   # 上
					1: mover_node.rotation_degrees = 90    # 下
					2: mover_node.rotation_degrees = 180  # 左
					3: mover_node.rotation_degrees = 0     # 右
				break
			
			# 旁边没有箱子，根据位置偏向设置默认朝向
			elif neighbor_cell.get("type") != GameData.ObjectInMap.WALL:
				match direction:
					0:
						if player_row >= floor(map_height / 2.0):
							mover_node.rotation_degrees = -90
					1:
						if player_row <= floor(map_height / 2.0):
							mover_node.rotation_degrees = 90
					2:
						if player_col >= floor(map_width / 2.0):
							mover_node.rotation_degrees = 180
					3:
						if player_col <= floor(map_width / 2.0):
							mover_node.rotation_degrees = 0

func _add_boarder_walls() -> void:
	# 为墙块添加视觉精灵
	for cell in map_cells:
		if cell.type == GameData.ObjectInMap.WALL:
			# 检查8个邻接方向，找到第一个非墙的邻居
			for neighbor_dir in range(8):
				var neighbor_idx: int = -1
				match neighbor_dir:
					0:  # 上
						if cell.rowIdx > 0:
							neighbor_idx = cell.idx - map_width
					1:  # 下
						if cell.rowIdx < map_height - 1:
							neighbor_idx = cell.idx + map_width
					2:  # 左
						if cell.colIdx > 0:
							neighbor_idx = cell.idx - 1
					3:  # 右
						if cell.colIdx < map_width - 1:
							neighbor_idx = cell.idx + 1
					4:  # 左上
						if cell.rowIdx > 0 and cell.colIdx > 0:
							neighbor_idx = cell.idx - map_width - 1
					5:  # 右上
						if cell.rowIdx > 0 and cell.colIdx < map_width - 1:
							neighbor_idx = cell.idx - map_width + 1
					6:  # 左下
						if cell.rowIdx < map_height - 1 and cell.colIdx > 0:
							neighbor_idx = cell.idx + map_width - 1
					7:  # 右下
						if cell.rowIdx < map_height - 1 and cell.colIdx < map_width - 1:
							neighbor_idx = cell.idx + map_width + 1
				
				# 如果找到非墙邻居，为这个墙块创建精灵
				if neighbor_idx >= 0 and map_cells[neighbor_idx].get("type") != GameData.ObjectInMap.WALL:
					var wall_sprite = _create_sprite(game_wall_texture, cell_wah)
					play_content_node.add_child(wall_sprite)
					wall_sprite.position = cell.pos
					wall_sprite.z_index = 9
					
					if map_rotated:
						wall_sprite.rotation_degrees = 90
					
					break  # 只创建一个精灵就够了
