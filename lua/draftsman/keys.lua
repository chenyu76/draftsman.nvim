local state = require("draftsman.state")
local actions = require("draftsman.actions")
local ui = require("draftsman.ui")
local canvas = require("draftsman.canvas")
local config = require("draftsman.config")
local C = require("draftsman.constants")

local M = {}

local function map_and_record(key, callback)
	vim.keymap.set("n", key, callback, { noremap = true, silent = true, buffer = 0, nowait = true })
	table.insert(state.mapped_keys, key)
end

function M.set_mappings(stop_callback)
	state.mapped_keys = {}

	-- Movements
	for _, k in ipairs({ "h", "j", "k", "l" }) do
		map_and_record(k, function()
			actions.move_cursor(k)
		end)
		map_and_record(string.upper(k), function()
			for _ = 1, 5 do
				actions.move_cursor(k)
			end
		end)
	end

	-- Tools
	map_and_record("?", ui.toggle_help)
	map_and_record("e", function()
		if state.mode == "edge" then
			state.mode = nil
			ui.update_status("Ended Edge Draw.")
		else
			state.mode, state.last_dir = "edge", nil
			ui.update_status("Edge Mode.\n<e> to commit.")
		end
	end)
	map_and_record("a", function()
		if state.mode == "arrow" then
			state.mode = nil
			ui.update_status("Ended Arrow Draw.")
		else
			state.mode, state.last_dir = "arrow", nil
			ui.update_status("Arrow Mode.\n<a> to commit.")
		end
	end)
	map_and_record("m", function()
		if state.mode == "move" then
			state.mode = nil
			ui.update_status("Ended Move Mode.")
		else
			state.mode = "move"
			ui.update_status("Move Mode.\n<m> to commit.")
		end
	end)
	map_and_record("i", function()
		state.mode = "text"
		state.text_start_col = canvas.get_virt_col()
		ui.update_status("Text Input.\n<Esc> to finish.")
		vim.cmd("startgreplace")
	end)
	map_and_record("x", function()
		canvas.set_char_at_cursor(" ")
	end)

	-- Box/Select
	map_and_record("b", function()
		if state.mode == "box" then
			actions.draw_box_commit()
		else
			state.mode = "box"
			state.box_start = { canvas.get_virt_row(), canvas.get_virt_col() }
			ui.update_start_marker()
			ui.update_status("Box Draw. \n<b> to commit.")
		end
	end)

	map_and_record("v", function()
		state.mode = "select"
		state.box_start = { canvas.get_virt_row(), canvas.get_virt_col() }
		ui.update_start_marker()
		ui.update_status("Select. \n<d> to delete. \n<y> to yank. \n<Esc> to cancel.")
	end)

	-- Clipboard
	map_and_record("d", function()
		if state.mode == "select" then
			actions.cut_selection()
		else
			ui.update_status("Nothing to delete.\nUse <v> first.")
		end
	end)
	map_and_record("y", function()
		if state.mode == "select" then
			actions.copy_selection()
		else
			ui.update_status("Nothing to yank.\nUse <v> first.")
		end
	end)
	map_and_record("p", actions.paste_clipboard)

	-- Misc
	map_and_record("o", function()
		vim.cmd("put =''")
	end)
	map_and_record("O", function()
		vim.cmd("put! =''")
	end)

	-- Undo/Redo
	map_and_record("u", function()
		if state.mode == "text" then
			canvas.set_char_at_cursor("u")
			vim.cmd("normal! l")
		else
			vim.cmd("undo")
		end
	end)
	-- mapped_chars["u"] = true
	map_and_record("<C-r>", function()
		vim.cmd("redo")
	end)
	map_and_record("<BS>", function()
		local r, c = canvas.get_cursor_virt_pos()
		if c > 0 then
			canvas.set_char_at(r, c - 1, " ")
			canvas.goto_virt_pos(r, c - 1)
		end
	end)

	-- Style Switch
	local num_styles = #(config.options.styles or config.defaults.styles)
	for i = 1, num_styles do
		map_and_record(tostring(i), function()
			state.style_idx = i
			ui.update_status("Style " .. i)
		end)
	end

	-- line break
	-- Record existing <CR> mapping in insert mode, if any
	local existing = vim.fn.maparg("<CR>", "i", false, true)
	if existing and existing.buffer == 1 then
		state.old_cr_mapping = existing
	end
	local cr_func = function()
		if state.mode == "text" then
			canvas.goto_virt_pos(canvas.get_virt_row() + 1, state.text_start_col)
		else
			local key = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
			vim.api.nvim_feedkeys(key, "n", false)
		end
	end
	vim.keymap.set("i", "<CR>", cr_func, { buffer = true })

	-- Stop text, visual and box mode if any
	-- Otherwise, exit.
	map_and_record("<Esc>", function()
		if state.mode == "select" or state.mode == "box" then
			state.mode, state.box_start = nil, nil
			ui.update_start_marker()
			ui.update_status("Ready.")
		else
			stop_callback()
		end
	end)
	-- Monitor InsertLeave to stop text mode
	local group_id = vim.api.nvim_create_augroup(C.TEXT_INPUT_GROUP_NAME, { clear = true })
	vim.api.nvim_create_autocmd("InsertLeave", {
		group = group_id,
		buffer = 0,
		callback = function()
			if state.mode == "text" then
				state.mode = nil
				ui.update_status("Ready.")
			end
		end,
	})
end

return M
