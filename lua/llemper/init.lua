local log = require("llemper.logger")
local dmp = require("llemper.dmp")
local ui = require("llemper.ui")

local M = {}

M.suggestion = nil
M.line = nil
M.skip = false

function M.setup(opts)
  opts = opts or {}
  opts.debounce = opts.debounce or 200

  dmp.settings({
    Match_Threshold = 0.20,
    Match_Distance = 100,
  })

  vim.keymap.set("i", "<S-Tab>", M.complete)

  local hl = vim.api.nvim_get_hl(0, { name = "DiffDelete" })
  vim.api.nvim_set_hl(0, "DiffDeleteBg", { bg = hl.bg })

  hl = vim.api.nvim_get_hl(0, { name = "DiffAdd" })
  vim.api.nvim_set_hl(0, "DiffAddBg", { bg = hl.bg })

  log.info("Llemper initialized")

  vim.api.nvim_create_autocmd("InsertEnter", {
    pattern = "*",
    callback = function()
      M.suggest()
    end,
    desc = "Llemper: Show inline diff on text change",
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    pattern = "*",
    callback = function()
      if M.skip then
        M.skip = false
        return
      end
      ui.clear_ui()
      M.suggest()
    end,
    desc = "",
  })
end

function M.suggest()
  local text = vim.api.nvim_get_current_line()
  M.line = vim.fn.line(".") - 1
  -- local diff = dmp.diff_main(text, text:sub(1, 4) .. "yep" .. text:sub(8) .. ".setup()")
  -- local suggestion = text:sub(1, 4) .. "yep" .. text:sub(8) .. ".setup()\nrequire('bruh')"
  local suggestion = "veryCoolFunction" .. ".setup()\nrequire('bruh')"
  M.suggestion = suggestion
  local diff = dmp.diff_main(text, suggestion)
  dmp.diff_cleanupSemantic(diff)
  diff = ui.diff_cleanupLines(diff)
  local overlay = vim.iter(diff):flatten(2):any(function(x)
    return x == -1
  end)

  ui.show_diff(text, suggestion, diff, { inline = true, overlay = overlay })
end

function M.complete()
  M.skip = true
  vim.api.nvim_buf_set_lines(0, M.line, M.line + 1, true, vim.split(M.suggestion, "\n"))
  ui.clear_ui()
end

return M
