class_name Solver
extends RefCounted

# ============ 编码常量 ============
const MOVE_LEFT = 0
const MOVE_RIGHT = 1
const MOVE_UP = 2
const MOVE_DOWN = 3
const PUSH_LEFT = 4
const PUSH_RIGHT = 5
const PUSH_UP = 6
const PUSH_DOWN = 7

const CODE_NAMES = {
	MOVE_LEFT: "左移", MOVE_RIGHT: "右移", MOVE_UP: "上移", MOVE_DOWN: "下移",
	PUSH_LEFT: "左推", PUSH_RIGHT: "右推", PUSH_UP: "上推", PUSH_DOWN: "下推"
}

# ============ 状态类 ============
class State:
	var player_idx: int
	var box_mask: int
	var g: int = 0
	var parent: State = null
	var action: int = -1
	
	func _init(p: int, b: int):
		player_idx = p
		box_mask = b
	
	func hash() -> int:
		return (box_mask << 6) | player_idx

# ============ 求解器核心 ============
var valid_cells: Array[Vector2i] = []
var pos_to_idx: Dictionary = {}
var cell_count: int = 0

var neighbors: Array[Array] = []
var target_positions: Array[int] = []
var target_mask: int = 0

var initial_player_idx: int = -1
var initial_box_mask: int = 0
var deadlock_mask: int = 0

# 预计算距离
var dist_to_targets: Array[Array] = []

func parse_map(map_data: Array) -> bool:
	if map_data.is_empty():
		push_error("空地图")
		return false
	
	valid_cells.clear()
	pos_to_idx.clear()
	target_positions.clear()
	target_mask = 0
	initial_box_mask = 0
	initial_player_idx = -1
	
	var height = map_data.size()
	var width = map_data[0].size()
	
	# 收集所有非墙格子
	for y in range(height):
		var row = map_data[y]
		for x in range(row.size()):
			var ch = row[x]
			if ch == null or str(ch) == "#":
				continue
			
			var pos = Vector2i(x, y)
			var idx = valid_cells.size()
			valid_cells.append(pos)
			pos_to_idx[pos] = idx
			
			var s = str(ch)
			match s:
				"+":
					initial_player_idx = idx
					target_positions.append(idx)
					target_mask |= (1 << idx)
				"@":
					initial_player_idx = idx
				"*":
					initial_box_mask |= (1 << idx)
					target_positions.append(idx)
					target_mask |= (1 << idx)
				"$":
					initial_box_mask |= (1 << idx)
				".":
					target_positions.append(idx)
					target_mask |= (1 << idx)
	
	cell_count = valid_cells.size()
	
	if initial_player_idx == -1:
		push_error("没有玩家起始位置")
		return false
	
	# 预计算邻居
	neighbors.resize(cell_count)
	for i in range(cell_count):
		var pos = valid_cells[i]
		var n = [-1, -1, -1, -1]
		
		var up = Vector2i(pos.x, pos.y - 1)
		if up in pos_to_idx:
			n[0] = pos_to_idx[up]
		
		var down = Vector2i(pos.x, pos.y + 1)
		if down in pos_to_idx:
			n[1] = pos_to_idx[down]
		
		var left = Vector2i(pos.x - 1, pos.y)
		if left in pos_to_idx:
			n[2] = pos_to_idx[left]
		
		var right = Vector2i(pos.x + 1, pos.y)
		if right in pos_to_idx:
			n[3] = pos_to_idx[right]
		
		neighbors[i] = n
	
	# 预计算距离
	_precompute_distances()
	
	# 预计算死锁
	_precompute_deadlocks()
	
	print("地图解析: 有效格子=", cell_count, " 目标=", target_positions.size(), " 箱子=", _count_bits(initial_box_mask))
	return true

func _precompute_distances():
	dist_to_targets.resize(cell_count)
	for i in range(cell_count):
		dist_to_targets[i] = []
		var pos = valid_cells[i]
		for t in target_positions:
			var tpos = valid_cells[t]
			var dist = abs(pos.x - tpos.x) + abs(pos.y - tpos.y)
			dist_to_targets[i].append(dist)

func _precompute_deadlocks():
	deadlock_mask = 0
	
	for i in range(cell_count):
		if target_mask & (1 << i):
			continue
		
		var n = neighbors[i]
		var w_up = n[0] == -1
		var w_down = n[1] == -1
		var w_left = n[2] == -1
		var w_right = n[3] == -1
		
		# 角落死锁
		if (w_up and w_left) or (w_up and w_right) or \
		   (w_down and w_left) or (w_down and w_right):
			deadlock_mask |= (1 << i)
			continue
		
		# 沿墙死锁
		if w_up and w_down:
			deadlock_mask |= (1 << i)
		if w_left and w_right:
			deadlock_mask |= (1 << i)

