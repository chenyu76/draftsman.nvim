-- Default commands for draftsman.nvim
-- These allow the plugin to be lazy-loaded or used without an explicit setup() call.

vim.api.nvim_create_user_command("DraftsmanStart", function()
	require("draftsman").start()
end, { desc = "Start draftsman" })

vim.api.nvim_create_user_command("DraftsmanStop", function()
	require("draftsman").stop()
end, { desc = "Stop draftsman" })

vim.api.nvim_create_user_command("DraftsmanToggle", function()
	require("draftsman").toggle()
end, { desc = "Toggle draftsman" })
