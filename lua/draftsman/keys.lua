local state = require("draftsman.state")
local actions = require("draftsman.actions")
local ui = require("draftsman.ui")
local canvas = require("draftsman.canvas")
local config = require("draftsman.config")

local M = {}

local function safe_map(key, callback)
	vim.keymap.set("n", key, callback, { noremap = true, silent = true, buffer = 0, nowait = true })
	table.insert(state.mapped_keys, key)
end

function M.set_mappings(stop_callback)
	state.mapped_keys = {}
	local mapped_chars = {}

	local function map_hybrid(key, cmd_callback)
		safe_map(key, function()
			if state.mode == "text" then
				canvas.set_char_at(vim.fn.line("."), canvas.get_virt_col(), key)
				vim.cmd("normal! l")
			else
				cmd_callback()
			end
		end)
		mapped_chars[key] = true
	end

	-- Movements
	for _, k in ipairs({ "h", "j", "k", "l" }) do
		map_hybrid(k, function()
			actions.move_cursor(k)
		end)
		map_hybrid(string.upper(k), function()
			for _ = 1, 5 do
				actions.move_cursor(k)
			end
		end)
	end

	-- Tools
	map_hybrid("?", ui.toggle_help)
	map_hybrid("e", function()
		state.mode, state.last_dir = "edge", nil
		ui.update_status("Edge Mode")
	end)
	map_hybrid("a", function()
		state.mode, state.last_dir = "arrow", nil
		ui.update_status("Arrow Mode")
	end)
	map_hybrid("i", function()
		state.mode = "text"
		ui.update_status("Text Input")
	end)
	map_hybrid("x", function()
		canvas.set_char_at(vim.fn.line("."), canvas.get_virt_col(), " ")
	end)

	-- Box/Select
	map_hybrid("b", function()
		if state.mode == "box" then
			actions.draw_box_commit()
		else
			state.mode = "box"
			state.box_start = { vim.fn.line("."), canvas.get_virt_col() }
			ui.update_start_marker()
			ui.update_status("Box Start")
		end
	end)

	map_hybrid("v", function()
		state.mode = "select"
		state.box_start = { vim.fn.line("."), canvas.get_virt_col() }
		ui.update_start_marker()
		ui.update_status("Select Start")
	end)

	-- Clipboard
	map_hybrid("d", function()
		if state.mode == "select" then
			actions.cut_selection()
		else
			ui.update_status("Use 'v' first")
		end
	end)
	map_hybrid("y", function()
		if state.mode == "select" then
			actions.copy_selection()
		else
			ui.update_status("Use 'v' first")
		end
	end)
	map_hybrid("p", actions.paste_clipboard)

	-- Misc
	map_hybrid("o", function()
		vim.cmd("put =''")
	end)
	map_hybrid("O", function()
		vim.cmd("put! =''")
	end)

	-- Undo/Redo
	safe_map("u", function()
		if state.mode == "text" then
			canvas.set_char_at(vim.fn.line("."), canvas.get_virt_col(), "u")
			vim.cmd("normal! l")
		else
			vim.cmd("undo")
		end
	end)
	mapped_chars["u"] = true
	safe_map("<C-r>", function()
		vim.cmd("redo")
	end)
	safe_map("<BS>", function()
		local r, c = vim.fn.line("."), canvas.get_virt_col()
		if c > 0 then
			canvas.set_char_at(r, c - 1, " ")
			canvas.goto_virt_pos(r, c - 1)
		end
	end)

	-- Style Switch
	local num_styles = #(config.options.styles or config.defaults.styles)
	for i = 1, num_styles do
		map_hybrid(tostring(i), function()
			state.style_idx = i
			ui.update_status("Style " .. i)
		end)
	end

	-- Exit/Commit
	safe_map("<Space>", function()
		if state.mode == "box" then
			actions.draw_box_commit()
		elseif state.mode == "select" then
			state.mode, state.box_start = nil, nil
			ui.update_start_marker()
			ui.update_status("Cancelled")
		else
			state.mode = nil
			ui.update_status("Ready")
		end
	end)

	safe_map("<Esc>", stop_callback)

	-- Text Input Fallback
	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:;!?-+*/=()[]{}_\"'<>`~@#$%^&"
	for i = 1, #chars do
		local c = chars:sub(i, i)
		if not mapped_chars[c] then
			safe_map(c, function()
				if state.mode == "text" then
					canvas.set_char_at(vim.fn.line("."), canvas.get_virt_col(), c)
					vim.cmd("normal! l")
				end
			end)
		end
	end
end

return M
