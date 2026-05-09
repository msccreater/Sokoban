extends Control

const CHAR_MAP = ['#', ' ', '.', '$', '*', '@', '+']

# ======== 可调参数 ========
var grid_rows: int = 8
var grid_cols: int = 8
var cell_size: int = 32
# ==========================

var map_data: Array = []          # 二维字符数组
var current_tile: String = '#'
var solver: Solver = Solver.new()
var msg_tip_tween: Tween = null
var is_dragging: bool = false
var is_erasing: bool = false
var last_cell: Vector2i = Vector2i(-1, -1)
var tile_buttons: Array = []

# UI 节点
@onready var edit_area: Control = $EditArea
@onready var btn_test_play: Button = $TopBar/BtnTestPlay
@onready var btn_test_solution: Button = $TopBar/BtnTestSolution
@onready var btn_import: Button = $TopBar/BtnImport
@onready var btn_export: Button = $TopBar/BtnExport
@onready var label_current_tile: Label = $TileBar/LabelCurrentTile
@onready var label_size_info: Label = $InfoPanel/LabelSizeInfo
@onready var label_counts: Label = $InfoPanel/LabelCounts
@onready var btn_wall: Button = $TileBar/BtnWall
@onready var btn_floor: Button = $TileBar/BtnFloor
@onready var btn_target: Button = $TileBar/BtnTarget
@onready var btn_box: Button = $TileBar/BtnBox
@onready var btn_box_on_target: Button = $TileBar/BtnBoxOnTarget
@onready var btn_player: Button = $TileBar/BtnPlayer
@onready var btn_player_on_target: Button = $TileBar/BtnPlayerOnTarget
@onready var btn_resize: Button = $InfoPanel/BtnResize
@onready var btn_clear: Button = $InfoPanel/BtnClear
@onready var tips_panel: Panel = $TipsPanel
@onready var tips_label: Label = $TipsPanel/TipsLabel

func _ready():
	_init_map()

	edit_area.mouse_filter = Control.MOUSE_FILTER_STOP
	edit_area.gui_input.connect(_on_edit_area_input)
	edit_area.draw.connect(_on_edit_area_draw)
	edit_area.queue_redraw()

	# 图块选择按钮
	btn_wall.pressed.connect(func(): set_current_tile('#'))
	btn_floor.pressed.connect(func(): set_current_tile(' '))
	btn_target.pressed.connect(func(): set_current_tile('.'))
	btn_box.pressed.connect(func(): set_current_tile('$'))
	btn_box_on_target.pressed.connect(func(): set_current_tile('*'))
	btn_player.pressed.connect(func(): set_current_tile('@'))
	btn_player_on_target.pressed.connect(func(): set_current_tile('+'))
	tile_buttons = [btn_wall,btn_floor,btn_target,btn_box,btn_box_on_target,btn_player,btn_player_on_target]

	# 顶部导出
	btn_test_play.pressed.connect(_on_test_play_pressed)
	btn_test_solution.pressed.connect(_on_test_solution_pressed)
	btn_import.pressed.connect(_on_import_pressed)
	btn_export.pressed.connect(_on_export_pressed)

	# 信息面板
	btn_resize.pressed.connect(_on_resize_pressed)
	btn_clear.pressed.connect(_on_clear_pressed)

	
	set_current_tile('#')
	_update_info_labels()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	match event.keycode:
		KEY_1: set_current_tile('#')
		KEY_2: set_current_tile(' ')
		KEY_3: set_current_tile('.')
		KEY_4: set_current_tile('$')
		KEY_5: set_current_tile('*')
		KEY_6: set_current_tile('@')
		KEY_7: set_current_tile('+')

