local state = require("draftsman.state")
local canvas = require("draftsman.canvas")
local mech = require("draftsman.mechanics")
local ui = require("draftsman.ui")
local C = require("draftsman.constants")

local M = {}

-- Helper: Update a char based on neighbor bitmask
local function smart_merge(row, virt_col, new_mask_bits, mask_to_remove)
	local current_char = canvas.get_char_at(row, virt_col)
	local current_mask = mech.char_to_mask(current_char)
	local new_char = mech.resolve_char(current_mask, new_mask_bits, mask_to_remove)
	if new_char then
		canvas.set_char_at(row, virt_col, new_char)
	end
end

--- Moves a connected stroke segment in a specific direction.
--- @param direction string: 'h', 'j', 'k', or 'l'
--- @param row number: row
--- @param col number: virtual column
function M.move_stroke_at(direction, row, col)
	local next_row, next_col = mech.direction_to_coord(direction, row, col)
	if next_row < 1 or next_col < 0 then
		return row, col
	end
	local get_char = canvas.char_reader()
	local set_char = canvas.set_char_at
	local bor, band, bnot = bit.bor, bit.band, bit.bnot

	local char = get_char(row, col)
	local mask = mech.char_to_mask(char)

	if mask == 0 then
		ui.update_status("No stroke to move.\nPlace cursor on a stroke character.")
		return row, col
	end

	local move_dr, move_dc = mech.direction_to_coord(direction)
	local move_bit = C.DIR_KEY_TO_BIT[direction]
	local rev_bit = C.OPPOSITE_BIT[move_bit]

	-- Move only the segment perpendicular to the movement direction.
	local scan_dirs = (direction == "h" or direction == "l") and { "j", "k" } or { "h", "l" }
	local axis_bits = 0
	for _, d in ipairs(scan_dirs) do
		axis_bits = bor(axis_bits, C.DIR_KEY_TO_BIT[d])
	end

	local strokes_pos = mech.collect_stroke(row, col, scan_dirs, get_char)

	-- Compute all changes before writing, since source and target cells overlap.
	local changes = {}

	for key, node in pairs(strokes_pos) do
		-- moving_part: The stroke actually moving (e.g., │ moving sideways)
		-- stationary_part: The connectors staying behind (e.g., ─ connected to │)
		local moving_part = band(node.mask, axis_bits)
		local stationary_part = band(node.mask, bnot(axis_bits))

		local is_collapsing = band(stationary_part, move_bit) ~= 0

		local has_tail = band(stationary_part, rev_bit) ~= 0

		local old_mask_final = stationary_part

		if is_collapsing then
			-- [Collapse/Slide Mode]: Remove the connection we are moving towards
			if not has_tail then
				old_mask_final = band(old_mask_final, bnot(move_bit))
			end
			-- If has_tail is true, we keep the line continuous (sliding along it)
		elseif stationary_part > 0 then
			-- [Expand Mode]: Leave a trail behind
			old_mask_final = bor(old_mask_final, move_bit)
		end

		local old_char = mech.resolve_char(0, old_mask_final, 0)
		changes[key] = { r = node.r, c = node.c, char = old_char }

		local new_r = node.r + move_dr
		local new_c = node.c + move_dc
		local new_key = new_r .. "," .. new_c

		-- Pending changes take precedence over the original buffer.
		local target_mask = 0
		if changes[new_key] then
			target_mask = mech.char_to_mask(changes[new_key].char)
		else
			local target_char = get_char(new_r, new_c)
			target_mask = mech.char_to_mask(target_char)
		end

		-- [Clean Background]: If collapsing, ensure we don't have conflicting bits
		if is_collapsing then
			target_mask = band(target_mask, bnot(rev_bit))
		end

		local new_mask_add = moving_part

		if stationary_part > 0 then
			if is_collapsing then
				-- [Collapse/Slide]: Inherit stationary parts
				local parts_to_add = stationary_part

				-- Sliding a perpendicular segment consumes its forward connection.
				if moving_part > 0 then
					parts_to_add = band(parts_to_add, bnot(move_bit))
				end

				new_mask_add = bor(new_mask_add, parts_to_add)
			else
				-- [Expand]: Connect back to the old position
				new_mask_add = bor(new_mask_add, rev_bit)
			end
		end

		local new_char = mech.resolve_char(target_mask, new_mask_add, 0)
		changes[new_key] = { r = new_r, c = new_c, char = new_char }
	end

	for _, change in pairs(changes) do
		set_char(change.r, change.c, change.char)
	end
	return next_row, next_col
end

