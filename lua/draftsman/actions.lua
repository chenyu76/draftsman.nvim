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

--- Moves a connected stroke segment in a specific direction.
--- @param direction string: 'h', 'j', 'k', or 'l'
--- @param r number: row
--- @param c number: col
function M.move_stroke_at(direction, r, c)
	-- Cache external functions and tables for performance
	local get_char = canvas.get_char_at
	local set_char = canvas.set_char_at
	local char_map = state.char_to_mask
	local bor, band, bnot = bit.bor, bit.band, bit.bnot

	-- 0. Validation
	local char = get_char(r, c)
	local mask = char_map[char] or 0

	if mask == 0 then
		if ui and ui.update_status then
			ui.update_status("No stroke to move.\nPlace cursor on an stroke character.")
		end
		return
	end

	-- 1. Prepare Basic Parameters
	local move_dr, move_dc = mech.direction_to_coord(direction)
	local move_bit = C.DIR_KEY_TO_BIT[direction]
	local rev_bit = C.OPPOSITE_BIT[move_bit]

	-- Determine Scan Axis (Perpendicular to movement)
	-- If moving Horizontal (h/l), scan Vertical (j/k), and vice versa.
	local scan_dirs = (direction == "h" or direction == "l") and { "j", "k" } or { "h", "l" }
	local axis_bits = 0
	for _, d in ipairs(scan_dirs) do
		axis_bits = bor(axis_bits, C.DIR_KEY_TO_BIT[d])
	end

	-- 2. Scan the Entire Segment
	-- We collect all connected nodes that share the same perpendicular axis.
	local strokes_pos = {}

	-- Helper to add node
	local function add_node(nr, nc, nmask)
		local key = nr .. "," .. nc
		if not strokes_pos[key] then
			strokes_pos[key] = { r = nr, c = nc, mask = nmask }
		end
	end

	-- Add current cursor position first
	add_node(r, c, mask)

	-- Scan in both perpendicular directions
	for _, scan_dir in ipairs(scan_dirs) do
		local s_dr, s_dc = mech.direction_to_coord(scan_dir)
		local scan_bit = C.DIR_KEY_TO_BIT[scan_dir]
		local opp_scan_bit = C.OPPOSITE_BIT[scan_bit]

		local curr_r, curr_c = r, c

		while true do
			-- Check current node's connectivity in scan direction
			local curr_char = get_char(curr_r, curr_c)
			local curr_mask = char_map[curr_char] or 0
			if band(curr_mask, scan_bit) == 0 then
				break
			end

			-- Check next node's connectivity coming back
			local next_r, next_c = curr_r + s_dr, curr_c + s_dc
			local next_char = get_char(next_r, next_c)
			local next_mask = char_map[next_char] or 0
			if band(next_mask, opp_scan_bit) == 0 then
				break
			end

			add_node(next_r, next_c, next_mask)
			curr_r, curr_c = next_r, next_c
		end
	end

	-- 3. Calculate Changes
	-- We store changes in a map to handle overlapping updates correctly.
	local changes = {}

	for key, node in pairs(strokes_pos) do
		-- A. Separate Mask Components
		-- moving_part: The stroke actually moving (e.g., │ moving sideways)
		-- stationary_part: The connectors staying behind (e.g., ─ connected to │)
		local moving_part = band(node.mask, axis_bits)
		local stationary_part = band(node.mask, bnot(axis_bits))

		-- Are we collapsing? (Moving INTO an existing connection)
		local is_collapsing = band(stationary_part, move_bit) ~= 0

		-- Do we have a tail? (Connection opposite to movement)
		local has_tail = band(stationary_part, rev_bit) ~= 0

		-- === Handle Old Position ===
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

		-- === Handle New Position ===
		local new_r = node.r + move_dr
		local new_c = node.c + move_dc
		local new_key = new_r .. "," .. new_c

		-- Resolve target background
		-- If the target is already in our `changes` table (updated by this loop), use that.
		local target_mask = 0
		if changes[new_key] then
			target_mask = char_map[changes[new_key].char] or 0
		else
			local target_char = get_char(new_r, new_c)
			target_mask = char_map[target_char] or 0
		end

		-- [Clean Background]: If collapsing, ensure we don't have conflicting bits
		if is_collapsing then
			target_mask = band(target_mask, bnot(rev_bit))
		end

		-- Calculate shape at new position
		local new_mask_add = moving_part

		if stationary_part > 0 then
			if is_collapsing then
				-- [Collapse/Slide]: Inherit stationary parts
				local parts_to_add = stationary_part

				-- Prevent extra connections when sliding.
				-- If moving a perpendicular stroke (moving_part > 0) AND there is a connection
				-- in the move direction, that connection is now "traversed" and should be removed.
				-- (Exception: If simply extending a parallel line, keep it).
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

	-- 4. Apply Changes
	for _, change in pairs(changes) do
		set_char(change.r, change.c, change.char)
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
		if r ~= old_r or c ~= old_c then
			M.move_stroke_at(direction, old_r, old_c)
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
	for r = rect.top, rect.bottom do
		local line_str = ""
		for c = rect.left, rect.right do
			line_str = line_str .. canvas.get_char_at(r, c)
		end
		table.insert(lines, line_str)
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
