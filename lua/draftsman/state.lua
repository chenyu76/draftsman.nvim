local M = {}

M.reset = function()
	M.active = false
	M.mode = nil -- nil, 'stroke', 'arrow', 'rectangle', 'visual', 'text'
	M.style_idx = 1
	M.rectangle_start = nil -- {row, virt_col}
	M.text_start_col = 0
	M.last_dir = nil -- last direction
	M.original_ve = ""

	-- UI Handles
	M.canvas_win = nil
	M.sidebar_buf = nil
	M.sidebar_win = nil
	M.ns_id = nil
	M.show_help = false

	M.mapped_keys = {}
	M.old_cr_mapping = nil
	M.clipboard = nil

	-- Cached lookups (populated by mechanics)
	M.parsed_styles = {}
	M.char_to_mask = {}
end

-- Initialize state
M.reset()

return M
