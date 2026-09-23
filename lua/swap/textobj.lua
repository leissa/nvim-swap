--- Text objects selecting swappable items: `i,` and `a,`.
local resolve = require("swap.resolve")
local util = require("swap.util")

local M = {}

--- Select the item under the cursor. With `kind = 'a'` one adjacent delimiter
--- is included, preferring the one in front of the item, as `a,` should.
---@param kind 'i'|'a'
---@param count? integer number of consecutive items to select
function M.select(kind, count)
  count = count or vim.v.count1
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local row, col = util.cursor(winid)

  local region = resolve.at_cursor(bufnr, row, col)
  if not region then
    return
  end

  local ranges = region:ranges()
  local first = region:index_at(row, col)
  local last = math.min(first + count - 1, #ranges)

  local srow, scol = ranges[first][1], ranges[first][2]
  local erow, ecol = ranges[last][3], ranges[last][4]

  if kind == "a" then
    if first > 1 then
      srow, scol = ranges[first - 1][3], ranges[first - 1][4]
    elseif last < #ranges then
      erow, ecol = ranges[last + 1][1], ranges[last + 1][2]
    end
  end

  -- Visual selections are inclusive, so step back one character from the
  -- exclusive end, continuation bytes included.
  local eline = vim.api.nvim_buf_get_lines(bufnr, erow, erow + 1, false)[1] or ""
  ecol = ecol - 1
  while ecol > 0 and bit.band(eline:byte(ecol + 1) or 0, 0xc0) == 0x80 do
    ecol = ecol - 1
  end

  -- Only in visual mode is there a selection to drop first; doing it in
  -- operator-pending mode would cancel the operator.
  if vim.fn.mode():match("^[vV\22]") then
    vim.cmd("normal! \27")
  end
  vim.api.nvim_win_set_cursor(winid, { srow + 1, scol })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(winid, { erow + 1, math.max(ecol, 0) })
end

return M
