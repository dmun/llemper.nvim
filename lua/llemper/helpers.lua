local H = {}

---@param win integer|nil
---@return integer[]
function H.get_zero_cursor(win)
  win = win or 0
  local cursor = vim.api.nvim_win_get_cursor(win)
  cursor[1] = cursor[1] - 1
  return cursor
end

return H
