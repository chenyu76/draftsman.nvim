local M = {}

M.defaults = {
	styles = {
		[1] = {
			[[┌┬┐↑]],
			[[├┼┤│]],
			[[└┴┘↓]],
			[[←─→ ]],
		},
		[2] = {
			[[╔╦╗▲]],
			[[╠╬╣║]],
			[[╚╩╝▼]],
			[[◄═► ]],
		},
		[3] = {
			[[+++^]],
			[[+++|]],
			[[+++v]],
			[[<-> ]],
		},
	},
	integrations = {
		-- disable some builtin mini.nvim plugins to
		-- prevent conflicts
		minisurround = true,
		miniai = true,
		miniindentscope = true,
		minipairs = true,
	},
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
