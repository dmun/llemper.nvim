local log = require("llemper.logger")
local dmp = require("llemper.dmp")
local ui = require("llemper.ui")
local provider = require("llemper.provider")

local M = {}

---@class Hunk
---@field text string
---@field suggestions Suggestion[]
---@field context Context
---@field startline integer
---@field endline integer

---@class Suggestion
---@field text string
---@field diff Diff[][]

---@class Context
---@field before string
---@field after string

local _suggestion = [[
def flagAllNeighbors(board, row, col): 
  for r, c in board.getNeighbors(row, col):
    if board.isValid(r, c):
      board.flag(r, c)
]]

---@type Hunk[]
local hunks = {}

M.skip = false
M.ignore_count = 0

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
        hunk.file = vim.fn.expand("%:t")
        hunk.context = {
          before = table.concat(vim.api.nvim_buf_get_lines(0, 0, hunk.startline, false), "\n"),
          after = table.concat(vim.api.nvim_buf_get_lines(0, hunk.endline, -1, false), "\n"),
        }

        hunks[1] = hunk

        M.suggest(hunks[1])

        log.debug("hunk", hunk)
      else
        local hunk = hunks[1]
        ui.show_diff(hunk, { inline = true, overlay = true })
      end
    end,
    desc = "Llemper: Show inline diff on text change",
  })

  vim.api.nvim_create_autocmd({ "TextChangedI" }, {
    pattern = "*",
    callback = function()
      M.ignore_count = M.ignore_count + 1

      if M.skip or vim.tbl_isempty(hunks[1].suggestions) then
        M.skip = false
        return
      end

      ui.clear_ui()
      M.update_hunk(hunks[1])

      if M.ignore_count > 3 then
        M.ignore_count = 0
        M.suggest(hunks[1])
      else
        ui.show_diff(hunks[1], { inline = true, overlay = true })
      end
    end,
    desc = "",
  })
end

---@param hunk Hunk
function M.update_hunk(hunk)
  local lines = vim.api.nvim_buf_get_lines(0, hunk.startline, hunk.endline, false)
  hunk.text = table.concat(lines, "\n")
end

---@param hunk Hunk
function M.suggest(hunk)
  vim.print("suggesting..." .. vim.api.nvim_win_get_cursor(0)[2])
  local lines = vim.api.nvim_buf_get_lines(0, hunk.startline, hunk.endline, false)
  hunk.text = table.concat(lines, "\n")

  provider.post(provider.presets.mercury, hunk, function(res)
    hunk.suggestions = {
      { text = res },
    }

    vim.schedule(function()
      ui.clear_ui()
      ui.show_diff(hunk, { inline = true, overlay = true })
    end)
  end)
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
