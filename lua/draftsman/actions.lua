local state = require("draftsman.state")
local canvas = require("draftsman.canvas")
local mech = require("draftsman.mechanics")
local ui = require("draftsman.ui")
local C = require("draftsman.constants")

local M = {}

-- Helper: Update a char based on neighbor bitmask
local function smart_merge(row, virt_col, new_mask_bits, mask_to_remove)
	local current_char = canvas.get_char_at(row, virt_col)
	local current_mask = state.char_to_mask[current_char] or 0
	local new_char = mech.resolve_char(current_mask, new_mask_bits, mask_to_remove)
	if new_char then
		canvas.set_char_at(row, virt_col, new_char)
	end
end

function M.move_edge_at(direction, r, c)
	local char = canvas.get_char_at(r, c)
	local mask = state.char_to_mask[char] or 0

	if mask == 0 then
		if ui and ui.update_status then
			ui.update_status("No edge to move.\nPlace cursor on an edge character.")
		end
		return
	end

	-- 准备基础参数
	local move_dr, move_dc = mech.direction_to_coord(direction)
	local move_bit = C.DIR_KEY_TO_BIT[direction]
	local rev_bit = C.OPPOSITE_BIT[move_bit]

	-- 1. 确定扫描轴 (Scan Axis)
	-- 如果左右移动(h/l)，移动的是竖线(j/k轴)
	-- 如果上下移动(j/k)，移动的是横线(h/l轴)
	local axis_dirs = {}
	local axis_bits = 0
	if direction == "h" or direction == "l" then
		axis_dirs = { "j", "k" }
		axis_bits = bit.bor(C.DIR_KEY_TO_BIT["j"], C.DIR_KEY_TO_BIT["k"])
	else
		axis_dirs = { "h", "l" }
		axis_bits = bit.bor(C.DIR_KEY_TO_BIT["h"], C.DIR_KEY_TO_BIT["l"])
	end

	-- 2. 扫描整条线段
	-- edges_pos 仅包含与移动方向垂直的那一条连续线段
	local edges_pos = {}

	local function scan(start_r, start_c, scan_dir)
		local dr, dc = mech.direction_to_coord(scan_dir)
		local scan_bit = C.DIR_KEY_TO_BIT[scan_dir]
		local curr_r, curr_c = start_r, start_c

		while true do
			local curr_char = canvas.get_char_at(curr_r, curr_c)
			local curr_mask = state.char_to_mask[curr_char] or 0

			if bit.band(curr_mask, scan_bit) == 0 then
				break
			end

			local next_r, next_c = curr_r + dr, curr_c + dc
			local next_char = canvas.get_char_at(next_r, next_c)
			local next_mask = state.char_to_mask[next_char] or 0
			local opp_scan_bit = C.OPPOSITE_BIT[scan_bit]

			if bit.band(next_mask, opp_scan_bit) == 0 then
				break
			end

			local key = next_r .. "," .. next_c
			if not edges_pos[key] then
				edges_pos[key] = { r = next_r, c = next_c, mask = next_mask }
			end

			curr_r, curr_c = next_r, next_c
		end
	end

	local cursor_key = r .. "," .. c
	edges_pos[cursor_key] = { r = r, c = c, mask = mask }

	for _, d in ipairs(axis_dirs) do
		scan(r, c, d)
	end

	-- 3. 计算变更 (Draw Changes)
	local changes = {}

	for key, node in pairs(edges_pos) do
		-- A. 分离掩码
		local moving_part = bit.band(node.mask, axis_bits) -- 移动的边 (如 │)
		local stationary_part = bit.band(node.mask, bit.bnot(axis_bits)) -- 连接的边 (如 ─)

		-- [关键判断 1] 是否在收缩 (或沿线滑动)
		-- 只要 stationary_part 包含移动方向，就说明是顺着线移动
		local is_collapsing = bit.band(stationary_part, move_bit) ~= 0

		-- [关键判断 2] 是否有尾巴
		-- 检查 stationary_part 是否包含反方向的线 (例如 ├ 包含向上)
		local has_tail = bit.band(stationary_part, rev_bit) ~= 0

		-- === 处理旧位置 (Old Position) ===
		local old_mask_final = stationary_part

		if is_collapsing then
			-- [收缩/滑动模式]
			if not has_tail then
				-- 如果没有尾巴 (如 ┐ 向左)，我们要切断通向新位置的线，实现"擦除"效果
				old_mask_final = bit.band(old_mask_final, bit.bnot(move_bit))
			else
				-- 如果有尾巴 (如 ├ 向下)，我们在沿线滑动，旧位置的线必须保持连通，什么都不用减
				-- old_mask_final 保持 stationary_part 原样 (即 │)
			end
		elseif stationary_part > 0 then
			-- [扩张模式] (如 │ 向右变成 ├)
			-- 拉出一条线指向新位置
			old_mask_final = bit.bor(old_mask_final, move_bit)
		end

		local old_char = mech.resolve_char(0, old_mask_final, 0)
		changes[key] = { r = node.r, c = node.c, char = old_char }

		-- === 处理新位置 (New Position) ===
		local new_r = node.r + move_dr
		local new_c = node.c + move_dc
		local new_key = new_r .. "," .. new_c

		-- 获取目标背景
		local target_mask = 0
		if changes[new_key] then
			target_mask = state.char_to_mask[changes[new_key].char] or 0
		else
			local target_char = canvas.get_char_at(new_r, new_c)
			target_mask = state.char_to_mask[target_char] or 0
		end

		-- [清理背景] 如果是收缩，目标位置原本通向"旧位置"的线段必须被切断
		-- 否则 ┐ 移到 ─ 上会变成 ┬
		if is_collapsing then
			target_mask = bit.band(target_mask, bit.bnot(rev_bit))
		end

		-- 计算新节点的形状
		local new_mask_add = moving_part
		if stationary_part > 0 then
			if is_collapsing then
				-- [收缩/滑动]：新节点应该完全继承旧节点的固定形状
				-- 比如 ├ (Up|Down) 向下移，新节点也应该有 Up|Down
				new_mask_add = bit.bor(new_mask_add, stationary_part)
			else
				-- [扩张]：新节点只需要连回旧位置
				new_mask_add = bit.bor(new_mask_add, rev_bit)
			end
		end

		local new_char = mech.resolve_char(target_mask, new_mask_add, 0)
		changes[new_key] = { r = new_r, c = new_c, char = new_char }
	end

	-- 4. 应用变更
	for _, change in pairs(changes) do
		canvas.set_char_at(change.r, change.c, change.char)
	end
