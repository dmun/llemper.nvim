local M = {}

local log_file = vim.fn.stdpath("state") .. "/llemper.log"

local function write_log(level, msg, data)
  data = data or {}

  local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")

  data.TIME = timestamp
  data.LEVEL = level
  data.MESSAGE = msg

  local info = debug.getinfo(3, "nSl")
  data.LOGGER = string.match(info.short_src, "llemper/(.*)/init.lua")

  if level == "TRACE" or level == "ERROR" then
    local src = string.gsub(info.short_src, "(.*)llemper/", " "):sub(1, -5)
    data.CALLER = string.format("%s:%d %s()", src, info.currentline, info.name or "<anonymous>")
  end

  vim.schedule(function()
    local json = vim.fn.json_encode(data) .. "\n"
    local file = io.open(log_file, "a")
    if file then
      file:write(json)
      file:close()
    end
  end)
end

function M.debug(msg, data)
  write_log("DEBUG", msg, data)
end

function M.info(msg, data)
  write_log("INFO", msg, data)
end

function M.warn(msg, data)
  write_log("WARN", msg, data)
end

function M.error(msg, data)
  write_log("ERROR", msg, data)
end

function M.trace(msg, data)
  write_log("TRACE", msg, data)
end

return M
