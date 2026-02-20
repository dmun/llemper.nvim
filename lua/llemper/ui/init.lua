local log = require("llemper.logger")
local dmp = require("llemper.dmp")

local M = {}

local ns_id = vim.api.nvim_create_namespace("llemper_diff")
local extmarks = {}
local popup_win

function M.clear_ui()
  for _, extmark in ipairs(extmarks) do
    vim.api.nvim_buf_del_extmark(0, ns_id, extmark)
  end
  extmarks = {}

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

---@alias Diff { [1]: operation, [2]: string }

--- Preprocess diff itmes to be separated by lines.
---@param diffs Diff[]
---@return Diff[][]
function M.diff_cleanupLines(diffs)
  local processed = {}
  local processed_line = {}

  for _, diff in ipairs(diffs) do
    local op, text = diff[1], diff[2]
    log.trace("Processing diff", { op = op, text = text })

    local lines = vim.split(text, "\n", { plain = true })
    log.trace("Split text into lines", { lines = lines })

    for i, line in ipairs(lines) do
      if i < #lines then
        table.insert(processed_line, { op, line })
        table.insert(processed, processed_line)
        processed_line = {}
      else
        table.insert(processed_line, { op, line })
      end
    end
  end

  if #processed_line > 0 then
    table.insert(processed, processed_line)
    processed_line = {}
  end

  -- log.trace("Processed diff", processed)
  return processed
end

--- Show inline diff in the buffer with extmarks
---@param suggestion Suggestion
---@param has_insertion boolean
---@param has_deletion boolean
---@param line_diffs Diff[][]  -- Pre-processed line-based diffs
function M.show_inline_diff(suggestion, has_insertion, has_deletion, line_diffs)
  local start_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, suggestion.start_ext, {})

  local row = start_pos[1]

  for yi, line_diff in ipairs(line_diffs) do
    local col = 0

    for _, diff in ipairs(line_diff) do
      local op, text = diff[1], diff[2]

      if op == 1 and not has_deletion then
        local extmark_add_hl_group = string.find(text, "%S") and "NonText" or "DiffAddBg"
        local extmark = vim.api.nvim_buf_set_extmark(0, ns_id, row + yi - 1, col, {
          virt_text = { { text, extmark_add_hl_group } },
          virt_text_pos = "inline",
          strict = false,
        })
        table.insert(extmarks, extmark)
      elseif op == -1 then
        local extmark = vim.api.nvim_buf_set_extmark(0, ns_id, row + yi - 1, col, {
          end_col = col + #text,
          hl_group = "DiffDeleteBg",
          hl_mode = "combine",
          strict = false,
        })
        table.insert(extmarks, extmark)
      end

      if op ~= 1 then
        col = col + #text
      end
    end
  end
end

function M.show_popup_diff(suggestion, line_diffs)
  local start_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, suggestion.start_ext, {})
  local end_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, suggestion.end_ext, {})

  local text_lines = vim.api.nvim_buf_get_text(0, start_pos[1], start_pos[2], end_pos[1], end_pos[2], {})
  local orig_text = table.concat(text_lines, "\n")

  local bufnr = vim.api.nvim_create_buf(false, true)
  local suggestion_lines = vim.split(suggestion.text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, suggestion_lines)

  local win_width = 10
  for _, line in ipairs(suggestion_lines) do
    local line_width = vim.fn.strdisplaywidth(line)
    if line_width > win_width then
      win_width = line_width
    end
  end

  local widest = 0
  for _, line in ipairs(vim.split(orig_text, "\n")) do
    local line_width = vim.fn.strdisplaywidth(line)
    if line_width > widest then
      widest = line_width
    end
  end

  local row = 0
  for yi, line_diff in ipairs(line_diffs) do
    local col = 0

    for _, diff in ipairs(line_diff) do
      local op, text = diff[1], diff[2]

      if op == 1 then
        local extmark = vim.api.nvim_buf_set_extmark(bufnr, ns_id, row + yi - 1, col, {
          end_col = col + #text,
          hl_group = "DiffAddBg",
          hl_mode = "combine",
          strict = false,
        })
        table.insert(extmarks, extmark)
      end

      if op ~= -1 then
        col = col + #text
      end
    end
  end

  popup_win = vim.api.nvim_open_win(bufnr, false, {
    win = 0,
    relative = "win",
    width = win_width,
    height = #suggestion_lines,
    col = widest + 2,
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

  local start_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, suggestion.start_ext, {})
  local end_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, suggestion.end_ext, {})

  local text_lines = vim.api.nvim_buf_get_text(0, start_pos[1], start_pos[2], end_pos[1], end_pos[2], {})
  local orig_text = table.concat(text_lines, "\n")

  local diffs = dmp.diff_main(orig_text, suggestion.text)
  dmp.diff_cleanupSemantic(diffs)
  dmp.diff_cleanupEfficiency(diffs)

  local contains_deletion = false
  local contains_insertion = false
  for _, diff in ipairs(diffs) do
    if diff[1] == -1 then
      contains_deletion = true
    elseif diff[1] == 1 then
      contains_insertion = true
    end
  end

  -- Split diffs by lines for proper inline rendering
  diffs = M.diff_cleanupLines(diffs)

  opts.overlay = contains_insertion and contains_deletion

  log.trace("diff", { original = orig_text, diff = diffs, opts = opts })

  if opts.inline then
    M.show_inline_diff(suggestion, contains_insertion, contains_deletion, diffs)
  end

  if opts.overlay then
    M.show_popup_diff(suggestion, diffs)
  end
end

return M
