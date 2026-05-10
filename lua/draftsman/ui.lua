local state = require("draftsman.state")
local config = require("draftsman.config")
local canvas = require("draftsman.canvas")
local M = {}

function M.update_status(msg)
	msg = msg or "(Empty)"
	if not state.sidebar_buf or not vim.api.nvim_buf_is_valid(state.sidebar_buf) then
		return
	end

	local info = "Tool: " .. (state.mode or "Ready")
	if state.rectangle_start then
		info = info .. string.format(" (%d,%d)", state.rectangle_start[1], state.rectangle_start[2])
	end

	local style_lines = (config.options.styles or config.defaults.styles)[state.style_idx]

	local display_lines = {
		"Current Style:",
		"  " .. style_lines[1],
		"  " .. style_lines[2],
		"  " .. style_lines[3],
		"  " .. style_lines[4],
		"Status:",
		"  " .. info,
		"Message:",
	}
	-- msg may contain multiple lines, so we need to split it first
	local msg_lines = vim.split(tostring(msg), "\n", { plain = true })
	for _, line in ipairs(msg_lines) do
		table.insert(display_lines, "  " .. line)
	end
	table.insert(display_lines, "Clipboard:")

	if state.clipboard then
		table.insert(display_lines, string.format("  Size: %dx%d", state.clipboard.width, state.clipboard.height))
		for i = 1, math.min(5, #state.clipboard.lines) do
			table.insert(display_lines, "  |" .. state.clipboard.lines[i])
		end
		if #state.clipboard.lines > 5 then
			table.insert(display_lines, "  ...")
		end
	else
		table.insert(display_lines, "  (Empty)")
	end

	local content = vim.api.nvim_buf_get_lines(state.sidebar_buf, 0, -1, false)
	local start_idx = 0
	for i, line in ipairs(content) do
		if line == "---- STATUS ----" then
			start_idx = i
			break
		end
	end
	if start_idx > 0 then
		vim.api.nvim_buf_set_lines(state.sidebar_buf, start_idx, -1, false, display_lines)
	end
end

function M.update_content()
	if not state.sidebar_buf or not vim.api.nvim_buf_is_valid(state.sidebar_buf) then
		return
	end

	local lines = { "- DIAGRAM MODE -" }
	local num_styles = #(config.options.styles or config.defaults.styles)
	local key = config.options.key or config.defaults.key

	if state.show_help then
		local help_items = {
			"Base Tools:",
			" <" .. key.arrow .. ">   Arrow",
			" <" .. key.stroke .. ">   Stroke",
			" <" .. key.rectangle .. ">   Rectangle",
			" <" .. key.insert_text .. ">   Insert Text",
			"",
			"Editing Tools:",
			" <" .. key.move .. ">   Move stroke",
			" <x>   Clear Char",
			-- needless to show
			-- " <BS>  Backspace",
			-- " o/O  Newline",
			" <v>   Visual",
			" <d>   Delete",
			" <y>   Yank",
			" <p/P> Paste",
			"",
			"Other Controls:",
			" <u>    Undo",
			" <C-r>  Redo",
			" hjkl   Move/Draw",
			" HJKL   Move/Draw Fast",
			" 1-" .. num_styles .. "    Style",
			" <Esc>  Exit",
		}
		for _, line in ipairs(help_items) do
			table.insert(lines, line)
		end
	else
		table.insert(lines, " <?>   Help")
	end

	table.insert(lines, "")
	table.insert(lines, "---- STATUS ----")
	vim.api.nvim_buf_set_lines(state.sidebar_buf, 0, -1, false, lines)
	M.update_status()
end

function M.toggle_help()
	state.show_help = not state.show_help
	M.update_content()
end

function M.open_sidebar()
	state.canvas_win = vim.api.nvim_get_current_win()
	state.sidebar_buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.sidebar_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.sidebar_buf })
	vim.api.nvim_set_option_value("filetype", "diagram_help", { buf = state.sidebar_buf })

	M.update_content()

	vim.cmd("botright vsplit")
	vim.cmd("vertical resize 25")
	state.sidebar_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(state.sidebar_win, state.sidebar_buf)

	vim.api.nvim_win_call(state.sidebar_win, function()
		vim.fn.matchadd("Special", "^ <.\\{-}>")
		vim.fn.matchadd("Special", "^ [a-zA-Z0-9][/-][a-zA-Z0-9]")
		vim.fn.matchadd("Special", [[hjkl]])
		vim.fn.matchadd("Special", [[HJKL]])
		vim.fn.matchadd("Title", "- DIAGRAM MODE -")
		vim.fn.matchadd("Title", "---- STATUS ----")
		vim.fn.matchadd("Function", "^.*:")
	end)

	vim.api.nvim_set_option_value("number", false, { win = state.sidebar_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = state.sidebar_win })
	vim.api.nvim_set_option_value("winhl", "Normal:Pmenu", { win = state.sidebar_win })

	if vim.api.nvim_win_is_valid(state.canvas_win) then
		vim.api.nvim_set_current_win(state.canvas_win)
	end
