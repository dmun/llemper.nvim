local M = {}

local log_file = vim.fn.stdpath("state") .. "/llemper.log"

local function write_log(level, msg, data)
  data = data or {}

  if #data == 1 then
    data = data[1]
  elseif #data > 1 and data[1] then
    data = { data = data }
  end

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

function M.debug(...)
  write_log("DEBUG", ...)
end

function M.info(...)
  write_log("INFO", ...)
end

function M.warn(...)
  write_log("WARN", ...)
end

function M.error(...)
  write_log("ERROR", ...)
end

function M.trace(...)
  write_log("TRACE", ...)
end

return M
