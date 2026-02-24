local log = require("llemper.logger")
local dmp = require("llemper.dmp")
local ui = require("llemper.ui")
local context = require("llemper.context")
local completion = require("llemper.completion")
local state = require("llemper.state")

local M = {}

local function setup_highlights()
  local hl = vim.api.nvim_get_hl(0, { name = "DiffDelete" })
  vim.api.nvim_set_hl(0, "DiffDeleteBg", { bg = hl.bg })

  hl = vim.api.nvim_get_hl(0, { name = "DiffAdd" })
  vim.api.nvim_set_hl(0, "DiffAddBg", { bg = hl.bg })
end

function M.setup(opts)
  opts = opts or {}
  opts.debounce = opts.debounce or 200

  dmp.settings({
    Match_Threshold = 0.20,
    Match_Distance = 100,
  })

  setup_highlights()

  vim.keymap.set("i", "<S-Tab>", completion.complete)

  log.info("Llemper initialized")

  vim.api.nvim_create_autocmd("InsertEnter", {
    pattern = "*",
    callback = function(ev)
      local buf_state = state.get_buf_state(ev.buf)
      if buf_state.active_suggestion then
        completion.show_suggestions(ev.buf)
      else
        completion.suggest(ev.buf)
      end
    end,
    desc = "Llemper: Show inline diff on text change",
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    pattern = "*",
    callback = function(ev)
      if completion.skip then
        completion.skip = false
        return
      end

      ui.clear_ui(ev.buf)

      local current_suggestion = completion.get_suggestion_under_cursor()
      completion.show_suggestions(current_suggestion)
    end,
    desc = "Llemper: Show inline diff on text change",
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    pattern = "*",
    callback = function(ev)
      context.update_edit_history()
      ui.clear_ui(ev.buf)
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
