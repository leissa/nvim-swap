--- Small position/text helpers shared by the rest of the plugin.
---
--- Positions are always (row, col) pairs with a 0-based row and a 0-based byte
--- column, and ranges are end-exclusive, matching the `nvim_buf_*` API.
local M = {}

--- Read a buffer range as a single string with "\n" line separators.
---@param bufnr integer
---@param srow integer
---@param scol integer
---@param erow integer
---@param ecol integer
---@return string
function M.get_text(bufnr, srow, scol, erow, ecol)
  return table.concat(vim.api.nvim_buf_get_text(bufnr, srow, scol, erow, ecol, {}), "\n")
end

--- Translate a byte offset inside `str` into a buffer position, given that
--- `str` starts at (srow, scol) in the buffer.
---@param srow integer
---@param scol integer
---@param str string
---@param offset integer 0-based byte offset
---@return integer row, integer col
function M.offset_to_pos(srow, scol, str, offset)
  local nl, last = 0, 0
  local i = 1
  while true do
    local p = str:find("\n", i, true)
    if not p or p > offset then
      break
    end
    nl, last, i = nl + 1, p, p + 1
  end
  if nl == 0 then
    return srow, scol + offset
  end
  return srow + nl, offset - last
end

--- Inverse of |offset_to_pos|: the byte offset of (row, col) inside a region
--- that starts at (srow, scol).
---@return integer
function M.pos_to_offset(bufnr, srow, scol, row, col)
  if row == srow then
    return col - scol
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, srow, row, false)
  local offset = #lines[1] - scol
  for i = 2, #lines do
    offset = offset + 1 + #lines[i]
  end
  return offset + 1 + col
end

--- Compare two positions.
---@return integer -1, 0 or 1
function M.cmp_pos(r1, c1, r2, c2)
  if r1 ~= r2 then
    return r1 < r2 and -1 or 1
  end
  if c1 ~= c2 then
    return c1 < c2 and -1 or 1
  end
  return 0
end

--- The cursor position of a window as (row, col), 0-based.
---@param winid? integer
---@return integer row, integer col
function M.cursor(winid)
  local pos = vim.api.nvim_win_get_cursor(winid or 0)
  return pos[1] - 1, pos[2]
end

--- Move the cursor, clamping the column to the line so that the call cannot
--- fail on a shrunken line.
function M.set_cursor(winid, row, col)
  local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(winid), row, row + 1, false)[1] or ""
  vim.api.nvim_win_set_cursor(winid, { row + 1, math.min(col, math.max(#line - 1, 0)) })
end

--- `vim.notify` with the plugin name attached.
---@param msg string
---@param level? integer
function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "swap" })
end

return M
