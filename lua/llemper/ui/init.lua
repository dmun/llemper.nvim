local log = require("llemper.logger")

local M = {}

local ns_id = vim.api.nvim_create_namespace("llemper_diff")
local extmarks = {}
local popup_win

local function autocommands()
  vim.api.nvim_create_autocmd("InsertLeave", {
    pattern = "*",
    callback = function()
      log.trace("InsertLeave event triggered")
      M.clear_ui()
    end,
    desc = "Llemper: Clear diff extmarks on InsertLeave",
  })
end
autocommands()

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

  log.debug("Processed diff", { processed = processed })
  return processed
end

---@param hunk Hunk
---@param opts DiffDisplayOpts
function M.show_diff(hunk, opts)
  opts = opts or {}

  log.trace("diff", { original = hunk.text, diff = hunk.suggestions[1].diff, opts = opts })

  if opts.inline then
    local start_line = hunk.startline

    for yi, diffs in ipairs(hunk.suggestions[1].diff) do
      local y_offset = yi - 1
      local start_col = 0

      for _, diff in ipairs(diffs) do
        local op, text = diff[1], diff[2]
        log.trace("Processing inline diff", { op = op, text = text })

        if op == 1 and yi == 1 and not opts.overlay then
          local extmark = vim.api.nvim_buf_set_extmark(0, ns_id, start_line, start_col, {
            virt_text = { { text, "NonText" } },
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

    -- local lines = vim.split(suggestion, "\n")
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
    local suggestion_lines = vim.split(hunk.suggestions[1].text, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, suggestion_lines)

    local win_width = 10
    for _, line in ipairs(suggestion_lines) do
      local line_width = vim.fn.strdisplaywidth(line)
      if line_width > win_width then
        win_width = line_width
      end
    end

    for yi, diffs in ipairs(hunk.suggestions[1].diff) do
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
    for _, line in ipairs(vim.split(hunk.text, "\n")) do
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
      bufpos = { hunk.startline - 1, 0 },
      anchor = "NW",
      style = "minimal",
      border = "none",
    })

    vim.api.nvim_set_option_value("filetype", vim.bo.filetype, { buf = bufnr })
  end
end

return M