# ---------- 地图初始化 ----------
func _init_map(init_str: String = ""):
	map_data.clear()
	if init_str.is_empty():
		for row in range(grid_rows):
			var col_arr = []
			col_arr.resize(grid_cols)
			map_data.append(col_arr)
	else:
		var rows: Array = []
		var current_row: Array = []
		var i = 0
		while i < init_str.length():
			var ch = init_str[i]
			if not(ch == '!' or (ch >= 'A' and ch <= 'Z') or CHAR_MAP.has(ch)):
				i += 1
				break
			if ch == "!" or ch == ";":
				if not current_row.is_empty():
					rows.append(current_row)
					current_row = []
				i += 1
			elif ch >= 'A' and ch <= 'Z':
				var cell_count = 1
				cell_count += GameData._calculate_val(ch)
				i += 1
				if i < init_str.length():
					ch = init_str[i]
					for j in range(cell_count):
						current_row.append(ch)
					i += 1
				else:
					break
			else:
				current_row.append(ch)
				i += 1
		if not current_row.is_empty():
			rows.append(current_row)
		if not rows.is_empty():
			var max_width = 0
			for row in rows:
				max_width = max(max_width, row.size())
			grid_cols = max_width
			grid_rows = rows.size()
			for r in range(grid_rows):
				var col_arr = []
				col_arr.resize(grid_cols)
				for c in range(grid_cols):
					col_arr[c] = rows[r][c] if c < rows[r].size() else ""
				map_data.append(col_arr)


# ---------- 图块选择 ----------
func set_current_tile(tile_char: String):
	current_tile = tile_char
	label_current_tile.text = "当前: " + _tile_display_name(tile_char)
	for i in range(CHAR_MAP.size()):
		if CHAR_MAP[i] == tile_char:
			tile_buttons[i].button_pressed = true
			break

func _tile_display_name(c: String) -> String:
	match c:
		'#': return "墙"
		' ': return "地板"
		'.': return "目标"
		'$': return "箱子"
		'*': return "箱子在目标上"
		'@': return "玩家"
		'+': return "玩家在目标上"
	return c


# ---------- 鼠标交互 ----------
func _on_edit_area_input(event: InputEvent):
	#if not (event is InputEventMouseButton and event.pressed): return
	#var local_pos = edit_area.get_local_mouse_position()
	#var offset = Vector2((edit_area.size.x - grid_cols * cell_size) / 2.0,
						 #(edit_area.size.y - grid_rows * cell_size) / 2.0)
	#var col_idx = int((local_pos.x - offset.x) / cell_size)
	#var row_idx = int((local_pos.y - offset.y) / cell_size)
	#if col_idx < 0 or col_idx >= grid_cols or row_idx < 0 or row_idx >= grid_rows: return
#
	#if event.button_index == MOUSE_BUTTON_LEFT:
		#map_data[row_idx][col_idx] = current_tile
	#elif event.button_index == MOUSE_BUTTON_RIGHT:
		#map_data[row_idx][col_idx] = ''
	#_update_info_labels()
	#edit_area.queue_redraw()
	
	# 鼠标按下：开始拖动
	if event is InputEventMouseButton and event.pressed:
		var cell = _get_cell_at_mouse()
		if cell == Vector2i(-1, -1):
			return
			
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = true
			is_erasing = false
			_place_at(cell)
			
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			is_dragging = true
			is_erasing = true
			_erase_at(cell)
	
	# 鼠标释放：停止拖动
	elif event is InputEventMouseButton and not event.pressed:
		is_dragging = false
		last_cell = Vector2i(-1, -1)
	
	# 鼠标移动：拖动中持续放置/删除
	elif event is InputEventMouseMotion and is_dragging:
		var cell = _get_cell_at_mouse()
		if cell != Vector2i(-1, -1) and cell != last_cell:
			if is_erasing:
				_erase_at(cell)
			else:
				_place_at(cell)

