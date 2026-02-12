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
	cmd = {
		"DraftsmanStart",
		"DraftsmanStop",
		"DraftsmanToggle",
	},
	key = {
		stroke = "s",
		arrow = "a",
		rectangle = "r",
		move = "m",
		insert_text = "i",
	},
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

	if M.options.cmd[1] then
		vim.api.nvim_create_user_command(M.options.cmd[1], function()
			require("draftsman").start()
		end, {})
	end
	if M.options.cmd[2] then
		vim.api.nvim_create_user_command(M.options.cmd[2], function()
			require("draftsman").stop()
		end, {})
	end
	if M.options.cmd[3] then
		vim.api.nvim_create_user_command(M.options.cmd[3], function()
			require("draftsman").toggle()
		end, {})
	end
end

return M
