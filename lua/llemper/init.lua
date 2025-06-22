local log = require("llemper.logger")
local dmp = require("llemper.dmp")
local ui = require("llemper.ui")

local M = {}

function M.setup(opts)
  opts = opts or {}
  opts.debounce = opts.debounce or 200

  dmp.settings({
    Match_Threshold = 0.20,
    Match_Distance = 100,
  })

  local hl = vim.api.nvim_get_hl(0, { name = "DiffDelete" })
  vim.api.nvim_set_hl(0, "DiffDeleteBg", { bg = hl.bg })

  hl = vim.api.nvim_get_hl(0, { name = "DiffAdd" })
  vim.api.nvim_set_hl(0, "DiffAddBg", { bg = hl.bg })

  log.info("Llemper initialized")

  vim.api.nvim_create_autocmd("InsertEnter", {
    pattern = "*",
    callback = function()
      local text = vim.api.nvim_get_current_line()
      -- local diff = dmp.diff_main(text, text:sub(1, 4) .. "yep" .. text:sub(8) .. ".setup()")
      local suggestion = text:sub(1, 4) .. "yep" .. text:sub(8) .. ".setup()\nrequire('bruh')"
      local diff = dmp.diff_main(text, suggestion)
      dmp.diff_cleanupSemantic(diff)
      diff = ui.diff_cleanupLines(diff)
      ui.show_diff(text, suggestion, diff, { inline = true, overlay = true })
    end,
    desc = "Llemper: Show inline diff on text change",
  })
end

return M
