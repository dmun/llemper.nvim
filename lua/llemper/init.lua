local log = require("llemper.logger")
local dmp = require("llemper.dmp")
local ui = require("llemper.ui")

local M = {}

---@class Hunk
---@field text string
---@field suggestions Suggestion[]
---@field startline integer
---@field endline integer

---@class Suggestion
---@field text string
---@field diff Diff[][]

local _suggestion = [[
def flagAllNeighbors(board, row, col): 
  for r, c in board.getNeighbors(row, col):
    if board.isValid(r, c):
      board.flag(r, c)
]]

---@type Hunk[]
local hunks = {}

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
      if vim.tbl_isempty(hunks) then
        local hunk = {}
        hunk.startline = vim.fn.line(".") - 1
        hunk.endline = hunk.startline + 4
        table.insert(hunks, hunk)
        M.suggest(hunk)
      end

      local hunk = hunks[1]
      ui.show_diff(hunk, { inline = true, overlay = true })
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
      M.suggest(hunks[1])
      ui.show_diff(hunks[1], { inline = true, overlay = true })
    end,
    desc = "",
  })
end

---@param hunk Hunk
function M.suggest(hunk)
  local lines = vim.api.nvim_buf_get_lines(0, hunk.startline, hunk.endline, false)
  hunk.text = table.concat(lines, "\n")

  local diff = dmp.diff_main(hunk.text, _suggestion)
  dmp.diff_cleanupSemantic(diff)
  -- dmp.diff_cleanupEfficiency(diff)
  diff = ui.diff_cleanupLines(diff)

  local suggestion = {
    text = _suggestion,
    diff = diff,
  }

  hunk.suggestions = {}
  hunk.suggestions[1] = suggestion
end

---@pparam hunk Hunk
function M.complete()
  local hunk = hunks[1]
  M.skip = true
  vim.api.nvim_buf_set_lines(0, hunk.startline, hunk.endline, false, vim.split(hunk.suggestions[1].text, "\n"))
  ui.clear_ui()
  hunks = {}
end

return M
