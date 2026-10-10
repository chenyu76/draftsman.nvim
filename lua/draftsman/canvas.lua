local M = {}

-- Vim groups composing marks with their base character when splitting at \zs.
local function line_cells(line, tabstop)
	local chars = vim.fn.split(line, [[\zs]])
	local index, byte, col = 0, 0, 0
	return function()
		index = index + 1
		local char = chars[index]
		if not char then
			return nil
		end
		local start_byte, start_col = byte, col
		local width = char == "\t" and tabstop - (col % tabstop) or vim.fn.strdisplaywidth(char)
		byte, col = byte + #char, col + width
		return char, start_byte, start_col, width
	end
end

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

	for char, byte, col, width in line_cells(line, tabstop) do
		if target_virt_col < col + width then
			return byte, byte + #char, line, width, char == "\t"
		end
	end

	return #line, #line, line, 0, false
end

-- Tabs and virtual cells past the line end are read as spaces.
function M.get_char_at(row, virt_col)
	local start_b, end_b, line, _, is_tab = M.get_byte_range(row, virt_col)

	if is_tab then
		return " "
	end

	if start_b >= #line then
		return " "
	end

	return string.sub(line, start_b + 1, end_b)
end

-- Reuse within a read phase; cached rows become stale after buffer writes.
function M.char_reader()
	local rows = {}
	local line_count = vim.api.nvim_buf_line_count(0)
	local tabstop = vim.bo.tabstop
	return function(row, col)
		if row < 1 or row > line_count or col < 0 then
			return " "
		end
		local cells = rows[row]
		if not cells then
			cells = {}
			local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
			for char, _, col_start, width in line_cells(line, tabstop) do
				local cell = char == "\t" and " " or char
				for offset = 0, width - 1 do
					cells[col_start + offset] = cell
				end
			end
			rows[row] = cells
		end
		return cells[col] or " "
	end
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
		local pad_len = virt_col - vim.fn.strdisplaywidth(line)
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

	vim.api.nvim_buf_set_text(0, row - 1, start_b, row - 1, end_b, { char })

	M.goto_virt_pos(cur_r, cur_c)
end

function M.get_char_at_cursor()
	return M.get_char_at(M.get_virt_row(), M.get_virt_col())
end

function M.set_char_at_cursor(char)
	M.set_char_at(M.get_virt_row(), M.get_virt_col(), char)
end

return M
