local state = require("draftsman.state")
local config = require("draftsman.config")
local mechanics = require("draftsman.mechanics")
local ui = require("draftsman.ui")
local keys = require("draftsman.keys")
-- local ui_markers = require("draftsman.ui") -- reuse marker logic

local M = {}

M.setup = config.setup

function M.start()
	if state.active then
		return
	end

	mechanics.init_styles()

	state.active = true
	state.original_ve = vim.o.virtualedit
	vim.o.virtualedit = "all"
	state.ns_id = vim.api.nvim_create_namespace("diagram_mode_markers")

	-- Disable interfering plugins temporarily
	local integrations = config.options.integrations or config.defaults.integrations
	if integrations.minisurround then
		vim.b.minisurround_disable = true
	end
	if integrations.miniai then
		vim.b.miniai_disable = true
	end
	if integrations.miniindentscope then
		vim.b.miniindentscope_disable = true
	end
	if integrations.minipairs then
		vim.b.minipairs_disable = true
	end

	ui.open_sidebar()
	keys.set_mappings(M.stop)
	ui.update_status("Ready")
end

function M.stop()
	if not state.active then
		return
	end
	state.active = false
	vim.o.virtualedit = state.original_ve

	-- Re-enable plugins
	vim.b.minisurround_disable = nil
	vim.b.miniai_disable = nil
	vim.b.miniindentscope_disable = nil
	vim.b.minipairs_disable = nil

	ui.close_sidebar()
	if state.ns_id then
		vim.api.nvim_buf_clear_namespace(0, state.ns_id, 0, -1)
	end

	for _, key in ipairs(state.mapped_keys) do
		pcall(vim.api.nvim_buf_del_keymap, 0, "n", key)
	end

	state.reset()
end

function M.toggle()
	if state.active then
		M.stop()
	else
		M.start()
	end
end

return M
