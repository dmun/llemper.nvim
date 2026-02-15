local M = {}

M.__index = M

function M.new(size)
  return setmetatable({
    data = {},
    max_size = size,
    head = 1,
    count = 0,
  }, M)
end

function M:push(item)
  self.data[self.head] = item

  self.head = (self.head % self.max_size) + 1

  if self.count < self.max_size then
    self.count = self.count + 1
  end
end

function M:get(i)
  if i < 1 or i > self.count then
    return nil
  end

  local offset = (self.count < self.max_size) and 0 or (self.head - 1)
  local physical_idx = ((offset + i - 1) % self.max_size) + 1

  return self.data[physical_idx]
end

function M:iter()
  local i = 0
  return function()
    i = i + 1
    if i <= self.count then
      return self:get(i)
    end
  end
end

return M
