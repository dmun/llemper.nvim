local log = require("llemper.logger")
local ringbuf = require("llemper.ringbuf")
local context = require("llemper.context")
-- local completion = require("llemper.completion")

local inception_template = [[
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
---@field prepare_request fun(ctx: Context): table
---@field handle_response fun(string): table

local M = {}

---@type table<string, Preset>
M.presets = {}

M.presets.mercury = {
  url = "https://api.inceptionlabs.ai/v1/edit/completions",
  headers = {
    "Content-Type: application/json",
    "Authorization: Bearer " .. os.getenv("INCEPTION_API_KEY"),
  },
  prepare_request = function(ctx)
    local cursor_tag = "<|cursor|>"

    local content = string.format(
      inception_template,
      "",
      ctx.file,
      ctx.before_context,
      ctx.editable_text_before_cursor .. cursor_tag .. ctx.editable_text_after_cursor,
      ctx.after_context,
      ctx.edit_history
    )

    return {
      model = "mercury-coder",
      messages = {
        {
          role = "user",
          content = content,
        },
      },
    }
  end,
  handle_response = function(data)
    local content = data.choices[1].message.content
    content = content:gsub("```\n", "")
    content = content:gsub("\n```", "")
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
---@param ctx Context
---@param callback function
function M.request_prediction(provider, ctx, callback)
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
  local data = provider.prepare_request(ctx)
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
