local log = require("llemper.logger")
local provider = require("llemper.provider")
local context = require("llemper.context")
local ui = require("llemper.ui")

---@class Suggestion
---@field text string|nil
---@field start_ext integer
---@field end_ext integer
---@field valid boolean

---@class Range
---@field start integer
---@field end integer

local M = {}

---@type Suggestion
M.suggestion = nil

---@type Suggestion[]
M.suggestions = {}

function M.suggest()
  log.info("Suggesting..")

  provider.request_prediction(provider.presets.mercury, function(res)
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
