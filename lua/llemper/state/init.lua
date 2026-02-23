local log = require("llemper.logger")

---@class BufferState
---@field active_suggestion Suggestion|nil
---@field suggestions Suggestion[]
---@field ui_extmarks integer[]
---@field popup_win integer|nil
---@field edit_history string[]

local M = {}

---@type BufferState[]
M.buffers = {}

function M.get(buffer)
  if not vim.api.nvim_buf_is_valid(buffer) then
    log.error("Tried getting state of invalid buffer", buffer)
    return
  end

  if not M.buffers[buffer] then
    M.buffers[buffer] = {
      active_suggestion = nil,
      suggestions = {},
      ui_extmarks = {},
      popup_win = nil,
      edit_history = {},
    }
  end

  return M.buffers[buffer]
end

return M
