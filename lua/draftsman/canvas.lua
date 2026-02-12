local M = {}

function M.get_virt_col()
	return vim.fn.virtcol(".") - 1
end

function M.get_virt_row()
	return vim.fn.line(".")
end

function M.get_cursor_virt_pos()
	return M.get_virt_row(), M.get_virt_col()
end

function M.goto_virt_pos(row, virt_col)
	local line_count = vim.api.nvim_buf_line_count(0)
	if row > line_count then
		local needed_lines = row - line_count
		local empty_lines = {}
		for _ = 1, needed_lines do
			table.insert(empty_lines, "")
		end
		vim.api.nvim_buf_set_lines(0, line_count, line_count, false, empty_lines)
	end

	local curr_r = vim.fn.line(".")
	local curr_c = M.get_virt_col()
	if curr_r == row and curr_c == virt_col then
		return
	end

	vim.api.nvim_win_set_cursor(0, { row, 0 })
	if virt_col > 0 then
		vim.cmd("normal! " .. (virt_col + 1) .. "|")
	end
end

-- return: start_byte, end_byte, line_content, char_width, char_is_tab
function M.get_byte_range(row, target_virt_col)
	local lines = vim.api.nvim_buf_get_lines(0, row - 1, row, false)
	local line = lines[1] or ""
	local tabstop = vim.bo.tabstop

	local current_virt = 0
	local char_idx = 0
	local byte_idx = 0
	local len_chars = vim.fn.strchars(line)

	for i = 0, len_chars - 1 do
		local char = vim.fn.strcharpart(line, i, 1)
		local w = vim.fn.strwidth(char)

		if char == "\t" then
			w = tabstop - (current_virt % tabstop)
		end

		if target_virt_col < current_virt + w then
			local next_byte_idx = vim.fn.byteidx(line, i + 1)
			return byte_idx, next_byte_idx, line, w, (char == "\t")
		end

		current_virt = current_virt + w
		byte_idx = vim.fn.byteidx(line, i + 1)
	end

	local pad_len = target_virt_col - current_virt
	pad_len = pad_len < 0 and 0 or pad_len
	return #line, #line, line, 0, false
end

-- NOTE: get_char_at return " "
-- if out of bounds or at a tab character
function M.get_char_at(row, virt_col)
	local start_b, end_b, line, width, is_tab = M.get_byte_range(row, virt_col)

	if is_tab then
		return " "
	end

	if start_b >= #line then
		return " "
	end

	return string.sub(line, start_b + 1, end_b)
end

function M.set_char_at(row, virt_col, char)
	local cur_r = vim.fn.line(".")
	local cur_c = M.get_virt_col()
	local line_count = vim.api.nvim_buf_line_count(0)

	-- fill empty lines if row exceeds current line count
	if row > line_count then
		local empty = {}
		for _ = 1, (row - line_count) do
			table.insert(empty, "")
		end
		vim.api.nvim_buf_set_lines(0, line_count, line_count, false, empty)
	end

	local start_b, end_b, line, width, is_tab = M.get_byte_range(row, virt_col)

	-- fill spaces if virt_col exceeds current line length
	if start_b == #line and end_b == #line then
		local current_virt_width = 0
		local temp_virt = 0
		local len_chars = vim.fn.strchars(line)
		local tabstop = vim.bo.tabstop
		for i = 0, len_chars - 1 do
			local c = vim.fn.strcharpart(line, i, 1)
			local w = vim.fn.strwidth(c)
			if c == "\t" then
				w = tabstop - (temp_virt % tabstop)
			end
			temp_virt = temp_virt + w
		end

		local pad_len = virt_col - temp_virt
		if pad_len > 0 then
			local padding = string.rep(" ", pad_len)
			line = line .. padding
			vim.api.nvim_buf_set_lines(0, row - 1, row, false, { line })
			start_b, end_b, line, width, is_tab = M.get_byte_range(row, virt_col)
		end
	end

	-- tab need to be expanded before setting character
	if is_tab then
		local expanded_spaces = string.rep(" ", width)
		vim.api.nvim_buf_set_text(0, row - 1, start_b, row - 1, end_b, { expanded_spaces })

		start_b, end_b = M.get_byte_range(row, virt_col)
	end

	if start_b > #vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] then
		return M.set_char_at(row, virt_col, char)
	end

	vim.api.nvim_buf_set_text(0, row - 1, start_b, row - 1, end_b or start_b, { char })

	M.goto_virt_pos(cur_r, cur_c)
end

function M.get_char_at_cursor()
	return M.get_char_at(M.get_virt_row(), M.get_virt_col())
end

function M.set_char_at_cursor(char)
	M.set_char_at(M.get_virt_row(), M.get_virt_col(), char)
end

return M