func _count_bits(x: int) -> int:
	var count = 0
	while x:
		count += 1
		x &= x - 1
	return count

# ============ 启发函数（修复版：简单贪心） ============
func heuristic(state: State) -> int:
	var total = 0
	var used_targets = 0
	var box_list: Array[int] = []
	
	for i in range(cell_count):
		if state.box_mask & (1 << i):
			box_list.append(i)
	
	# 简单贪心：每个箱子找最近未使用的目标
	for box in box_list:
		var min_dist = 9999
		var best_t = -1
		
		for ti in range(target_positions.size()):
			if used_targets & (1 << ti):
				continue
			
			var dist = dist_to_targets[box][ti]
			if dist < min_dist:
				min_dist = dist
				best_t = ti
		
		if best_t >= 0:
			used_targets |= (1 << best_t)
			total += min_dist
	
	return total

# ============ 移动生成 ============
func generate_moves(state: State) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var p = state.player_idx
	var box_mask = state.box_mask
	var n = neighbors[p]
	
	# 上
	if n[0] != -1:
		if box_mask & (1 << n[0]):
			var nn = neighbors[n[0]][0]
			if nn != -1 and not (box_mask & (1 << nn)):
				if not (deadlock_mask & (1 << nn)):
					moves.append({"new_player": n[0], "new_box_from": n[0], "new_box_to": nn, "action": PUSH_UP})
		else:
			moves.append({"new_player": n[0], "action": MOVE_UP})
	
	# 下
	if n[1] != -1:
		if box_mask & (1 << n[1]):
			var nn = neighbors[n[1]][1]
			if nn != -1 and not (box_mask & (1 << nn)):
				if not (deadlock_mask & (1 << nn)):
					moves.append({"new_player": n[1], "new_box_from": n[1], "new_box_to": nn, "action": PUSH_DOWN})
		else:
			moves.append({"new_player": n[1], "action": MOVE_DOWN})
	
	# 左
	if n[2] != -1:
		if box_mask & (1 << n[2]):
			var nn = neighbors[n[2]][2]
			if nn != -1 and not (box_mask & (1 << nn)):
				if not (deadlock_mask & (1 << nn)):
					moves.append({"new_player": n[2], "new_box_from": n[2], "new_box_to": nn, "action": PUSH_LEFT})
		else:
			moves.append({"new_player": n[2], "action": MOVE_LEFT})
	
	# 右
	if n[3] != -1:
		if box_mask & (1 << n[3]):
			var nn = neighbors[n[3]][3]
			if nn != -1 and not (box_mask & (1 << nn)):
				if not (deadlock_mask & (1 << nn)):
					moves.append({"new_player": n[3], "new_box_from": n[3], "new_box_to": nn, "action": PUSH_RIGHT})
		else:
			moves.append({"new_player": n[3], "action": MOVE_RIGHT})
	
	return moves

func _apply_move(state: State, move: Dictionary) -> State:
	var new_box_mask = state.box_mask
	
	if move.has("new_box_from"):
		new_box_mask &= ~(1 << int(move["new_box_from"]))
		new_box_mask |= (1 << int(move["new_box_to"]))
	
	var new_state = State.new(int(move["new_player"]), new_box_mask)
	new_state.g = state.g + 1
	new_state.parent = state
	new_state.action = int(move["action"])
	
	return new_state

func _is_win(state: State) -> bool:
	return (state.box_mask & target_mask) == target_mask

# ============ IDA* 求解 ============
func solve() -> Array[int]:
	if initial_player_idx == -1:
		return []
	
	var initial = State.new(initial_player_idx, initial_box_mask)
	
	if _is_win(initial):
		return []
	
	var start_time = Time.get_ticks_msec()
	var nodes = 0
	
	var bound = heuristic(initial)
	var max_depth = 200
	
	while bound <= max_depth:
		print("IDA* 边界=", bound, "...")
		var result = _ida_search(initial, 0, bound, nodes)
		
		if result is Array:
			var elapsed = Time.get_ticks_msec() - start_time
			print("求解成功! 步数=", result.size(), " 节点=", nodes, " 耗时=", elapsed, "ms")
			return result
		
		if result == 999999:
			push_error("无解")
			return []
		
		bound = result
		
		if Time.get_ticks_msec() - start_time > 60000:
			push_error("求解超时(60s)")
			return []
	
	return []

func _ida_search(state: State, g: int, bound: int, nodes: int) -> Variant:
	nodes += 1
	var f = g + heuristic(state)
	
	if f > bound:
		return f
	
	if _is_win(state):
		return _reconstruct_actions(state)
	
	var min_next = 999999
	var moves = generate_moves(state)
	
	# 按推箱子后离目标距离排序
	if moves.size() > 1:
		moves.sort_custom(func(a, b):
			var ha = _move_heuristic(a)
			var hb = _move_heuristic(b)
			return ha < hb
		)
	
	for move in moves:
		var new_state = _apply_move(state, move)
		var result = _ida_search(new_state, g + 1, bound, nodes)
		
		if result is Array:
			return result
		
		if result < min_next:
			min_next = result
	
	return min_next

