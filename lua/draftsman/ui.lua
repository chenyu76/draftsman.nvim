local state = require("draftsman.state")
local config = require("draftsman.config")
local M = {}

function M.update_status(msg)
	msg = msg or "(Empty)"
	if not state.sidebar_buf or not vim.api.nvim_buf_is_valid(state.sidebar_buf) then
		return
	end

	local info = "Mode: " .. (state.mode or "Ready")
	if state.box_start then
		info = info .. string.format(" (%d,%d)", state.box_start[1], state.box_start[2])
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
		"Info:",
		"  " .. msg,
		"Clipboard:",
	}

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

	if state.show_help then
		local help_items = {
			"Base Tools:",
			" [a]   Arrow",
			" [e]   Edge (Line)",
			" [b]   Box (Rect)",
			" [i]   Text Insert",
			" [ ]   Commit",
			"",
			"Editing Tools:",
			" [x]   Clear Char",
			" [BS]  Backspace",
			" [v]   Select Start",
			" [d]   Delete",
			" [y]   Yank",
			" [p]   Paste",
			" [o/O] New Line",
			"",
			"Other Controls:",
			" [u]    Undo",
			" [^r]   Redo",
			" [hjkl] Move/Draw",
			" [HJKL] Move/Draw Fast",
			" [1-" .. num_styles .. "]  Style",
			" [Esc]  Exit",
		}
		for _, line in ipairs(help_items) do
			table.insert(lines, line)
		end
	else
		table.insert(lines, " [?]   Help")
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
		vim.fn.matchadd("Special", "\\[.\\{-}\\]")
		vim.fn.matchadd("Keyword", "- DIAGRAM MODE -")
		vim.fn.matchadd("Keyword", "---- STATUS ----")
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

function M.update_start_marker()
	if state.ns_id then
		vim.api.nvim_buf_clear_namespace(0, state.ns_id, 0, -1)
	end
	if (state.mode == "select" or state.mode == "box") and state.box_start then
		local r, c = state.box_start[1], state.box_start[2]
		local start_b, _, _ = require("draftsman.canvas").get_byte_range(r, c)
		if start_b then
			local opts = { id = 1, priority = 200, virt_text_pos = "overlay", virt_text = { { "⊕", "MatchParen" } } }
			vim.api.nvim_buf_set_extmark(0, state.ns_id, r - 1, start_b, opts)
		end
	end
end

return M
