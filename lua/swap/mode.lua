--- Swap mode: the interactive counterpart of `g<` / `g>`.
---
--- Every item of the list is highlighted and numbered, the current one stands
--- out, and normal-mode style motions move it around: `h`/`l` move the current
--- item, `j`/`k` pick a different one. Nothing is committed until the mode is
--- left, so `u` inside the mode is instant and a single `u` afterwards undoes
--- the whole session.
local config = require("swap.config")
local highlight = require("swap.highlight")
local Region = require("swap.region")
local resolve = require("swap.resolve")
local util = require("swap.util")

local M = {}

--- Map every configured key to its command name.
---@return table<string, string>
local function keymap()
  local map = {}
  for command, keys in pairs(config.options.swap_mode.keys) do
    for _, key in ipairs(keys) do
      map[vim.keycode(key)] = command
    end
  end
  return map
end

--- The swap mode status line, cut down to `width` columns. A message that does
--- not fit would trigger a |hit-enter| prompt on every keystroke, so hints are
--- dropped from the right until it does.
---@param count integer number of items
---@param current integer
---@param pending string
---@param width integer
---@return table[] chunks for |nvim_echo()|
function M.status(count, current, pending, width)
  local keys = config.options.swap_mode.keys
  local function key(command)
    return (keys[command] or {})[1] or ""
  end

  local status = string.format("item %d/%d", current, count)
  if pending ~= "" then
    status = status .. " \u{2192} " .. pending
  end

  local hints = {
    key("move_prev") .. "/" .. key("move_next") .. " move",
    key("select_next") .. "/" .. key("select_prev") .. " select",
    key("group") .. " group",
    key("sort") .. " sort",
    key("reverse") .. " reverse",
    key("undo") .. " undo",
    "<Esc> done",
  }

  local head = "-- SWAP -- "
  while #hints > 0 and vim.fn.strdisplaywidth(head .. status .. "  " .. table.concat(hints, "  ")) > width do
    table.remove(hints)
  end
  if #hints > 0 then
    return {
      { head, "ModeMsg" },
      { status .. "  ", "Normal" },
      { table.concat(hints, "  "), "Comment" },
    }
  end

  if vim.fn.strdisplaywidth(head .. status) <= width then
    return { { head, "ModeMsg" }, { status, "Normal" } }
  end

  while status ~= "" and vim.fn.strdisplaywidth(status) > width do
    status = vim.fn.strcharpart(status, 0, vim.fn.strchars(status) - 1)
  end
  return { { status, "Normal" } }
end

---@param region swap.Region
---@param current integer
---@param pending string
local function echo(region, current, pending)
  if not config.options.swap_mode.echo then
    return
  end
  -- |v:echospace| is what is left of the last screen line once 'showcmd' and
  -- the ruler have taken their share. Going past it means a |hit-enter|
  -- prompt on every single keystroke.
  vim.api.nvim_echo(M.status(region:count(), current, pending, vim.v.echospace), false, {})
end

