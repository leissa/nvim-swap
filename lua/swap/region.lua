--- A region is a stretch of buffer holding a list of items separated by gaps.
---
--- Only the items move; the gaps keep their positions. Reordering
--- `foo(aaa, b, cc)` therefore rebuilds the region as item .. gap .. item ..
--- gap .. item, which is what keeps line breaks and indentation of a wrapped
--- argument list exactly where they were.
local util = require("swap.util")

---@class swap.Cell One movable unit: an item, or a group of items.
---@field text string
---@field kids? swap.Cell[] components, when this cell is a group
---@field kidgap? string the gap that was absorbed when grouping

---@class swap.Region
---@field bufnr integer
---@field srow integer
---@field scol integer
---@field erow integer
---@field ecol integer
---@field cells swap.Cell[]
---@field gaps string[] `#cells - 1` separators, by position
local Region = {}
Region.__index = Region

--- Build a region from item ranges. The ranges must be sorted and disjoint;
--- everything between them becomes a gap.
---@param bufnr integer
---@param ranges integer[][] list of { srow, scol, erow, ecol }
---@return swap.Region?
function Region.from_ranges(bufnr, ranges)
  if #ranges < 2 then
    return nil
  end
  local srow, scol = ranges[1][1], ranges[1][2]
  local last = ranges[#ranges]
  local erow, ecol = last[3], last[4]
  local text = util.get_text(bufnr, srow, scol, erow, ecol)

  -- Offset of the start of each line of the region, so that a position turns
  -- into an offset without going back to the buffer for every item.
  local starts, at = { 0 }, 0
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    at = at + #line + 1
    starts[#starts + 1] = at
  end
  local function offset_of(row, col)
    return starts[row - srow + 1] + (row == srow and col - scol or col)
  end

  local cells, gaps = {}, {}
  local prev_end = nil
  for _, r in ipairs(ranges) do
    local from = offset_of(r[1], r[2])
    local to = offset_of(r[3], r[4])
    if prev_end then
      gaps[#gaps + 1] = text:sub(prev_end + 1, from)
    end
    cells[#cells + 1] = { text = text:sub(from + 1, to) }
    prev_end = to
  end

  return setmetatable({
    bufnr = bufnr,
    srow = srow,
    scol = scol,
    erow = erow,
    ecol = ecol,
    cells = cells,
    gaps = gaps,
  }, Region)
end

---@return integer
function Region:count()
  return #self.cells
end

--- The region text for the current cell order.
---@return string
function Region:render()
  local out = {}
  for i, cell in ipairs(self.cells) do
    out[#out + 1] = cell.text
    if self.gaps[i] then
      out[#out + 1] = self.gaps[i]
    end
  end
  return table.concat(out)
end

--- Buffer ranges of every cell for the current order.
---@return integer[][] list of { srow, scol, erow, ecol }
function Region:ranges()
  local text = self:render()
  local ranges, offset = {}, 0
  for i, cell in ipairs(self.cells) do
    local sr, sc = util.offset_to_pos(self.srow, self.scol, text, offset)
    offset = offset + #cell.text
    local er, ec = util.offset_to_pos(self.srow, self.scol, text, offset)
    ranges[#ranges + 1] = { sr, sc, er, ec }
    offset = offset + #(self.gaps[i] or "")
  end
  return ranges
end

--- Write the current order back to the buffer.
function Region:apply()
  local text = self:render()
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(self.bufnr, self.srow, self.scol, self.erow, self.ecol, lines)
  -- Reordering keeps the byte count but can move line breaks around, so the
  -- end of the region is recomputed rather than assumed.
  if #lines == 1 then
    self.erow, self.ecol = self.srow, self.scol + #lines[1]
  else
    self.erow, self.ecol = self.srow + #lines - 1, #lines[#lines]
  end
end

--- Exchange two cells. Out-of-range indices are ignored.
---@param i integer
---@param j integer
---@return boolean changed
function Region:swap(i, j)
  if i == j or not self.cells[i] or not self.cells[j] then
    return false
  end
  self.cells[i], self.cells[j] = self.cells[j], self.cells[i]
  return true
end

--- Merge cell `i` with cell `i + 1` into one movable group.
---@param i integer
---@return boolean changed
function Region:group(i)
  if not self.cells[i] or not self.cells[i + 1] then
    return false
  end
  local a, b = self.cells[i], self.cells[i + 1]
  local gap = self.gaps[i]
  self.cells[i] = { text = a.text .. gap .. b.text, kids = { a, b }, kidgap = gap }
  table.remove(self.cells, i + 1)
  table.remove(self.gaps, i)
  return true
end

--- Split a grouped cell back into its components.
---@param i integer
---@return boolean changed
function Region:ungroup(i)
  local cell = self.cells[i]
  if not cell or not cell.kids then
    return false
  end
  self.cells[i] = cell.kids[1]
  table.insert(self.cells, i + 1, cell.kids[2])
  table.insert(self.gaps, i, cell.kidgap)
  return true
end

---@param comparator fun(a: string, b: string): boolean
---@param descending? boolean
---@return boolean changed
function Region:sort(comparator, descending)
  local before = vim.tbl_map(function(c)
    return c.text
  end, self.cells)
  table.sort(self.cells, function(a, b)
    if descending then
      return comparator(b.text, a.text)
    end
    return comparator(a.text, b.text)
  end)
  for i, c in ipairs(self.cells) do
    if c.text ~= before[i] then
      return true
    end
  end
  return false
end

---@return boolean changed
function Region:reverse()
  local n = #self.cells
  for i = 1, math.floor(n / 2) do
    self.cells[i], self.cells[n + 1 - i] = self.cells[n + 1 - i], self.cells[i]
  end
  return n > 1
end

--- Index of the cell containing (row, col), or the nearest one.
---@param row integer
---@param col integer
---@return integer
function Region:index_at(row, col)
  local ranges = self:ranges()
  for i, r in ipairs(ranges) do
    if util.cmp_pos(row, col, r[3], r[4]) < 0 then
      -- Before the end of item i: inside it, or in the gap ahead of it.
      return i
    end
  end
  return #ranges
end

--- A deep enough copy to serve as an undo snapshot.
---@return { cells: swap.Cell[], gaps: string[] }
function Region:snapshot()
  return { cells = vim.deepcopy(self.cells), gaps = vim.deepcopy(self.gaps) }
end

---@param snap { cells: swap.Cell[], gaps: string[] }
function Region:restore(snap)
  self.cells = vim.deepcopy(snap.cells)
  self.gaps = vim.deepcopy(snap.gaps)
end

return Region
