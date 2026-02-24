local M = {}

-- namespace id for highlights, inline preview, etc
M.ui_ns_id = vim.api.nvim_create_namespace("LlemperUI")

-- namespace id for tracking suggestions
M.hunk_ns_id = vim.api.nvim_create_namespace("LlemperSuggestions")

return M
