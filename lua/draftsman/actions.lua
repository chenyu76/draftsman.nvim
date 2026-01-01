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

function M.move_cursor(direction)
	local r = vim.fn.line(".")
	local c = canvas.get_virt_col()
	local old_r, old_c = r, c

	if direction == "h" then
		c = c - 1
	elseif direction == "j" then
		r = r + 1
	elseif direction == "k" then
		r = r - 1
	elseif direction == "l" then
		c = c + 1
	end

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

	canvas.goto_virt_pos(r, c)

	-- Handle double-width chars movement adjustments
	if direction == "h" and canvas.get_virt_col() == old_c and c > 0 then
		canvas.goto_virt_pos(r, old_c - 2)
	end

	-- Refresh post-move
	r = vim.fn.line(".")
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
	local r2 = vim.fn.line(".")
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
	local r2, c2 = vim.fn.line("."), canvas.get_virt_col()
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
	ui.update_status("Copied")
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
	ui.update_status("Cut")
end

function M.paste_clipboard()
	if not state.clipboard then
		return ui.update_status("Clipboard empty")
	end
	local r, c = vim.fn.line("."), canvas.get_virt_col()
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