func _move_heuristic(move: Dictionary) -> int:
	if not move.has("new_box_to"):
		return 0
	
	var box_to = int(move["new_box_to"])
	var min_dist = 9999
	
	for t in target_positions:
		var dist = dist_to_targets[box_to][target_positions.find(t)]
		if dist < min_dist:
			min_dist = dist
	
	return min_dist

func _reconstruct_actions(end_state: State) -> Array[int]:
	var actions: Array[int] = []
	var current = end_state
	
	while current.parent != null:
		actions.append(current.action)
		current = current.parent
	
	actions.reverse()
	return actions

# ============ A* 备用求解 ============
func solve_astar() -> Array[int]:
	if initial_player_idx == -1:
		return []
	
	var initial = State.new(initial_player_idx, initial_box_mask)
	
	if _is_win(initial):
		return []
	
	var open_list: Array[State] = [initial]
	var open_scores: Array[int] = [heuristic(initial)]
	var closed_set = {}
	
	var nodes = 0
	var start_time = Time.get_ticks_msec()
	
	while not open_list.is_empty():
		var best_idx = 0
		var best_f = open_scores[0]
		for i in range(1, open_scores.size()):
			if open_scores[i] < best_f:
				best_f = open_scores[i]
				best_idx = i
		
		var current = open_list[best_idx]
		open_list.remove_at(best_idx)
		open_scores.remove_at(best_idx)
		
		nodes += 1
		
		if _is_win(current):
			var elapsed = Time.get_ticks_msec() - start_time
			print("A* 成功! 步数=", current.g, " 节点=", nodes, " 耗时=", elapsed, "ms")
			return _reconstruct_actions(current)
		
		var h = current.hash()
		if h in closed_set:
			continue
		closed_set[h] = true
		
		var moves = generate_moves(current)
		for move in moves:
			var next_state = _apply_move(current, move)
			var nh = next_state.hash()
			
			if nh in closed_set:
				continue
			
			var f = next_state.g + heuristic(next_state)
			open_list.append(next_state)
			open_scores.append(f)
	
	push_error("A* 无解")
	return []

# ============ 输出格式化 ============
func actions_to_string(actions: Array[int]) -> String:
	var result = ""
	for i in range(actions.size()):
		if i > 0:
			result += " "
		result += str(actions[i])
	return result

func actions_to_readable(actions: Array[int]) -> String:
	var result = ""
	for i in range(actions.size()):
		result += str(actions[i]) + "(" + CODE_NAMES.get(actions[i], "?") + ")"
		if i < actions.size() - 1:
			result += " "
	return result

func get_stats(actions: Array[int]) -> Dictionary:
	var moves = 0
	var pushes = 0
	for a in actions:
		if a <= 3:
			moves += 1
		else:
			pushes += 1
	return {"total": actions.size(), "moves": moves, "pushes": pushes}

# ============ 可视化 ============
func print_solution(map_data: Array, actions: Array[int]):
	if actions.is_empty():
		print("无解")
		return
	
	var state = State.new(initial_player_idx, initial_box_mask)
	var step = 0
	
	print("\n===== 初始状态 =====")
	_print_state(map_data, state)
	
	for action in actions:
		step += 1
		var moves = generate_moves(state)
		for move in moves:
			if int(move["action"]) == action:
				state = _apply_move(state, move)
				break
		
		var name = CODE_NAMES.get(action, "?")
		print("\n===== 步骤 ", step, " [", action, "=", name, "] =====")
		_print_state(map_data, state)
	
	var stats = get_stats(actions)
	print("\n===== 完成 ===== 总步数=", stats.total, " (移动", stats.moves, " + 推箱子", stats.pushes, ")")

func _print_state(map_data: Array, state: State):
	var height = map_data.size()
	var width = map_data[0].size()
	
	for y in range(height):
		var line = ""
		for x in range(width):
			var pos = Vector2i(x, y)
			if not pos in pos_to_idx:
				line += "#"
				continue
			
			var idx = pos_to_idx[pos]
			var is_player = (idx == state.player_idx)
			var is_box = (state.box_mask & (1 << idx)) != 0
			var is_target = (target_mask & (1 << idx)) != 0
			
			if is_player and is_target:
				line += "+"
			elif is_player:
				line += "@"
			elif is_box and is_target:
				line += "*"
			elif is_box:
				line += "$"
			elif is_target:
				line += "."
			else:
				line += " "
		print(line)
