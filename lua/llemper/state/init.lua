local log = require("llemper.logger")

---@class BufferState
---@field active_suggestion Suggestion|nil
---@field suggestions table<integer, Suggestion>
---@field ui_extmarks integer[]
---@field popup_win integer|nil
---@field edit_history string[]

local M = {}

---@type BufferState[]
M.buffers = {}

---@param buffer integer
---@return BufferState
function M.get_buf_state(buffer)
  if not buffer or buffer == 0 then
    buffer = vim.api.nvim_win_get_buf(0)
  end

  assert(vim.api.nvim_buf_is_valid(buffer), "Tried getting state of invalid buffer")

  if not M.buffers[buffer] then
    M.buffers[buffer] = {
      active_suggestion = nil,
      suggestions = {},
      ui_extmarks = {},
      popup_win = nil,
      edit_history = {},
    }
  end

  log.trace("buf_state", M.buffers[buffer])

  return M.buffers[buffer]
end

return M
