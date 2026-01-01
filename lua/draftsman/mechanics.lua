local config = require("draftsman.config")
local state = require("draftsman.state")
local C = require("draftsman.constants")
local BIT = C.BIT

local M = {}

local function parse_style_grid(grid)
	local lines, arrows = {}, {}
	local function get(r, c)
		return vim.fn.strcharpart(grid[r], c, 1)
	end

	-- Grid Parsing logic (Mapping characters to bitmasks)
	lines[BIT.D + BIT.R] = get(1, 0)
	lines[BIT.D + BIT.R + BIT.L] = get(1, 1)
	lines[BIT.D + BIT.L] = get(1, 2)
	arrows[BIT.U] = get(1, 3)

	lines[BIT.U + BIT.D + BIT.R] = get(2, 0)
	lines[15] = get(2, 1) -- All directions
	lines[BIT.U + BIT.D + BIT.L] = get(2, 2)
	local v = get(2, 3)
	lines[BIT.U], lines[BIT.D], lines[BIT.U + BIT.D] = v, v, v

	lines[BIT.U + BIT.R] = get(3, 0)
	lines[BIT.U + BIT.R + BIT.L] = get(3, 1)
	lines[BIT.U + BIT.L] = get(3, 2)
	arrows[BIT.D] = get(3, 3)

	arrows[BIT.L] = get(4, 0)
	arrows[BIT.R] = get(4, 2)
	lines[0] = get(4, 3)
	local h = get(4, 1)
	lines[BIT.L], lines[BIT.R], lines[BIT.L + BIT.R] = h, h, h

	return { lines = lines, arrows = arrows }
end

function M.init_styles()
	state.char_to_mask = {}
	state.parsed_styles = {}

	local raw = config.options.styles or config.defaults.styles

	for i, grid in ipairs(raw) do
		local parsed = parse_style_grid(grid)
		state.parsed_styles[i] = parsed

		-- Reverse lookup
		for mask, char in pairs(parsed.lines) do
			if char ~= " " then
				state.char_to_mask[char] = mask
			end
		end

		local a = parsed.arrows
		if a[BIT.U] and a[BIT.U] ~= " " then
			state.char_to_mask[a[BIT.U]] = BIT.D
		end
		if a[BIT.D] and a[BIT.D] ~= " " then
			state.char_to_mask[a[BIT.D]] = BIT.U
		end
		if a[BIT.L] and a[BIT.L] ~= " " then
			state.char_to_mask[a[BIT.L]] = BIT.R
		end
		if a[BIT.R] and a[BIT.R] ~= " " then
			state.char_to_mask[a[BIT.R]] = BIT.L
		end
	end

	state.char_to_mask[" "] = 0
	state.char_to_mask["+"] = 15
end

function M.resolve_char(current_mask, add_bits, remove_mask)
	if remove_mask and remove_mask > 0 then
		current_mask = bit.band(current_mask, bit.bnot(remove_mask))
	end
	local final_mask = bit.bor(current_mask, add_bits)
	local palette = state.parsed_styles[state.style_idx].lines
	return palette[final_mask]
end

return M