# 将鼠标坐标转为格子坐标
func _get_cell_at_mouse() -> Vector2i:
	var local_pos = edit_area.get_local_mouse_position()
	var offset = Vector2(
		(edit_area.size.x - grid_cols * cell_size) / 2.0,
		(edit_area.size.y - grid_rows * cell_size) / 2.0
	)
	
	var col_idx = int((local_pos.x - offset.x) / cell_size)
	var row_idx = int((local_pos.y - offset.y) / cell_size)
	
	if col_idx < 0 or col_idx >= grid_cols or row_idx < 0 or row_idx >= grid_rows:
		return Vector2i(-1, -1)
	
	return Vector2i(col_idx, row_idx)


# 在指定格子放置
func _place_at(cell: Vector2i):
	last_cell = cell
	var col_idx = cell.x
	var row_idx = cell.y
	
	# 玩家只能有一个
	if current_tile == "@" or current_tile == "+":
		_remove_existing_player()
	
	map_data[row_idx][col_idx] = current_tile
	_update_info_labels()
	edit_area.queue_redraw()


# 在指定格子删除
func _erase_at(cell: Vector2i):
	last_cell = cell
	var col_idx = cell.x
	var row_idx = cell.y
	
	map_data[row_idx][col_idx] = ""
	_update_info_labels()
	edit_area.queue_redraw()


# 移除地图上已有的玩家
func _remove_existing_player():
	for row in range(grid_rows):
		for col in range(grid_cols):
			if map_data[row][col] == "@" or map_data[row][col] == "+":
				map_data[row][col] = ""

# ---------- 绘制 ----------
func _on_edit_area_draw():
	if not edit_area: return
	var canvas = edit_area
	var offset = Vector2((canvas.size.x - grid_cols * cell_size) / 2.0,
						 (canvas.size.y - grid_rows * cell_size) / 2.0)
	for row in range(grid_rows):
		for col in range(grid_cols):
			var tile_char = map_data[row][col]
			var rect_pos = offset + Vector2(col * cell_size, row * cell_size)
			#var rect = Rect2(rect_pos, Vector2(cell_size, cell_size))
			if tile_char and not tile_char.is_empty():
				var texture = _get_tile_texture(tile_char)
				if not texture:
					continue
				var src_rect = Rect2(Vector2(0,0), texture.get_size())
				var dst_rect = Rect2(rect_pos, Vector2(cell_size, cell_size))
				canvas.draw_texture_rect_region(texture, dst_rect, src_rect)

	for i in range(grid_rows + 1):
		var y = offset.y + i * cell_size
		canvas.draw_line(Vector2(offset.x, y), Vector2(offset.x + grid_cols * cell_size, y), Color.BLACK, 1)
	for j in range(grid_cols + 1):
		var x = offset.x + j * cell_size
		canvas.draw_line(Vector2(x, offset.y), Vector2(x, offset.y + grid_rows * cell_size), Color.BLACK, 1)

func _get_tile_texture(tile_char: String) -> Texture2D:
	match tile_char:
		' ': return GameData.game_floor_texture #地板
		'#': return GameData.game_wall_texture #墙壁
		'.': return GameData.game_target_texture #目标
		'$': return GameData.game_box_texture #箱子
		'@': return GameData.game_mover_texture #玩家
		'*': return GameData.game_box_r_texture #箱子在目标
		"+": return GameData.game_mover_target_texture #玩家在目标
	return null

# ---------- UI 信息更新 ----------
func _update_info_labels():
	var box_count = 0
	var target_count = 0
	var player_count = 0
	for row in map_data:
		for c in row:
			if c == '$' or c == '*': box_count += 1
			if c == '.' or c == '*' or c == '+': target_count += 1
			if c == '@' or c == '+': player_count += 1
	label_size_info.text = "当前: %d×%d (内部)" % [grid_cols, grid_rows]
	label_counts.text = "箱:%d 标:%d 人:%d" % [box_count, target_count, player_count]


# ---------- 🔥 核心：自动裁剪 + 字母压缩导出 ----------
func _on_test_play_pressed():
	var export_str = _generate_map_str()
	GameData.set_test_map(export_str)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")
	
func _on_test_solution_pressed():
	var export_str = _generate_map_str()
	GameData.set_test_map(export_str)
	get_tree().change_scene_to_file("res://scenes/solution/solution.tscn")

