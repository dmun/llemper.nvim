local log = require("llemper.logger")
local curl = require("plenary.curl")

local M = {}

local context = {
  edit_history = {},
  suggestions = {},
}

local function get_context()
  local ctx = {}

  ctx.bufnr = vim.api.nvim_get_current_buf()
  ctx.bufnr = vim.api.nvim_get_current_buf()

  return ctx
end

local function create_suggestion(ctx)
  ctx.suggestions = ctx.suggestions or {}
end

return M
