--- Entry points behind the `<Plug>` mappings, including dot-repeat.
---
--- Everything runs inside 'operatorfunc' (`g@`) so that the dot command repeats
--- it for free. On the first run an interactive session records what it did; a
--- later `.` replays those operations without asking again, which is how
--- vim-swap behaves too.
local mode = require("swap.mode")
local resolve = require("swap.resolve")
local util = require("swap.util")

local M = {}

---@class swap.Pending
---@field kind 'relative'|'interactive'|'visual'
---@field dir? integer
---@field count integer
---@field ops? table[] recorded operations, set after an interactive session
local pending = nil

--- Arm the operator function. The `<Plug>` mappings call this and then feed
--- `g@`.
---@param kind string
---@param opts? table
function M.prepare(kind, opts)
  pending = vim.tbl_extend("force", { kind = kind, count = vim.v.count1 }, opts or {})
  vim.go.operatorfunc = "v:lua.require'swap.ops'.opfunc"
end

---@param motion string 'char', 'line' or 'block'
---@return integer[] spos, integer[] epos, string mode
local function operated_range(motion)
  local s = vim.fn.getpos("'[")
  local e = vim.fn.getpos("']")
  local kinds = { char = "v", line = "V", block = vim.keycode("<C-v>") }
  return { s[2] - 1, s[3] - 1 }, { e[2] - 1, e[3] - 1 }, kinds[motion] or "v"
end

--- Swap the item under the cursor with one of its neighbours.
---@param bufnr integer
---@param winid integer
---@param dir integer -1 or 1
---@param count integer
---@return boolean
local function relative(bufnr, winid, dir, count)
  local row, col = util.cursor(winid)
  local region = resolve.at_cursor(bufnr, row, col)
  if not region then
    return false
  end

  local index = region:index_at(row, col)
  local changed = false
  for _ = 1, count do
    local target = index + dir
    if not region:swap(index, target) then
      break
    end
    index = target
    changed = true
  end
  if not changed then
    return false
  end

  region:apply()
  local range = region:ranges()[index]
  util.set_cursor(winid, range[1], range[2])
  return true
end

--- The 'operatorfunc'. Not called directly.
---@param motion string
function M.opfunc(motion)
  if not pending then
    return
  end
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)

  if pending.kind == "relative" then
    if not relative(bufnr, winid, pending.dir, pending.count) then
      util.notify("no swappable items here", vim.log.levels.WARN)
    end
    return
  end

  if pending.ops then
    mode.replay(bufnr, winid, pending.ops)
    return
  end

  local region
  if pending.kind == "visual" then
    local spos, epos, vmode = operated_range(motion)
    region = resolve.from_selection(bufnr, vmode, spos, epos)
  else
    local row, col = util.cursor(winid)
    region = resolve.at_cursor(bufnr, row, col)
  end

  if not region then
    util.notify("no swappable items here", vim.log.levels.WARN)
    return
  end

  local row, col = util.cursor(winid)
  local ops = mode.run(region, { winid = winid, current = region:index_at(row, col) })
  -- A following `.` replays these operations instead of starting swap mode.
  pending.ops = ops
end

--- `g<`
function M.prev()
  M.prepare("relative", { dir = -1 })
end

--- `g>`
function M.next()
  M.prepare("relative", { dir = 1 })
end

--- `gs` in normal mode.
function M.interactive()
  M.prepare("interactive")
end

--- `gs` in visual mode.
function M.visual()
  M.prepare("visual")
end

return M
