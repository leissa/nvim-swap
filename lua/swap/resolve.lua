--- Turning a cursor position or a visual selection into a |swap.Region|.
local Region = require("swap.region")
local scan = require("swap.scan")
local ts = require("swap.ts")
local util = require("swap.util")

local M = {}

--- All item lists around a position, innermost first. Tree-sitter is asked
--- first; the scanner only runs when it comes up empty.
---@param bufnr integer
---@param row integer
---@param col integer
---@return integer[][][]
function M.candidates(bufnr, row, col)
  local out = {}
  for _, cand in ipairs(ts.candidates(bufnr, row, col)) do
    out[#out + 1] = cand.ranges
  end
  if #out == 0 then
    local ranges = scan.around_cursor(bufnr, row, col)
    if ranges then
      out[1] = ranges
    end
  end
  return out
end

--- The innermost item list around the cursor. Swap mode reaches the enclosing
--- ones through |M.candidates()|.
---@param bufnr integer
---@param row integer
---@param col integer
---@return swap.Region?
function M.at_cursor(bufnr, row, col)
  local candidates = M.candidates(bufnr, row, col)
  if #candidates == 0 then
    return nil
  end
  return Region.from_ranges(bufnr, candidates[1])
end

--- Items of a visual selection.
---@param bufnr integer
---@param mode string 'v', 'V' or CTRL-V
---@param spos integer[] { row, col } 0-based, inclusive
---@param epos integer[] { row, col } 0-based, inclusive
---@return swap.Region?
function M.from_selection(bufnr, mode, spos, epos)
  if util.cmp_pos(spos[1], spos[2], epos[1], epos[2]) > 0 then
    spos, epos = epos, spos
  end

  if mode == "V" then
    -- Each line is an item. The indentation stays where it is, so only the
    -- content from the first non-blank character onwards moves.
    local ranges = {}
    for row = spos[1], epos[1] do
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
      local indent = #line - #line:gsub("^%s+", "")
      ranges[#ranges + 1] = { row, indent, row, #line }
    end
    return Region.from_ranges(bufnr, ranges)
  end

  if mode == vim.keycode("<C-v>") then
    -- The selected block of each line is an item.
    local left = math.min(spos[2], epos[2])
    local right = math.max(spos[2], epos[2]) + 1
    local ranges = {}
    for row = spos[1], epos[1] do
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
      ranges[#ranges + 1] = { row, math.min(left, #line), row, math.min(right, #line) }
    end
    return Region.from_ranges(bufnr, ranges)
  end

  -- The visual end position is inclusive; step past the whole character.
  local eline = vim.api.nvim_buf_get_lines(bufnr, epos[1], epos[1] + 1, false)[1] or ""
  local ecol = math.min(epos[2] + 1 + vim.str_utf_end(eline, epos[2] + 1), #eline)
  local text = util.get_text(bufnr, spos[1], spos[2], epos[1], ecol)
  local ranges = scan.split(text, { whitespace = true })
  if not ranges or #ranges < 2 then
    return nil
  end
  return Region.from_ranges(bufnr, scan.to_buf_ranges(spos[1], spos[2], text, ranges))
end

return M
