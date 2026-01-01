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
		return
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

-- Calculates the byte range corresponding to a virtual column,
-- handling wide characters and padding
function M.get_byte_range(row, target_virt_col)
	local lines = vim.api.nvim_buf_get_lines(0, row - 1, row, false)
	local line = lines[1] or ""
	local current_virt = 0
	local found_start, found_end = nil, nil
	local len_chars = vim.fn.strchars(line)

	for i = 0, len_chars - 1 do
		local char = vim.fn.strcharpart(line, i, 1)
		local w = vim.fn.strwidth(char)
		if current_virt == target_virt_col then
			found_start = vim.fn.byteidx(line, i)
			found_end = vim.fn.byteidx(line, i + 1)
			break
		elseif current_virt > target_virt_col then
			found_start = vim.fn.byteidx(line, i - 1)
			found_end = vim.fn.byteidx(line, i)
			break
		end
		current_virt = current_virt + w
	end

	if not found_start then
		local pad_len = target_virt_col - vim.fn.strwidth(line)
		pad_len = pad_len < 0 and 0 or pad_len
		local padding = string.rep(" ", pad_len + 1)
		line = line .. padding
		found_start = #lines[1] + pad_len
		found_end = found_start + 1
	end
	return found_start, found_end, line
end

function M.get_char_at(row, virt_col)
	local start_b, end_b = M.get_byte_range(row, virt_col)
	if start_b and end_b then
		local curr_line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
		if start_b >= #curr_line then
			return " "
		end
		return string.sub(curr_line, start_b + 1, end_b)
	end
	return " "
end

function M.set_char_at(row, virt_col, char)
	local cur_r = vim.fn.line(".")
	local cur_c = M.get_virt_col()
	local line_count = vim.api.nvim_buf_line_count(0)

	-- fill empty lines if needed
	if row > line_count then
		local empty = {}
		for _ = 1, (row - line_count) do
			table.insert(empty, "")
		end
		vim.api.nvim_buf_set_lines(0, line_count, line_count, false, empty)
	end

	local start_b, end_b, padded_line = M.get_byte_range(row, virt_col)
	local current_line_content = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""

	if #padded_line > #current_line_content then
		vim.api.nvim_buf_set_lines(0, row - 1, row, false, { padded_line })
	end

	vim.api.nvim_buf_set_text(0, row - 1, start_b, row - 1, end_b or 0, { char })
	M.goto_virt_pos(cur_r, cur_c)
end

function M.get_char_at_cursor()
	return M.get_char_at(M.get_virt_row(), M.get_virt_col())
end

function M.set_char_at_cursor(char)
	M.set_char_at(M.get_virt_row(), M.get_virt_col(), char)
end

return M
