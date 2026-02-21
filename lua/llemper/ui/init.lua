local log = require("llemper.logger")
local dmp = require("llemper.dmp")

local M = {}

M.extmarks = {}
local popup_win

function M.clear_ui()
  for _, extmark in ipairs(M.extmarks) do
    log.debug("Clearing", extmark)
    vim.api.nvim_buf_del_extmark(0, _G.ns_id, extmark)
  end
  M.extmarks = {}

  if popup_win and vim.api.nvim_win_is_valid(popup_win) then
    vim.api.nvim_win_close(popup_win, true)
    popup_win = nil
  end
end

---@class DiffDisplayOpts
---@field inline? boolean
---@field overlay? boolean
---@field popup? boolean

---@alias operation
---| 0 # unchanged
---| 1 # insertion
---| -1 # deletion

---@param lines string[]
function M.get_widest(lines)
  local widest = 0
  for _, line in ipairs(lines) do
    local line_width = vim.fn.strdisplaywidth(line)
    if line_width > widest then
      widest = line_width
    end
  end
  return widest
end

---@param extmark_id integer
function M.show_next_edit(extmark_id)
  local suggestion_line = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id2, extmark_id, {})[1]
  local extmark = vim.api.nvim_buf_set_extmark(0, _G.ns_id, suggestion_line, 0, {
    virt_text = { { " S-TAB ", "CursorLine" } },
    virt_text_pos = "eol",
    right_gravity = false,
    strict = false,
  })
  table.insert(M.extmarks, extmark)
end

---Show inline diff in the buffer with extmarks
---@param suggestion Suggestion
---@param has_insertions boolean
---@param has_deletions boolean
function M.show_inline_diff(suggestion, has_insertions, has_deletions)
  local start_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id2, suggestion.extmark_id, {})

  local row = start_pos[1]

  for yi, diff_line in ipairs(suggestion.diff_lines) do
    local col = 0

    for _, diff in ipairs(diff_line) do
      local op, text = diff[1], diff[2]

      if op == 1 and not has_deletions then
        local extmark_add_hl_group = string.find(text, "%S") and "NonText" or "DiffAddBg"
        local extmark = vim.api.nvim_buf_set_extmark(0, _G.ns_id, row + yi - 1, col, {
          virt_text = { { text, extmark_add_hl_group } },
          virt_text_pos = "inline",
          strict = false,
        })
        table.insert(M.extmarks, extmark)
      elseif op == -1 and (has_insertions and has_deletions) then
        local extmark = vim.api.nvim_buf_set_extmark(0, _G.ns_id, row + yi - 1, col, {
          end_col = col + #text,
          hl_group = "DiffDeleteBg",
          hl_mode = "combine",
          strict = false,
        })
        table.insert(M.extmarks, extmark)
      end

      if op ~= 1 then
        col = col + #text
      end
    end
  end
end

---@param suggestion Suggestion
function M.show_popup_diff(suggestion)
  local start_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id2, suggestion.extmark_id, {})
  local text_lines = vim.api.nvim_buf_get_lines(0, start_pos[1], start_pos[1] + #suggestion.diff_lines, false)

  local bufnr = vim.api.nvim_create_buf(false, true)
  local suggestion_lines = vim.split(suggestion.text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, suggestion_lines)

  local row = 0
  for yi, diff_line in ipairs(suggestion.diff_lines) do
    local col = 0

    for _, diff in ipairs(diff_line) do
      local op, text = diff[1], diff[2]

      if op == 1 then
        local extmark = vim.api.nvim_buf_set_extmark(bufnr, _G.ns_id, row + yi - 1, col, {
          end_col = col + #text,
          hl_group = "DiffAddBg",
          hl_mode = "combine",
          strict = false,
        })
        table.insert(M.extmarks, extmark)
      end

      if op ~= -1 then
        col = col + #text
      end
    end
  end

  popup_win = vim.api.nvim_open_win(bufnr, false, {
    win = 0,
    relative = "win",
    width = M.get_widest(suggestion_lines),
    height = #suggestion_lines,
    col = M.get_widest(text_lines) + 2,
    bufpos = { start_pos[1] - 1, 0 },
    anchor = "NW",
    style = "minimal",
    border = "none",
  })

  vim.api.nvim_set_option_value("filetype", vim.bo.filetype, { buf = bufnr })
end

---@param suggestion Suggestion
---@param opts DiffDisplayOpts?
function M.show_diff(suggestion, opts)
  opts = opts or {}

  local has_insertions = false
  local has_deletions = false
  vim.iter(suggestion.diff_lines):flatten():each(function(diff)
    if diff[1] == -1 then
      has_deletions = true
    elseif diff[1] == 1 then
      has_insertions = true
    end
  end)

  M.show_inline_diff(suggestion, has_insertions, has_deletions)

  if has_insertions and has_deletions then
    M.show_popup_diff(suggestion)
  end
end

return M
