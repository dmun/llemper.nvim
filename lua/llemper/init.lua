local log = require("llemper.logger")
local dmp = require("llemper.dmp")
local ui = require("llemper.ui")
local provider = require("llemper.provider")
local completion = require("llemper.completion")

_G.ns_id = vim.api.nvim_create_namespace("Llemper")

local M = {}

M.skip = false
M.ignore_count = 0

local last_buf_state = nil

function M.update_edit_history()
  local cur_buf_state = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  if last_buf_state then
    local diff = vim.text.diff(last_buf_state, cur_buf_state)
    log.debug(diff)
    provider._edit_history:push(diff)
  end
  last_buf_state = cur_buf_state
end

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
      completion.suggest()
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

      if not completion.suggestion.text then
        return
      end

      ui.clear_ui()
      ui.show_diff(completion.suggestion, { inline = true, overlay = true })
    end,
    desc = "Llemper: Show inline diff on text change",
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    pattern = "*",
    callback = function()
      M.update_edit_history()
      ui.clear_ui()
    end,
    desc = "Llemper: Clear diff extmarks on InsertLeave",
  })
end

return M