func _on_import_pressed():
	var map_str = DisplayServer.clipboard_get()
	if not map_str.is_empty():
		_init_map(map_str)
		_update_info_labels()
		edit_area.queue_redraw()
	
func _on_export_pressed():
	var export_str = _generate_map_str()
	DisplayServer.clipboard_set(export_str)
	_show_tip("已导出 %s" % export_str)

func _generate_map_str() -> String:
	var lines = []
	for r in grid_rows:
		var row_chars = []
		# 找起始位置
		var start_idx = -1
		for c in range(grid_cols):
			var tile_char = map_data[r][c]
			if tile_char:
				start_idx = c
				break
		if start_idx == -1:
			continue
		# 找结束位置
		var end_idx = -1
		for c in range(grid_cols - 1, -1, -1):
			var tile_char = map_data[r][c]
			if tile_char:
				end_idx = c
				break
		# 处理一行数据
		for c in range(start_idx, end_idx + 1):
			var tile_char = map_data[r][c]
			row_chars.append(tile_char if tile_char else ' ')
		lines.append(_compress_row(row_chars))

	if lines.is_empty():
		_show_tip("全空")
		return ""

	for row in range(grid_rows):
		for col in range(grid_cols):
			var tile_char = map_data[row][col]
			if not tile_char:
				map_data[row][col] = "#"
				
	var solution_str = ""
	var success = solver.parse_map(map_data)
	if success:
		var actions = solver.solve_astar()
		solution_str = _compress_row(actions)
	var export_str = "!".join(lines)+";" +solution_str
	return export_str

# 通用压缩：任何连续相同字符超过 2 个就压缩，否则原样输出
func _compress_row(row: Array) -> String:
	var res = ""
	var i = 0
	while i < row.size():
		var ch = row[i]
		var count = 1
		while i + count < row.size() and row[i + count] == ch:
			count += 1
		if count > 2:
			var extra = count
			while extra > 0:
				var step = mini(extra, 26)         # 1..26
				res += char(64 + step) + str(ch)        # 'A' = 65
				extra -= step
		else:
			for _j in range(count):
				res += str(ch)
		i += count
	return res

# ---------- 调整尺寸对话框 ----------
func _on_resize_pressed():
	var dialog = AcceptDialog.new()
	dialog.title = "调整地图大小"
	dialog.size = Vector2(350, 150)
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	var row1 = HBoxContainer.new()
	row1.add_child(_make_label("列数："))
	var spin_cols = _make_spinbox(3, 100, grid_cols)
	row1.add_child(spin_cols)
	vbox.add_child(row1)
	var row2 = HBoxContainer.new()
	row2.add_child(_make_label("行数："))
	var spin_rows = _make_spinbox(3, 100, grid_rows)
	row2.add_child(spin_rows)
	vbox.add_child(row2)
	dialog.add_cancel_button("取消")
	dialog.add_button("确定", true, "confirm")
	dialog.confirmed.connect(func():
		grid_cols = int(spin_cols.value)
		grid_rows = int(spin_rows.value)
		_init_map()
		_update_info_labels()
		edit_area.queue_redraw()
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()


func _make_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	return lbl

func _make_spinbox(minv: int, maxv: int, value: int) -> SpinBox:
	var sb = SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.value = value
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sb


# ---------- 清空地图 ----------
func _on_clear_pressed():
	_init_map()
	_update_info_labels()
	edit_area.queue_redraw()
	_show_tip("地图已清空")


# ---------- 简易提示 ----------
func _show_tip(text: String, duration: float = 1.0):
	tips_label.text = text
	tips_panel.show()
	if msg_tip_tween and msg_tip_tween.is_valid():
		msg_tip_tween.kill()
	msg_tip_tween = create_tween()
	msg_tip_tween.tween_interval(duration)
	msg_tip_tween.tween_callback(func(): tips_panel.hide())
