local state = require("draftsman.state")
local config = require("draftsman.config")
local mechanics = require("draftsman.mechanics")
local ui = require("draftsman.ui")
local keys = require("draftsman.keys")
local C = require("draftsman.constants")

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
	state.ns_id = vim.api.nvim_create_namespace("draftsman_markers")

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
	local integrations = config.options.integrations or config.defaults.integrations
	if integrations.minisurround then
		vim.b.minisurround_disable = nil
	end
	if integrations.miniai then
		vim.b.miniai_disable = nil
	end
	if integrations.miniindentscope then
		vim.b.miniindentscope_disable = nil
	end
	if integrations.minipairs then
		vim.b.minipairs_disable = nil
	end

	ui.close_sidebar()
	if state.ns_id then
		vim.api.nvim_buf_clear_namespace(0, state.ns_id, 0, -1)
	end

	for _, key in ipairs(state.mapped_keys) do
		pcall(vim.api.nvim_buf_del_keymap, 0, "n", key)
	end

	-- Remove text input monitor
	local group_id = vim.api.nvim_create_augroup(C.TEXT_INPUT_GROUP_NAME, { clear = true })
	vim.api.nvim_del_augroup_by_id(group_id)

	-- Restore old <CR> mapping if any, or delete the new one
	if state.old_cr_mapping then
		local m = state.old_cr_mapping

		local rhs = m.callback or m.rhs

		local opts = {
			buffer = true,
			silent = (m.silent == 1),
			expr = (m.expr == 1),
			nowait = (m.nowait == 1),
			remap = (m.noremap == 0),
			desc = m.desc,
		}

		vim.keymap.set("i", "<CR>", rhs, opts)
	else
		pcall(vim.keymap.del, "i", "<CR>", { buffer = true })
	end
	state.old_cr_mapping = nil

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