end

function M.close_sidebar()
	if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
		vim.api.nvim_win_close(state.sidebar_win, true)
	end
	state.sidebar_win = nil
	state.sidebar_buf = nil
end

function M.update_visual_markers()
	if state.ns_id then
		vim.api.nvim_buf_clear_namespace(0, state.ns_id, 0, -1)
	end
	if (state.mode == "visual" or state.mode == "rectangle") and state.rectangle_start then
		local r1, c1 = state.rectangle_start[1], state.rectangle_start[2]
		local r2, c2 = canvas.get_virt_row(), canvas.get_virt_col()

		local min_r, max_r = math.min(r1, r2), math.max(r1, r2)
		local min_c, max_c = math.min(c1, c2), math.max(c1, c2)

		local row_data = {} -- r -> { [byte_idx] = { {col, char}, ... } }

		local function add_marker(r, c, char)
			local start_b, _, line_content = canvas.get_byte_range(r, c)
			if not start_b then
				return
			end
			if not row_data[r] then
				row_data[r] = {}
			end
			if not row_data[r][start_b] then
				row_data[r][start_b] = {}
			end
			table.insert(row_data[r][start_b], { col = c, char = char, line = line_content })
		end

		if min_r == max_r and min_c == max_c then
			add_marker(min_r, min_c, "⊕")
		else
			-- Corners
			add_marker(min_r, min_c, "+")
			add_marker(min_r, max_c, "+")
			add_marker(max_r, min_c, "+")
			add_marker(max_r, max_c, "+")

			-- Horizontal edges
			for c = min_c + 1, max_c - 1 do
				add_marker(min_r, c, "-")
				add_marker(max_r, c, "-")
			end

			-- Vertical edges
			for r = min_r + 1, max_r - 1 do
				add_marker(r, min_c, "|")
				add_marker(r, max_c, "|")
			end
		end

		for r, bytes in pairs(row_data) do
			for b, markers in pairs(bytes) do
				table.sort(markers, function(a, b)
					return a.col < b.col
				end)

				local line = markers[1].line
				local start_virt = vim.fn.strdisplaywidth(string.sub(line, 1, b))

				local current_str = ""
				local current_col = start_virt

				for _, m in ipairs(markers) do
					if m.col > current_col then
						current_str = current_str .. string.rep(" ", m.col - current_col)
						current_col = m.col
					end
					if m.col == current_col then
						current_str = current_str .. m.char
						current_col = current_col + vim.fn.strwidth(m.char)
					end
				end

				vim.api.nvim_buf_set_extmark(0, state.ns_id, r - 1, b, {
					virt_text_pos = "overlay",
					virt_text = { { current_str, "MatchParen" } },
					priority = 200,
				})
			end
		end
	end
end

return M