end

function M.move_cursor(direction)
	local r = canvas.get_virt_row()
	local c = canvas.get_virt_col()
	local old_r, old_c = r, c

	r, c = mech.direction_to_coord(direction, r, c)
	if r < 1 then
		r = 1
	end
	if c < 0 then
		c = 0
	end

	-- Expand buffer if needed
	local line_count = vim.api.nvim_buf_line_count(0)
	if r > line_count then
		vim.api.nvim_buf_set_lines(0, line_count, line_count, false, { "" })
	end

	if state.mode == "move" then
		-- 如果新位置和旧位置一样（比如撞墙了），就不执行移动操作
		if r ~= old_r or c ~= old_c then
			M.move_edge_at(direction, old_r, old_c)
		end
	end

	canvas.goto_virt_pos(r, c)

	-- Handle double-width chars movement adjustments
	if direction == "h" and canvas.get_virt_col() == old_c and c > 0 then
		canvas.goto_virt_pos(r, old_c - 2)
	end

	-- Refresh post-move
	r = canvas.get_virt_row()
	c = canvas.get_virt_col()

	-- Drawing Logic
	if (state.mode == "edge" or state.mode == "arrow") and (r ~= old_r or c ~= old_c) then
		local d_mask = C.DIR_KEY_TO_BIT[direction]
		local rev_mask = C.OPPOSITE_BIT[d_mask]

		-- 1. Handle Old Position
		local mask_to_add = d_mask
		local mask_to_remove = 0
		if state.last_dir and state.last_dir ~= direction then
			local last_bit = C.DIR_KEY_TO_BIT[state.last_dir]
			if last_bit then
				mask_to_remove = last_bit
			end
		end
		smart_merge(old_r, old_c, mask_to_add, mask_to_remove)

		-- 2. Handle New Position
		if state.mode == "arrow" then
			local arrow_char = state.parsed_styles[state.style_idx].arrows[d_mask]
			if arrow_char and arrow_char ~= " " then
				canvas.set_char_at(r, c, arrow_char)
			end
		else
			smart_merge(r, c, rev_mask)
		end
	end
	state.last_dir = direction

	-- Status update for selection/box
	if (state.mode == "box" or state.mode == "select") and state.box_start then
		local r1, c1 = state.box_start[1], state.box_start[2]
		local w = math.abs(c - c1) + 1
		local h = math.abs(r - r1) + 1
		local prefix = (state.mode == "box") and "Box" or "Select"
		ui.update_status(string.format("%s: %dx%d", prefix, w, h))
	end
