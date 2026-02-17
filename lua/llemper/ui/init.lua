local log = require("llemper.logger")
local dmp = require("llemper.dmp")
-- local completion = require("llemper.completion")

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

---@param suggestion Suggestion
---@param opts DiffDisplayOpts
function M.show_diff(suggestion, opts)
  opts = opts or {}

  local start_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, suggestion.start_ext, {})
  local end_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, suggestion.end_ext, {})

  local text_lines = vim.api.nvim_buf_get_lines(0, start_pos[1], end_pos[1], false)
  local orig_text = table.concat(text_lines, "\n")

  local dmp_diff = dmp.diff_main(orig_text, suggestion.text)
  dmp.diff_cleanupSemantic(dmp_diff)
  dmp.diff_cleanupEfficiency(dmp_diff)
  dmp_diff = M.diff_cleanupLines(dmp_diff)

  opts.overlay = vim.iter(dmp_diff):flatten():any(function(x)
    return x[1] == 1 or x[1] == -1
  end)

  log.trace("diff", { original = orig_text, diff = dmp_diff, opts = opts })

  if opts.inline then
    local start_line = start_pos[1]

    for yi, diffs in ipairs(dmp_diff) do
      local y_offset = yi - 1
      local start_col = 0

      for _, diff in ipairs(diffs) do
        local op, text = diff[1], diff[2]
        log.trace("Processing inline diff", { op = op, text = text })

        if op == 1 then
          local extmark_add_hl_group = string.find(text, "%S") and "NonText" or "DiffAddBg"
          local extmark = vim.api.nvim_buf_set_extmark(0, ns_id, start_line + y_offset, start_col, {
            virt_text = { { text, extmark_add_hl_group } },
            virt_text_pos = "inline",
            strict = false,
          })
          table.insert(extmarks, extmark)
        elseif op == -1 then
          local extmark = vim.api.nvim_buf_set_extmark(0, ns_id, start_line + y_offset, start_col, {
            end_col = start_col + #text,
            hl_group = "DiffDeleteBg",
            strict = false,
            hl_mode = "combine",
          })
          table.insert(extmarks, extmark)
        end

        start_col = start_col + #text
      end
    end

    -- local lines = vim.split(suggestion.text, "\n")
    -- local extmark = vim.api.nvim_buf_set_extmark(0, ns_id, start_line, 0, {
    --   virt_lines = vim
    --     .iter(lines)
    --     :skip(1)
    --     :map(function(line)
    --       return { { line, "NonText" } }
    --     end)
    --     :totable(),
    --   strict = true,
    -- })
    -- table.insert(extmarks, extmark)
  end

  if opts.overlay then
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

    for yi, diffs in ipairs(dmp_diff) do
      local cur_col = 0
      log.trace("Processing overlay diff lines", { yi = yi, diffs = diffs })
      for _, diff in ipairs(diffs) do
        local op, text = diff[1], diff[2]
        log.trace("Processing overlay diff", { op = op, text = text })

        if op == 1 then
          vim.api.nvim_buf_set_extmark(bufnr, ns_id, yi - 1, cur_col, {
            end_col = cur_col + #text,
            hl_group = "DiffAddBg",
            virt_text_pos = "overlay",
            strict = false,
          })
        end
        if op ~= -1 then
          cur_col = cur_col + #text
        end
      end
    end

    local widest = 0
    for _, line in ipairs(vim.split(orig_text, "\n")) do
      local line_width = vim.fn.strdisplaywidth(line)
      if line_width > widest then
        widest = line_width
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
end

return M
