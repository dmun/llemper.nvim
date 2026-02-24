local H = require("llemper.helpers")
local log = require("llemper.logger")
local provider = require("llemper.provider")
local context = require("llemper.context")
local dmp = require("llemper.dmp")
local ui = require("llemper.ui")
local C = require("llemper.constants")
local state = require("llemper.state")

---@class Suggestion
---@field text string|nil
---@field diff_lines DiffLine[]
---@field extmark_id integer

---@class Range
---@field start integer
---@field end integer

local M = {}

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

    if (not has_change or j == #diff_lines) and not vim.tbl_isempty(consecutive_lines) then
      hunks[i] = {
        offset = hunk_offset,
        diff_lines = consecutive_lines,
      }
      hunk_offset = nil
      consecutive_lines = {}
      i = i + 1
    end
  end

  return hunks
end

---@param diffs Diff[]
function M.has_changes(diffs)
  if #diffs == 1 and diffs[1][1] == 0 then
    return false
  end
  return true
end

function M.get_suggestion_under_cursor(cursor)
  local buf_state = state.get_buf_state(0)
  cursor = cursor or H.get_zero_cursor()
  log.debug("Cursor", vim.inspect(cursor))

  for extmark_id, suggestion in pairs(buf_state.suggestions) do
    local extmark = vim.api.nvim_buf_get_extmark_by_id(0, C.hunk_ns_id, extmark_id, {})

    if extmark[1] then
      log.debug("Comparing", { cursor = cursor, extmark = extmark })
      if cursor[1] >= extmark[1] and cursor[1] < extmark[1] + #suggestion.diff_lines then
        log.debug("Found suggestion under cursor with id", extmark_id)
        return suggestion
      end
    end
  end

  log.debug("No suggestion found under cursor", vim.inspect(cursor))
  return nil
end

---@param buffer integer
---@param extmark_id integer
function M.clear_suggestion(buffer, extmark_id)
  local buf_state = state.get_buf_state(buffer)
  vim.api.nvim_buf_del_extmark(buffer, C.hunk_ns_id, extmark_id)
  buf_state.suggestions[extmark_id] = nil
end

---@param buffer integer
function M.show_suggestions(buffer)
  local buf_state = state.get_buf_state(buffer)
  local extmark_id = next(buf_state.suggestions)
  if buf_state.active_suggestion then
    ui.show_diff(buf_state.active_suggestion)
  elseif extmark_id then
    ui.show_next_edit(extmark_id)
  end
end

---@param buffer integer
function M.suggest(buffer)
  log.info("Suggesting for buffer", buffer)
  local ctx = context.get_context()
  local buf_state = state.get_buf_state(buffer)

  provider.request_prediction(provider.presets.mercury, ctx, function(res)
    log.debug("Response", res)

    local diffs = dmp.diff_main(ctx.editable_text, res)
    log.debug(diffs)

    if not M.has_changes(diffs) then
      return
    end

    dmp.diff_cleanupSemantic(diffs)
    dmp.diff_cleanupEfficiency(diffs)
    local diff_lines = M.diff_toLines(diffs)
    local diff_hunks = M.diffLines_toHunks(diff_lines)

    log.debug("Diff hunks", vim.inspect(diff_hunks))

    vim.schedule(function()
      for _, diff_hunk in ipairs(diff_hunks) do
        log.debug("new extmark")

        local extmark_id =
          vim.api.nvim_buf_set_extmark(buffer, C.hunk_ns_id, ctx.editable_range[1] + diff_hunk.offset, 0, {
            right_gravity = false,
            strict = false,
          })

        local suggestion_text = vim
          .iter(vim.split(res, "\n"))
          :slice(diff_hunk.offset + 1, diff_hunk.offset + #diff_hunk.diff_lines)
          :join("\n")

        buf_state.suggestions[extmark_id] = {
          extmark_id = extmark_id,
          text = suggestion_text,
          diff_lines = diff_hunk.diff_lines,
        }
      end

      buf_state.active_suggestion = M.get_suggestion_under_cursor(ctx.cursor_position)
      log.debug("Current suggestion", buf_state.active_suggestion)
      M.show_suggestions(buffer)
    end)
  end)
end

function M.get_new_cursor_position(suggestion)
  local start_pos = vim.api.nvim_buf_get_extmark_by_id(0, C.hunk_ns_id, suggestion.extmark_id, {})
  local last_diff_line = suggestion.diff_lines[#suggestion.diff_lines]
  local col_offset = nil

  vim.iter(last_diff_line):rev():each(function(diff)
    local op, text = diff[1], diff[2]

    if not col_offset and op ~= 0 then
      col_offset = 0
    end

    if col_offset and op ~= -1 then
      col_offset = col_offset + #text
    end
  end)

  local new_cursor_position = {
    start_pos[1] + #suggestion.diff_lines,
    col_offset + 1,
  }

  return new_cursor_position
end

function M.jump_to_next_suggestion(buffer)
  local buf_state = state.get_buf_state(buffer)

  local extmark_id, suggestion = next(buf_state.suggestions)
  if not extmark_id then
    log.info("No next suggestion")
    return
  end
  buf_state.active_suggestion = suggestion
  local new_line = vim.api.nvim_buf_get_extmark_by_id(buffer, C.hunk_ns_id, extmark_id, {})[1]
  local new_col = M.get_new_cursor_position(suggestion)[2]
  vim.fn.cursor(new_line + 1, new_col)
end

---@param buffer integer
function M.complete(buffer)
  buffer = buffer or 0
  local buf_state = state.get_buf_state(buffer)

  if not buf_state.active_suggestion then
    buf_state.active_suggestion = M.get_suggestion_under_cursor()
  end

  if not buf_state.active_suggestion then
    M.jump_to_next_suggestion()
    ui.clear_ui(buffer)
    log.info("No suggestion active")
    return
  end

  local extmark_id = buf_state.active_suggestion.extmark_id
  local start_pos = vim.api.nvim_buf_get_extmark_by_id(buffer, C.hunk_ns_id, extmark_id, {})
  log.debug("start_pos", vim.inspect(start_pos))
  local text_lines =
    vim.api.nvim_buf_get_lines(buffer, start_pos[1], start_pos[1] + #buf_state.active_suggestion.diff_lines, false)

  local diff_text = vim.text.diff(table.concat(text_lines, "\n"), buf_state.active_suggestion.text)
  context.edit_history:push(diff_text)

  local edits = {
    {
      range = {
        start = {
          line = start_pos[1],
          character = start_pos[2],
        },
        ["end"] = {
          line = start_pos[1] + #buf_state.active_suggestion.diff_lines - 1,
          character = math.huge,
        },
      },
      newText = #buf_state.active_suggestion.text,
    },
  }

  -- create undo point
  vim.cmd([[call feedkeys("\<c-g>u", "n")]])

  -- M.skip = true
  vim.lsp.util.apply_text_edits(edits, vim.api.nvim_win_get_buf(0), "utf-8")
  local new_cursor_position = M.get_new_cursor_position(buf_state.active_suggestion)
  vim.fn.cursor(new_cursor_position)
  M.clear_suggestion(buffer, extmark_id)
  ui.clear_ui(buffer)
end

return M
