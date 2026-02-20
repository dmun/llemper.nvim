local log = require("llemper.logger")
local provider = require("llemper.provider")
local context = require("llemper.context")
local dmp = require("llemper.dmp")
local ui = require("llemper.ui")

---@class Suggestion
---@field text string|nil
---@field diff_lines DiffLine[]
---@field extmark_id integer
---@field valid boolean

---@class Range
---@field start integer
---@field end integer

local M = {}

---@type Suggestion
M.suggestion = nil

---@type Suggestion[]
M.suggestions = {}

---@alias Diff { [1]: operation, [2]: string }

---@alias DiffLine Diff[]

---@class DiffHunk
---@field offset integer
---@field diff_lines DiffLine[]

---Preprocess diff times to be separated by lines.
---@param diffs Diff[]
---@return Diff[][]
function M.diff_toLines(diffs)
  local processed = {}
  local processed_line = {}

  for _, diff in ipairs(diffs) do
    local op, text = diff[1], diff[2]
    local lines = vim.split(text, "\n", { plain = true })

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

  return processed
end

---@param diff_lines DiffLine[]
---@return DiffHunk[]
function M.diffLines_toHunks(diff_lines)
  local hunks = {}
  local hunk_offset = nil
  local consecutive_lines = {}
  local i = 1

  for j, diff_line in ipairs(diff_lines) do
    local has_change = false

    for _, diff in ipairs(diff_line) do
      if diff[1] ~= 0 then
        has_change = true
        break
      end
    end

    if has_change then
      table.insert(consecutive_lines, diff_line)
      if not hunk_offset then
        hunk_offset = j - 1
      end
    end

    if (not has_change and not vim.tbl_isempty(consecutive_lines)) or j == #diff_lines then
      hunks[i] = {
        offset = hunk_offset,
        diff_lines = consecutive_lines,
      }
      consecutive_lines = {}
      i = i + 1
    end
  end

  return hunks
end

function M.suggest()
  log.info("Suggesting..")
  local ctx = context.get_context()

  provider.request_prediction(provider.presets.mercury, ctx, function(res)
    log.debug(res)

    local diffs = dmp.diff_main(ctx.editable_text, res)
    dmp.diff_cleanupSemantic(diffs)
    dmp.diff_cleanupEfficiency(diffs)
    local diff_lines = M.diff_toLines(diffs)
    local diff_hunks = M.diffLines_toHunks(diff_lines)

    log.debug(diff_hunks)

    vim.schedule(function()
      for _, diff_hunk in ipairs(diff_hunks) do
        local extmark_id = vim.api.nvim_buf_set_extmark(0, _G.ns_id, ctx.editable_range[1] + diff_hunk.offset, 0, {})
        local suggestion_text = vim
          .iter(vim.split(res, "\n"))
          :slice(diff_hunk.offset + 1, diff_hunk.offset + #diff_hunk.diff_lines)
          :join("\n")

        table.insert(M.suggestions, {
          text = suggestion_text,
          diff_lines = diff_hunk.diff_lines,
          extmark_id = extmark_id,
        })
      end

      ui.clear_ui()
      ui.show_diff(M.suggestions[1], { inline = true, overlay = true })
    end)
  end)
end

---@param suggestion Suggestion
function M.complete(suggestion)
  suggestion = suggestion or M.suggestions[1]

  local start_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, suggestion.extmark_id, {})
  local text_lines = vim.api.nvim_buf_get_lines(0, start_pos[1], start_pos[1] + #suggestion.diff_lines, false)

  local diff = vim.text.diff(table.concat(text_lines, "\n"), suggestion.text)
  context.edit_history:push(diff)

  local edits = {
    {
      range = {
        start = {
          line = start_pos[1],
          character = start_pos[2],
        },
        ["end"] = {
          line = start_pos[1] + #suggestion.diff_lines - 1,
          character = math.huge,
        },
      },
      newText = suggestion.text,
    },
  }

  M.skip = true
  vim.lsp.util.apply_text_edits(edits, vim.api.nvim_win_get_buf(0), "utf-8")
  ui.clear_ui()
end

return M