end

function M.draw_box_commit()
	if not state.box_start then
		return
	end
	local r1, c1 = state.box_start[1], state.box_start[2]
	local r2 = canvas.get_virt_row()
	local c2 = canvas.get_virt_col()
	local start_r, end_r = math.min(r1, r2), math.max(r1, r2)
	local start_c, end_c = math.min(c1, c2), math.max(c1, c2)

	local BIT = C.BIT
	smart_merge(start_r, start_c, BIT.R + BIT.D)
	smart_merge(start_r, end_c, BIT.L + BIT.D)
	smart_merge(end_r, start_c, BIT.R + BIT.U)
	smart_merge(end_r, end_c, BIT.L + BIT.U)

	for c = start_c + 1, end_c - 1 do
		smart_merge(start_r, c, BIT.L + BIT.R)
		smart_merge(end_r, c, BIT.L + BIT.R)
	end
	for r = start_r + 1, end_r - 1 do
		smart_merge(r, start_c, BIT.U + BIT.D)
		smart_merge(r, end_c, BIT.U + BIT.D)
	end

	state.box_start = nil
	state.mode = nil
	ui.update_start_marker()
	ui.update_status("Box Drawn")
end

local function get_selection_rect()
	if not state.box_start then
		return nil
	end
	local r1, c1 = state.box_start[1], state.box_start[2]
	local r2, c2 = canvas.get_cursor_virt_pos()
	return { top = math.min(r1, r2), bottom = math.max(r1, r2), left = math.min(c1, c2), right = math.max(c1, c2) }
end

function M.copy_selection()
	local rect = get_selection_rect()
	if not rect then
		return ui.update_status("No selection")
	end

	local lines = {}
	for r = rect.top, rect.bottom do
		local line_str = ""
		for c = rect.left, rect.right do
			line_str = line_str .. canvas.get_char_at(r, c)
		end
		table.insert(lines, line_str)
	end

	state.clipboard = { lines = lines, width = rect.right - rect.left + 1, height = rect.bottom - rect.top + 1 }
	state.box_start = nil
	state.mode = nil
	ui.update_start_marker()
	ui.update_status("Yanked.\nUse <p> to paste.")
end

function M.cut_selection()
	local rect = get_selection_rect()
	if not rect then
		return ui.update_status("No selection")
	end
	M.copy_selection() -- This clears box_start, so use local rect
	for r = rect.top, rect.bottom do
		for c = rect.left, rect.right do
			canvas.set_char_at(r, c, " ")
		end
	end
	ui.update_status("Deleted.\nUse <p> to paste.")
end

function M.paste_clipboard()
	if not state.clipboard then
		return ui.update_status("Clipboard empty.\nUse <v> to select\nand <y> to yank first.")
	end
	local r, c = canvas.get_cursor_virt_pos()
	for i, line_content in ipairs(state.clipboard.lines) do
		local target_r = r + i - 1
		local len_chars = vim.fn.strchars(line_content)
		for j = 1, len_chars do
			local char = vim.fn.strcharpart(line_content, j - 1, 1)
			if char ~= " " then
				canvas.set_char_at(target_r, c + j - 1, char)
			end
		end
	end
	ui.update_status("Pasted")
end

return M