-- Choose the last connected direction before a gap, scanning clockwise from right.
function M.jump_stroke_ends()
	local r, c = canvas.get_cursor_virt_pos()
	local get_char = canvas.char_reader()

	local mask = mech.char_to_mask(get_char(r, c))
	if mask == 0 then
		local count = vim.v.count > 0 and tostring(vim.v.count) or ""
		vim.cmd("normal! " .. count .. "%")
		return
	end

	local directions = { "l", "j", "h", "k" }
	local selected_direction
	-- Two passes allow the connected run to wrap around to right.
	for i = 1, #directions * 2 do
		local direction = directions[(i - 1) % #directions + 1]
		if mech.connected_neighbor(r, c, direction, get_char) then
			selected_direction = direction
		elseif selected_direction then
			break
		end
	end
	selected_direction = selected_direction or directions[1]

	for node in mech.scan_stroke(r, c, selected_direction, get_char) do
		r, c = node.r, node.c
	end
	canvas.goto_virt_pos(r, c)
	state.last_dir = nil
	ui.update_visual_markers()
end

function M.search_stroke(backward)
	local r, c = canvas.get_cursor_virt_pos()
	local get_char = canvas.char_reader()
	local char = get_char(r, c)
	if mech.char_to_mask(char) == 0 then
		local count = vim.v.count > 0 and tostring(vim.v.count) or ""
		vim.cmd("normal! " .. count .. (backward and "#" or "*"))
		return
	end

	local matches = mech.stroke_matcher(r, c, get_char)
	local pattern = "\\C\\V" .. vim.fn.escape(char, "\\")
	local flags = backward and "b" or ""
	local origin = vim.fn.getpos(".")
	local moved = false
	for _ = 1, vim.v.count1 do
		local before = vim.api.nvim_win_get_cursor(0)
		local found = vim.fn.searchpos(pattern, flags, 0, 0, function()
			local row, col = canvas.get_cursor_virt_pos()
			return not matches(row, col)
		end)
		if found[1] == 0 or vim.deep_equal(before, vim.api.nvim_win_get_cursor(0)) then
			break
		end
		moved = true
	end
	if moved then
		vim.fn.setpos("''", origin)
		state.last_dir = nil
		ui.update_visual_markers()
	else
		ui.update_status("No other matching stroke.")
	end
end

function M.open_line(above)
	local r, c = canvas.get_cursor_virt_pos()
	vim.cmd(above and "put! =''" or "put =''")
	canvas.goto_virt_pos(above and r or r + 1, c)
	state.last_dir = nil
	ui.update_visual_markers()
end

function M.move_word_at(direction, row, col)
	local next_row, next_col = mech.direction_to_coord(direction, row, col)
	if next_row < 1 or next_col < 0 then
		return row, col
	end
	local word, start_col, width = canvas.word_at(row, col)
	if word then
		local target_row, target_col = mech.direction_to_coord(direction, row, start_col)
		if target_col < 0 then
			return row, col
		end
		-- Clear first so horizontal moves can overlap the original word.
		canvas.replace_span(row, start_col, width, string.rep(" ", width))
		canvas.replace_span(target_row, target_col, width, word)
	end
	return next_row, next_col
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
		if r ~= old_r or c ~= old_c then
			if mech.char_to_mask(canvas.get_char_at(old_r, old_c)) ~= 0 then
				r, c = M.move_stroke_at(direction, old_r, old_c)
			else
				r, c = M.move_word_at(direction, old_r, old_c)
			end
		end
	end

	canvas.goto_virt_pos(r, c)

	-- Handle double-width chars movement adjustments
	if direction == "h" and c < old_c and canvas.get_virt_col() == old_c and c > 0 then
		canvas.goto_virt_pos(r, old_c - 2)
	end

	-- Refresh post-move
	r = canvas.get_virt_row()
	c = canvas.get_virt_col()

	-- Drawing Logic
	if (state.mode == "stroke" or state.mode == "arrow") and (r ~= old_r or c ~= old_c) then
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

	-- Status update for visualization/rectangle
	if (state.mode == "rectangle" or state.mode == "visual") and state.rectangle_start then
		local r1, c1 = state.rectangle_start[1], state.rectangle_start[2]
		local w = math.abs(c - c1) + 1
		local h = math.abs(r - r1) + 1
		local prefix = (state.mode == "rectangle") and "rectangle" or "visual"
		ui.update_status(string.format("%s: %dx%d", prefix, w, h))
		ui.update_visual_markers()
	end
end

function M.draw_rectangle_commit()
	if not state.rectangle_start then
		return
	end
	local r1, c1 = state.rectangle_start[1], state.rectangle_start[2]
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

	state.rectangle_start = nil
	state.mode = nil
	ui.update_visual_markers()
	ui.update_status("rectangle Drawn")
end

local function get_visualization_rect()
	if not state.rectangle_start then
		return nil
	end
	local r1, c1 = state.rectangle_start[1], state.rectangle_start[2]
	local r2, c2 = canvas.get_cursor_virt_pos()
	return { top = math.min(r1, r2), bottom = math.max(r1, r2), left = math.min(c1, c2), right = math.max(c1, c2) }
end

function M.copy_visualization()
	local rect = get_visualization_rect()
	if not rect then
		return ui.update_status("No visualization")
	end

	local lines = {}
	local get_char = canvas.char_reader()
	for r = rect.top, rect.bottom do
		local chars = {}
		for c = rect.left, rect.right do
			chars[#chars + 1] = get_char(r, c)
		end
		lines[#lines + 1] = table.concat(chars)
	end

	state.clipboard = { lines = lines, width = rect.right - rect.left + 1, height = rect.bottom - rect.top + 1 }
	state.rectangle_start = nil
	state.mode = nil
	ui.update_visual_markers()
	ui.update_status("Yanked.\nUse <p> or <P> to paste.")
end

function M.cut_visualization()
	local rect = get_visualization_rect()
	if not rect then
		return ui.update_status("No visualization")
	end
	M.copy_visualization() -- This clears rectangle_start, so use local rect
	for r = rect.top, rect.bottom do
		for c = rect.left, rect.right do
			canvas.set_char_at(r, c, " ")
		end
	end
	ui.update_status("Deleted.\nUse <p> or <P> to paste.")
end

function M.paste_clipboard(reverse_row, reverse_col)
	if not state.clipboard then
		return ui.update_status("Clipboard empty.\nUse <v> to visual\nand <y> to yank first.")
	end

	local row_offset = reverse_row and -(state.clipboard.height - 1) or 0
	local col_offset = reverse_col and -(state.clipboard.width - 1) or 0

	local r, c = canvas.get_cursor_virt_pos()
	r = r + row_offset
	c = c + col_offset

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