--- Run swap mode on a region.
---@param region swap.Region
---@param opts { winid: integer, level?: integer, current?: integer }
---@return table[] ops the operations performed, for dot-repeat
function M.run(region, opts)
  local winid = opts.winid
  local bufnr = region.bufnr
  local level = opts.level or 1
  local current = opts.current or 1
  local keys = keymap()
  local digits = config.options.swap_mode.digits
  local sortfn = config.options.swap_mode.sort

  local anchor_row, anchor_col = util.cursor(winid)
  local undo_stack, redo_stack = {}, {}
  local ops, undone_ops = {}, {}
  local dirty = false
  local pending = ""

  --- Apply a change, recording it for undo and for dot-repeat.
  ---@param fn fun(): boolean
  ---@param op table
  local function mutate(fn, op)
    local snapshot = region:snapshot()
    if not fn() then
      return
    end
    undo_stack[#undo_stack + 1] = snapshot
    redo_stack, undone_ops = {}, {}
    ops[#ops + 1] = op
    if dirty then
      pcall(vim.cmd, "silent! undojoin")
    end
    region:apply()
    dirty = true
  end

  local function restore(from, to, from_ops, to_ops)
    if #from == 0 then
      return
    end
    to[#to + 1] = region:snapshot()
    region:restore(table.remove(from))
    if #from_ops > 0 then
      to_ops[#to_ops + 1] = table.remove(from_ops)
    end
    pcall(vim.cmd, "silent! undojoin")
    region:apply()
    dirty = true
  end

  --- Rebuild the region from an enclosing or enclosed candidate. The candidate
  --- list is always taken from where swap mode started, so that widening and
  --- narrowing again lands back on the list it came from.
  ---@param delta integer
  local function relevel(delta)
    local fresh = resolve.candidates(bufnr, anchor_row, anchor_col)
    local target = math.min(math.max(level + delta, 1), #fresh)
    if #fresh == 0 or target == level then
      return
    end
    local next_region = Region.from_ranges(bufnr, fresh[target])
    if not next_region then
      return
    end
    level = target
    region = next_region
    current = region:index_at(anchor_row, anchor_col)
    undo_stack, redo_stack = {}, {}
    ops[#ops + 1] = { "level", level }
  end

  local function goto_item(n)
    if n >= 1 and n <= region:count() then
      current = n
    end
  end

  local commands = {
    move_prev = function()
      if current > 1 then
        local from = current
        mutate(function()
          return region:swap(from, from - 1)
        end, { "swap", from, from - 1 })
        current = from - 1
      end
    end,
    move_next = function()
      if current < region:count() then
        local from = current
        mutate(function()
          return region:swap(from, from + 1)
        end, { "swap", from, from + 1 })
        current = from + 1
      end
    end,
    select_prev = function()
      goto_item(current - 1)
    end,
    select_next = function()
      goto_item(current + 1)
    end,
    group = function()
      local at = current
      mutate(function()
        return region:group(at)
      end, { "group", at })
      goto_item(at)
    end,
    ungroup = function()
      local at = current
      mutate(function()
        return region:ungroup(at)
      end, { "ungroup", at })
    end,
    sort = function()
      mutate(function()
        return region:sort(sortfn, false)
      end, { "sort", false })
    end,
    sort_reverse = function()
      mutate(function()
        return region:sort(sortfn, true)
      end, { "sort", true })
    end,
    reverse = function()
      mutate(function()
        return region:reverse()
      end, { "reverse" })
      current = region:count() + 1 - current
    end,
    undo = function()
      restore(undo_stack, redo_stack, ops, undone_ops)
    end,
    redo = function()
      restore(redo_stack, undo_stack, undone_ops, ops)
    end,
    widen = function()
      relevel(1)
    end,
    shrink = function()
      relevel(-1)
    end,
  }

  local ok, err = pcall(function()
    while true do
      current = math.min(math.max(current, 1), region:count())
      local ranges = region:ranges()
      util.set_cursor(winid, ranges[current][1], ranges[current][2])
      highlight.show(region, current)
      echo(region, current, pending)
      vim.cmd("redraw")

      local key = vim.fn.getcharstr()
      if key == "" or keys[key] == "quit" then
        break
      end

      local command = keys[key]
      if command and commands[command] then
        pending = ""
        commands[command]()
      elseif key:match("^%d$") then
        if digits == "accumulate" then
          pending = pending .. key
        else
          pending = ""
          goto_item(tonumber(key))
        end
      elseif key == vim.keycode("<CR>") then
        if pending ~= "" then
          goto_item(tonumber(pending))
        end
        pending = ""
      elseif key == vim.keycode("<BS>") then
        pending = pending:sub(1, -2)
      else
        pending = ""
      end
    end
  end)

  highlight.clear(bufnr)
  vim.api.nvim_echo({ { "" } }, false, {})
  if not ok then
    error(err)
  end

  local ranges = region:ranges()
  if ranges[current] then
    util.set_cursor(winid, ranges[current][1], ranges[current][2])
  end
  return ops
end

--- Replay recorded swap mode operations, without any interaction. Used by the
--- dot command.
---@param bufnr integer
---@param winid integer
---@param ops table[]
---@return boolean applied
function M.replay(bufnr, winid, ops)
  if #ops == 0 then
    return true
  end
  local row, col = util.cursor(winid)
  local candidates = resolve.candidates(bufnr, row, col)
  if #candidates == 0 then
    return false
  end

  local region = Region.from_ranges(bufnr, candidates[1])
  if not region then
    return false
  end

  local sortfn = config.options.swap_mode.sort
  for _, op in ipairs(ops) do
    local kind = op[1]
    if kind == "swap" then
      region:swap(op[2], op[3])
    elseif kind == "group" then
      region:group(op[2])
    elseif kind == "ungroup" then
      region:ungroup(op[2])
    elseif kind == "sort" then
      region:sort(sortfn, op[2])
    elseif kind == "reverse" then
      region:reverse()
    elseif kind == "level" then
      local pick = candidates[op[2]]
      if not pick then
        return false
      end
      region:apply()
      local fresh = Region.from_ranges(bufnr, pick)
      if not fresh then
        return false
      end
      region = fresh
    end
  end
  region:apply()
  return true
end

return M
