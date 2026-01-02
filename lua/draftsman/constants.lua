local M = {}

-- Bitmasks: Up, Right, Down, Left
M.BIT = { U = 1, R = 2, D = 4, L = 8 }

M.DIR_KEY_TO_BIT = { h = M.BIT.L, j = M.BIT.D, k = M.BIT.U, l = M.BIT.R }

M.OPPOSITE_BIT = {
	[M.BIT.U] = M.BIT.D,
	[M.BIT.D] = M.BIT.U,
	[M.BIT.L] = M.BIT.R,
	[M.BIT.R] = M.BIT.L,
}

M.TEXT_INPUT_GROUP_NAME = "DraftsmanTextInputGroup"

return M
