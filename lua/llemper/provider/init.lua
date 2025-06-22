local log = require("llemper.logger")

local M = {}

M.presets = {}

M.presets.codestral = {
  url = "https://api.mistral.ai/v1/fim/completions",
  headers = {
    "Content-Type: application/json",
    "Accept: application/json",
    "Authorization: Bearer " .. os.getenv("MISTRAL_API_KEY"),
  },
  handle_context = function(ctx)
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

function M.post(provider, content, callback)
  local command = {
    "curl",
    provider.url,
    "-X",
    "POST",
    unpack(vim.tbl_map(function(header)
      return "-H" .. header
    end, provider.headers)),
    '"Content-Type: application/json"',
    "-d",
    vim.json.encode(content),
  }
  vim.system(command:concat(" "), {}, callback)
end

return M
