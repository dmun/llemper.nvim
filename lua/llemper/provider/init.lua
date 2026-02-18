local log = require("llemper.logger")
local ringbuf = require("llemper.ringbuf")
-- local completion = require("llemper.completion")

local inception = [[
<|recently_viewed_code_snippets|>
%s
<|/recently_viewed_code_snippets|>

<|current_file_content|>
current_file_path: %s
%s
<|code_to_edit|>
%s
<|/code_to_edit|>
%s
<|/current_file_content|>

<|edit_diff_history|>
%s
<|/edit_diff_history|>
]]

---@class Preset
---@field url string
---@field headers string[]
---@field prepare_request fun(suggestion: Suggestion): table
---@field handle_response fun(string): table

local M = {}

M._edit_history = ringbuf.new(5)

---@type table<string, Preset>
M.presets = {}

M.presets.mercury = {
  url = "https://api.inceptionlabs.ai/v1/edit/completions",
  headers = {
    "Content-Type: application/json",
    "Authorization: Bearer " .. os.getenv("INCEPTION_API_KEY"),
  },
  prepare_request = function(suggestion)
    local cur_pos = vim.api.nvim_win_get_cursor(0)
    local start_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, suggestion.start_ext, {})
    local end_pos = vim.api.nvim_buf_get_extmark_by_id(0, _G.ns_id, suggestion.end_ext, {})

    local cur_line = vim.api.nvim_get_current_line()
    local text_before_cur = string.sub(cur_line, 0, cur_pos[2])
    local text_after_cur = string.sub(cur_line, cur_pos[2] + 1)

    local lines_before = vim.api.nvim_buf_get_lines(0, start_pos[1], cur_pos[1] - 1, false)
    local lines_after = vim.api.nvim_buf_get_lines(0, cur_pos[1], end_pos[1] + 1, false)

    local context_before = vim.api.nvim_buf_get_lines(0, 0, start_pos[1], false)
    local context_after = vim.api.nvim_buf_get_lines(0, end_pos[1] + 1, -1, false)

    local text_lines = {}
    table.insert(text_lines, table.concat(lines_before, "\n"))
    table.insert(text_lines, text_before_cur .. "<|cursor|>" .. text_after_cur)
    table.insert(text_lines, table.concat(lines_after, "\n"))
    local text = table.concat(text_lines, "\n")

    local edit_history = {}
    for diff in M._edit_history:iter() do
      table.insert(edit_history, diff)
    end

    return {
      model = "mercury-coder",
      messages = {
        {
          role = "user",
          content = string.format(
            inception,
            "",
            vim.fn.expand("%"),
            table.concat(context_before, "\n"),
            text,
            table.concat(context_after, "\n"),
            table.concat(edit_history, "\n")
          ),
        },
      },
    }
  end,
  handle_response = function(data)
    local content = data.choices[1].message.content
    content = content:gsub("```\n", "")
    content = content:gsub("\n```", "")
    content = content:gsub("<|code_to_edit|>", "")
    -- content = content:gsub("^%s+", "")
    -- content = content:gsub("%s+$", "")

    return content
  end,
}

M.presets.codestral = {
  url = "https://api.mistral.ai/v1/fim/completions",
  headers = {
    "Content-Type: application/json",
    "Accept: application/json",
    "Authorization: Bearer " .. os.getenv("MISTRAL_API_KEY"),
  },
  prepare_request = function(ctx)
    return {
      model = "codestral-latest",
      prompt = ctx.prefix,
      suffix = ctx.suffix,
      temperature = 0.1,
      stop = { "\n>>", ">>>>", "\n\n" },
      max_tokens = 96,
    }
  end,
  handle_response = function(data)
    vim.g.total_tokens = vim.g.total_tokens + data.usage.total_tokens
    local input_cost = 0.2
    local output_cost = 0.6
    local cost = (data.usage.prompt_tokens * input_cost + data.usage.completion_tokens * output_cost) / 1000000

    log.info("Session tokens: ", vim.g.total_tokens)
    log.info("Session cost: $", string.format("%.6f", cost))

    return data.choices[1].message.content:gsub("█", "")
  end,
}

---@class Response.Mercury
---@field id string
---@field object string
---@field created number
---@field model string
---@field choices table[]
---@field usage table
---@field warning string|nil

---@class Response.Mercury.Usage
---@field prompt_tokens number
---@field reasoning_tokens number
---@field completion_tokens number
---@field total_tokens number

---@class Response.Mercury.Choice
---@field index number
---@field message table
---@field finish_reason string

---@param provider Preset
---@param suggestion Suggestion
---@param callback function
function M.post(provider, suggestion, callback)
  local headers = vim
    .iter(provider.headers)
    :map(function(header)
      return { "-H", header }
    end)
    :flatten()
    :totable()

  local command = { "curl", provider.url, "-X", "POST" }
  vim.list_extend(command, headers)
  table.insert(command, "-d")
  local data = provider.prepare_request(suggestion)
  log.debug(data.messages[1].content)
  table.insert(command, vim.json.encode(data))

  vim.system(command, {}, function(res)
    if not res.stdout then
      log.error("no stdout")
      return
    end

    local data = vim.json.decode(res.stdout)
    log.debug("response")
    if provider.handle_response then
      local content = provider.handle_response(data)
      callback(content)
    else
      callback(data)
    end
  end)
end

return M
