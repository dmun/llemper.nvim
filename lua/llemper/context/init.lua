local log = require("llemper.logger")
local ringbuf = require("llemper.ringbuf")

local context = {}

---@class Context
---@field file string
---@field cursor_position [integer, integer] -- {row, col} (0-based)
---@field editable_text string
---@field editable_text_before_cursor string
---@field editable_text_after_cursor string
---@field editable_range [integer, integer]  -- {start_row, end_row}
---@field before_context string
---@field after_context string
---@field edit_history string[]

---@class ContextOpts
---@field context_size integer
---@field editable_region_size integer

local last_buf_state = nil

context.edit_history = ringbuf.new(3)

function context.update_edit_history()
  local cur_buf_state = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  if last_buf_state then
    local diff = vim.text.diff(last_buf_state, cur_buf_state)
    context.edit_history:push(diff)
  end
  last_buf_state = cur_buf_state
end

---@param cursor_position [integer, integer]?
---@param opts ContextOpts?
---@return Context
function context.get_context(cursor_position, opts)
  opts = {
    context_size = 20,
    editable_region_size = 3,
  }

  if not cursor_position then
    cursor_position = vim.api.nvim_win_get_cursor(0)
    -- keep zero-based
    cursor_position[1] = cursor_position[1] - 1
  end

  local line_count = vim.api.nvim_buf_line_count(0)
  local start_row = math.max(cursor_position[1] - opts.editable_region_size, 0)
  local end_row = math.min(cursor_position[1] + opts.editable_region_size, line_count - 1)

  -- editable text before cursor
  local current_line = vim.api.nvim_get_current_line()
  local lines_before = vim.api.nvim_buf_get_lines(0, start_row, cursor_position[1], false)
  table.insert(lines_before, string.sub(current_line, 0, cursor_position[2]))
  local editable_text_before_cursor = table.concat(lines_before, "\n")

  -- editable text after cursor
  local lines_after = vim.api.nvim_buf_get_lines(0, cursor_position[1] + 1, end_row + 1, false)
  table.insert(lines_after, 1, string.sub(current_line, cursor_position[2] + 1))
  local editable_text_after_cursor = table.concat(lines_after, "\n")

  local before_context
  local after_context
  if start_row > 0 then
    before_context = table.concat(vim.api.nvim_buf_get_lines(0, 0, start_row, false), "\n")
  end
  if end_row < line_count then
    after_context = table.concat(vim.api.nvim_buf_get_lines(0, end_row + 1, line_count, false), "\n")
  end

  local edit_history = table.concat(context.edit_history:totable(), "\n")

  return {
    file = vim.fn.expand("%"),
    cursor_position = cursor_position,
    editable_text = editable_text_before_cursor .. editable_text_after_cursor,
    editable_text_before_cursor = editable_text_before_cursor,
    editable_text_after_cursor = editable_text_after_cursor,
    editable_range = { start_row, end_row },
    before_context = before_context,
    after_context = after_context,
    edit_history = edit_history,
  }
end

---@param cursor_position [integer, integer]?
---@return [integer, integer]
function context.get_editable_range(cursor_position)
  if not cursor_position then
    cursor_position = vim.api.nvim_win_get_cursor(0)
    -- keep zero-based
    cursor_position[1] = cursor_position[1] - 1
  end

  local start_row = math.max(cursor_position[1] - 3, 0)
  local end_row = math.min(cursor_position[1] + 3, vim.api.nvim_buf_line_count(0) - 1)

  return { start_row, end_row }
end

return context
