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
				canvas.set_char_at_cursor(key)
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
		if state.mode == "edge" then
			state.mode = nil
			ui.update_status("Ended Edge Draw.")
		else
			state.mode, state.last_dir = "edge", nil
			ui.update_status("Edge Mode.\n<e> to commit.")
		end
	end)
	map_hybrid("a", function()
		if state.mode == "arrow" then
			state.mode = nil
			ui.update_status("Ended Arrow Draw.")
		else
			state.mode, state.last_dir = "arrow", nil
			ui.update_status("Arrow Mode.\n<a> to commit.")
		end
	end)
	map_hybrid("m", function()
		if state.mode == "move" then
			state.mode = nil
			ui.update_status("Ended Move Mode.")
		else
			state.mode = "move"
			ui.update_status("Move Mode.\n<m> to commit.")
		end
	end)
	map_hybrid("i", function()
		state.mode = "text"
		state.text_start_col = canvas.get_virt_col()
		ui.update_status("Text Input.\n<Esc> to commit.")
	end)
	map_hybrid("x", function()
		canvas.set_char_at_cursor(" ")
	end)

	-- Box/Select
	map_hybrid("b", function()
		if state.mode == "box" then
			actions.draw_box_commit()
		else
			state.mode = "box"
			state.box_start = { canvas.get_virt_row(), canvas.get_virt_col() }
			ui.update_start_marker()
			ui.update_status("Box Draw. \n<b> to commit.")
		end
	end)

	map_hybrid("v", function()
		state.mode = "select"
		state.box_start = { canvas.get_virt_row(), canvas.get_virt_col() }
		ui.update_start_marker()
		ui.update_status("Select. \n<d> to delete. \n<y> to yank. \n<Esc> to cancel.")
	end)

	-- Clipboard
	map_hybrid("d", function()
		if state.mode == "select" then
			actions.cut_selection()
		else
			ui.update_status("Nothing to delete.\nUse <v> first.")
		end
	end)
	map_hybrid("y", function()
		if state.mode == "select" then
			actions.copy_selection()
		else
			ui.update_status("Nothing to yank.\nUse <v> first.")
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
			canvas.set_char_at_cursor("u")
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
		local r, c = canvas.get_cursor_virt_pos()
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

	-- space in text
	safe_map("<Space>", function()
		if state.mode == "text" then
			canvas.set_char_at_cursor(" ")
			vim.cmd("normal! l")
		end
	end)

	-- line break
	safe_map("<CR>", function()
		local r = canvas.get_virt_row()
		local c = state.text_start_col
		canvas.goto_virt_pos(r + 1, c)
	end)

	-- Stop text, visual and box mode if any
	-- Otherwise, exit.
	safe_map("<Esc>", function()
		if state.mode == "text" or state.mode == "select" or state.mode == "box" then
			state.mode, state.box_start = nil, nil
			ui.update_start_marker()
			ui.update_status("Ready.")
		else
			stop_callback()
		end
	end)

	-- Text Input Fallback
	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:;!?-+*/=()[]{}_\"'<>`~@#$%^&"
	for i = 1, #chars do
		local c = chars:sub(i, i)
		if not mapped_chars[c] then
			safe_map(c, function()
				if state.mode == "text" then
					canvas.set_char_at_cursor(c)
					vim.cmd("normal! l")
				end
			end)
		end
	end
end

return M
