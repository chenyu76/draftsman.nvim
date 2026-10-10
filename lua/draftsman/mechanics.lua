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

	local raw = config.options.styles

	for i, grid in ipairs(raw) do
		local parsed = parse_style_grid(grid)
		state.parsed_styles[i] = parsed

		-- Reverse lookup
		for mask, char in pairs(parsed.lines) do
			if char ~= " " then
				state.char_to_mask[char] = bit.bor(state.char_to_mask[char] or 0, mask)
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

-- Resolve the character for a given bitmask, with optional additions/removals
function M.resolve_char(current_mask, add_bits, remove_mask)
	if remove_mask and remove_mask > 0 then
		current_mask = bit.band(current_mask, bit.bnot(remove_mask))
	end
	local final_mask = bit.bor(current_mask, add_bits)
	local palette = state.parsed_styles[state.style_idx].lines
	return palette[final_mask]
end

-- Characters outside the stroke palette have no connections.
function M.char_to_mask(char)
	return state.char_to_mask[char] or 0
end

function M.char_to_direction(char)
	return M.mask_to_direction(M.char_to_mask(char))
end

function M.mask_to_direction(mask)
	if not mask then
		return {}
	end

	local directions = {}
	if bit.band(mask, BIT.U) > 0 then
		table.insert(directions, "k")
	end
	if bit.band(mask, BIT.R) > 0 then
		table.insert(directions, "l")
	end
	if bit.band(mask, BIT.D) > 0 then
		table.insert(directions, "j")
	end
	if bit.band(mask, BIT.L) > 0 then
		table.insert(directions, "h")
	end

	return directions
end

function M.direction_to_coord(direction, r, c)
	r = r or 0
	c = c or 0
	if direction == "h" then
		return r, c - 1
	elseif direction == "j" then
		return r + 1, c
	elseif direction == "k" then
		return r - 1, c
	elseif direction == "l" then
		return r, c + 1
	end
	return r, c
end

-- A connection must be present on both sides of the shared edge.
function M.connected_neighbor(row, col, direction, get_char)
	local direction_bit = C.DIR_KEY_TO_BIT[direction]
	local mask = M.char_to_mask(get_char(row, col))
	if bit.band(mask, direction_bit) == 0 then
		return nil
	end

	local next_r, next_c = M.direction_to_coord(direction, row, col)
	local char = get_char(next_r, next_c)
	local next_mask = M.char_to_mask(char)
	if bit.band(next_mask, C.OPPOSITE_BIT[direction_bit]) == 0 then
		return nil
	end
	return { r = next_r, c = next_c, mask = next_mask, char = char }
end

-- Follow a straight ray; corners and junctions do not change its direction.
function M.scan_stroke(row, col, direction, get_char)
	return function()
		local node = M.connected_neighbor(row, col, direction, get_char)
		if node then
			row, col = node.r, node.c
		end
		return node
	end
end

function M.collect_stroke(row, col, directions, get_char)
	local char = get_char(row, col)
	local mask = M.char_to_mask(char)
	local nodes = {}
	if mask == 0 then
		return nodes
	end
	nodes[row .. "," .. col] = { r = row, c = col, mask = mask, char = char }
	for _, direction in ipairs(directions) do
		for node in M.scan_stroke(row, col, direction, get_char) do
			nodes[node.r .. "," .. node.c] = node
		end
	end
	return nodes
end

-- Compile a comparison once per search. Test endpoints first, then compare
-- cells directly; equal characters imply the same interior connections.
function M.stroke_matcher(row, col, get_char)
	local center = get_char(row, col)
	local rays = {}
	for _, direction in ipairs({ "k", "l", "j", "h" }) do
		local dr, dc = M.direction_to_coord(direction)
		local chars = {}
		for node in M.scan_stroke(row, col, direction, get_char) do
			chars[#chars + 1] = node.char
		end
		rays[#rays + 1] = { direction = direction, dr = dr, dc = dc, chars = chars }
	end
	return function(r, c)
		if get_char(r, c) ~= center then
			return false
		end
		for _, ray in ipairs(rays) do
			local length = #ray.chars
			local end_r, end_c = r + ray.dr * length, c + ray.dc * length
			local end_char = ray.chars[length] or center
			if get_char(end_r, end_c) ~= end_char
				or M.connected_neighbor(end_r, end_c, ray.direction, get_char) then
				return false
			end
		end
		for _, ray in ipairs(rays) do
			for offset, char in ipairs(ray.chars) do
				if get_char(r + ray.dr * offset, c + ray.dc * offset) ~= char then
					return false
				end
			end
		end
		return true
	end
end

return M
