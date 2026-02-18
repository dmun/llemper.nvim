local log = require("llemper.logger")
local provider = require("llemper.provider")
local ui = require("llemper.ui")

---@class Suggestion
---@field text string|nil
---@field start_ext integer
---@field end_ext integer
---@field valid boolean

local M = {}

---@type Suggestion
M.suggestion = nil

function M.suggest()
  log.info("Suggesting..")

  local cur_pos = vim.api.nvim_win_get_cursor(0)
  cur_pos[1] = cur_pos[1] - 1

  local start_row = cur_pos[1] - 2
  local start_ext = vim.api.nvim_buf_set_extmark(0, _G.ns_id, start_row, 0, {})

  -- constrict row because for some reason strict = false doesnt work
  local end_row = math.min(cur_pos[1] + 2, vim.api.nvim_buf_line_count(0) - 1)
  local end_ext = vim.api.nvim_buf_set_extmark(0, _G.ns_id, end_row, -1, {})

  M.suggestion = {
    start_ext = start_ext,
    end_ext = end_ext,
    valid = false,
  }

  provider.post(provider.presets.mercury, M.suggestion, function(res)
    M.suggestion.text = res
    vim.schedule(function()
      ui.clear_ui()
      ui.show_diff(M.suggestion, { inline = true, overlay = true })
    end)
  end)
end

function M.complete()
  local start_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, M.suggestion.start_ext, {})
  local end_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, M.suggestion.end_ext, {})

  local text_lines = vim.api.nvim_buf_get_text(0, start_pos[1], start_pos[2], end_pos[1], end_pos[2], {})
  local orig_text = table.concat(text_lines, "\n")

  local diff = vim.text.diff(orig_text, M.suggestion.text)
  provider._edit_history:push(diff)

  local edits = {
    {
      range = {
        start = {
          line = start_pos[1],
          character = start_pos[2],
        },
        ["end"] = {
          line = end_pos[1],
          character = end_pos[2],
        },
      },
      newText = M.suggestion.text,
    },
  }

  M.skip = true
  vim.lsp.util.apply_text_edits(edits, vim.api.nvim_win_get_buf(0), "utf-8")
  ui.clear_ui()
end

return M
