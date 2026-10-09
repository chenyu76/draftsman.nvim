-- Demo data collector: captures the plugin's real behavior for the GIF renderer.
--
-- Lua operates the actual plugin; Python draws the captured results.
local spec = vim.json.decode(table.concat(vim.fn.readfile(vim.env.DRAFTSMAN_GIF_INPUT), "\n"))
vim.opt.swapfile = false
vim.opt.undofile = false
vim.opt.virtualedit = "all"
vim.opt.tabstop = 4
vim.opt.columns = 160
vim.opt.lines = 50
local state = require("draftsman.state")
local canvas = require("draftsman.canvas")
local ui = require("draftsman.ui")
ui.open_sidebar = function()
	state.canvas_win = vim.api.nvim_get_current_win()
end
local result = {}
local function capture(key, duration)
	local row, col = canvas.get_cursor_virt_pos()
	local rect = state.rectangle_start
	return {
		lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
		cursor = { row, col },
		anchor = rect and { rect[1], rect[2] } or vim.NIL,
		mode = state.mode or "ready",
		style = state.style_idx,
		key = key,
		duration = duration,
	}
end
local scenario_index = 0
local function next_scenario()
	scenario_index = scenario_index + 1
	local scenario = spec.scenarios[scenario_index]
	if not scenario then
		vim.fn.writefile({ vim.json.encode(result) }, vim.env.DRAFTSMAN_GIF_OUTPUT)
		vim.cmd("qa!")
		return
	end
	if state.active then
		require("draftsman").stop()
	end
	vim.cmd("enew!")
	local lines = vim.deepcopy(scenario.lines or { "" })
	while #lines < 24 do
		table.insert(lines, "")
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	require("draftsman").start()
	canvas.goto_virt_pos(scenario.cursor[1], scenario.cursor[2])
	local frames = { capture("", spec.timing.start_ms) }
	local keys = {}
	-- Strings expand into individual keys; named keys use <Esc>, <CR>, etc.
	for _, step in ipairs(scenario.steps) do
		local i = 1
		while i <= #step.keys do
			local key = step.keys:sub(i, i)
			if key == "<" then
				local end_pos = assert(step.keys:find(">", i, true), "Unclosed key notation")
				key = step.keys:sub(i, end_pos)
			end
			i = i + #key
			table.insert(keys, { key = key, hold = i > #step.keys and step.hold_ms or nil })
		end
	end
	local key_index = 0
	local function next_key()
		key_index = key_index + 1
		local item = keys[key_index]
		if not item then
			frames[#frames].duration = spec.timing.end_ms
			table.insert(result, { name = scenario.name, frames = frames })
			next_scenario()
			return
		end
		local codes = vim.api.nvim_replace_termcodes(item.key, true, false, true)
		local typing = state.mode == "text" and not item.key:match("^<")
		vim.api.nvim_feedkeys(codes, "mt", false)
		vim.defer_fn(function()
			local moving = item.key:match("^[hjklHJKL]$") and state.mode ~= "text"
			local duration = item.hold
				or (typing and spec.timing.typing_ms or moving and spec.timing.move_ms or spec.timing.key_ms)
			table.insert(frames, capture(item.key, duration))
			next_key()
		end, 10)
	end
	next_key()
end
vim.schedule(next_scenario)
