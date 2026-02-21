local log = require("llemper.logger")
local dmp = require("llemper.dmp")
local ui = require("llemper.ui")
local provider = require("llemper.provider")
local context = require("llemper.context")
local completion = require("llemper.completion")

_G.ns_id = vim.api.nvim_create_namespace("Llemper")
_G.ns_id2 = vim.api.nvim_create_namespace("Llemper2")

local M = {}

M.skip = false
M.ignore_count = 0

function M.setup(opts)
  opts = opts or {}
  opts.debounce = opts.debounce or 200

  dmp.settings({
    Match_Threshold = 0.20,
    Match_Distance = 100,
  })

  vim.keymap.set("i", "<S-Tab>", completion.complete)

  local hl = vim.api.nvim_get_hl(0, { name = "DiffDelete" })
  vim.api.nvim_set_hl(0, "DiffDeleteBg", { bg = hl.bg })

  hl = vim.api.nvim_get_hl(0, { name = "DiffAdd" })
  vim.api.nvim_set_hl(0, "DiffAddBg", { bg = hl.bg })

  log.info("Llemper initialized")

  vim.api.nvim_create_autocmd("InsertEnter", {
    pattern = "*",
    callback = function()
      if vim.tbl_isempty(completion.suggestions) then
        completion.suggest()
      else
        local current_suggestion = completion.get_suggestion_under_cursor()
        completion.show_suggestions(current_suggestion)
      end
    end,
    desc = "Llemper: Show inline diff on text change",
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    pattern = "*",
    callback = function()
      if completion.skip then
        completion.skip = false
        return
      end

      ui.clear_ui()
      local current_suggestion = completion.get_suggestion_under_cursor()
      completion.show_suggestions(current_suggestion)
    end,
    desc = "Llemper: Show inline diff on text change",
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    pattern = "*",
    callback = function()
      context.update_edit_history()
      ui.clear_ui()
    end,
    desc = "Llemper: Clear diff extmarks on InsertLeave",
  })

  vim.api.nvim_create_autocmd("CursorMovedI", {
    pattern = "*",
    callback = function()
      local current_suggestion = completion.get_suggestion_under_cursor()
      completion.show_suggestions(current_suggestion)
      -- completion.suggestions = {}
    end,
    desc = "Llemper: Clear diff extmarks on InsertLeave",
  })
end

return M
