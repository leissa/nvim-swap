--- Regex-free fallback scanner.
---
--- Used when tree-sitter has no parser for the buffer, when it finds no list
--- around the cursor, and for visual selections (where the user has already
--- said what the region is). It knows about nesting and quoting, but nothing
--- about the language.
local config = require("swap.config")
local util = require("swap.util")

local M = {}

---@param text string
---@return table<string, string> open -> close
---@return table<string, boolean> close set
local function bracket_maps()
  local open, close = {}, {}
  for _, pair in ipairs(config.options.fallback.brackets) do
    open[pair[1]] = pair[2]
    close[pair[2]] = true
  end
  return open, close
end

---@return table<string, boolean>
local function quote_set()
  local out = {}
  for _, q in ipairs(config.options.fallback.quotes) do
    out[q] = true
  end
  return out
end

--- Walk `text` and call `fn(i, char, depth, quoted)` for every byte.
---@param text string
---@param fn fun(i: integer, char: string, depth: integer, quoted: boolean): boolean?
local function walk(text, fn)
  local open, close = bracket_maps()
  local quotes = quote_set()
  local depth, quote = 0, nil
  local i = 1
  while i <= #text do
    local c = text:sub(i, i)
    if quote then
      if c == "\\" then
        i = i + 1
      elseif c == quote then
        quote = nil
      end
    elseif quotes[c] then
      quote = c
    elseif open[c] then
      depth = depth + 1
    elseif close[c] then
      depth = depth - 1
    end
    if fn(i, c, depth, quote ~= nil) == false then
      return
    end
    i = i + 1
  end
end

--- Byte range of the innermost bracket pair enclosing `offset`, exclusive of
--- the brackets themselves.
---@param text string
---@param offset integer 0-based
---@return integer? from 0-based, inclusive
---@return integer? to 0-based, exclusive
function M.enclosing_brackets(text, offset)
  local open, close = bracket_maps()
  local quotes = quote_set()
  local stack, quote = {}, nil
  local i = 1
  while i <= #text do
    local c = text:sub(i, i)
    if quote then
      if c == "\\" then
        i = i + 1
      elseif c == quote then
        quote = nil
      end
    elseif quotes[c] then
      quote = c
    elseif open[c] then
      stack[#stack + 1] = { char = c, pos = i }
    elseif close[c] then
      local top = stack[#stack]
      if top and open[top.char] == c then
        if top.pos <= offset and i > offset then
          return top.pos, i - 1
        end
        stack[#stack] = nil
      end
    end
    i = i + 1
  end
  return nil
end

---@param text string
---@return string
local function ltrim(text)
  return (text:gsub("^%s+", ""))
end

--- Split `text` into item ranges. Whitespace around a delimiter belongs to the
--- gap, not to the items.
---@param text string
---@param opts? { whitespace?: boolean, delimiters?: string[] }
---@return integer[][]? list of { from, to } 0-based, end-exclusive
---@return string? kind 'delimiter' or 'whitespace'
function M.split(text, opts)
  opts = opts or {}
  local fallback = config.options.fallback
  local delimiters = opts.delimiters or fallback.delimiters

  for _, delim in ipairs(delimiters) do
    local positions = {}
    walk(text, function(i, c, depth, quoted)
      if not quoted and depth == 0 and c == delim then
        positions[#positions + 1] = i
      end
    end)
    if #positions > 0 then
      local ranges = {}
      local from = 1
      local bounds = vim.list_extend(vim.deepcopy(positions), { #text + 1 })
      for _, at in ipairs(bounds) do
        local piece = text:sub(from, at - 1)
        local lead = #piece - #ltrim(piece)
        local trimmed = vim.trim(piece)
        ranges[#ranges + 1] = { from - 1 + lead, from - 1 + lead + #trimmed }
        from = at + 1
      end
      -- A leading or trailing delimiter (`[1, 2, 3,]`) yields an empty piece at
      -- the edge; leave that delimiter outside the region.
      while ranges[1] and ranges[1][1] == ranges[1][2] do
        table.remove(ranges, 1)
      end
      while ranges[#ranges] and ranges[#ranges][1] == ranges[#ranges][2] do
        table.remove(ranges)
      end
      if #ranges >= 2 then
        return ranges, "delimiter"
      end
      return nil
    end
  end

  local want_whitespace = opts.whitespace
  if want_whitespace == nil then
    want_whitespace = fallback.whitespace
  end
  if not want_whitespace then
    return nil
  end

  local ranges = {}
  local start = nil
  walk(text, function(i, c, depth, quoted)
    local blank = not quoted and depth == 0 and c:match("%s") ~= nil
    if blank then
      if start then
        ranges[#ranges + 1] = { start - 1, i - 1 }
        start = nil
      end
    elseif not start then
      start = i
    end
  end)
  if start then
    ranges[#ranges + 1] = { start - 1, #text }
  end
  return #ranges >= 2 and ranges or nil, "whitespace"
end

--- Convert offset ranges inside a region string into buffer ranges.
---@param srow integer
---@param scol integer
---@param text string
---@param ranges integer[][]
---@return integer[][]
function M.to_buf_ranges(srow, scol, text, ranges)
  local out = {}
  for _, r in ipairs(ranges) do
    local sr, sc = util.offset_to_pos(srow, scol, text, r[1])
    local er, ec = util.offset_to_pos(srow, scol, text, r[2])
    out[#out + 1] = { sr, sc, er, ec }
  end
  return out
end

--- The run of words around the cursor, used when a line holds no delimiter and
--- no brackets: `foo bar baz` with the cursor anywhere on it.
---@param line string
---@param col integer 0-based byte column
---@return integer? from 0-based
---@return integer? to 0-based, exclusive
local function word_run(line, col)
  local function is_run(c)
    return c ~= "" and (c:match("[%w_]") or c:match("[ \t]"))
  end
  if not is_run(line:sub(col + 1, col + 1)) then
    return nil
  end
  local from = col + 1
  while from > 1 and is_run(line:sub(from - 1, from - 1)) do
    from = from - 1
  end
  local to = col + 1
  while to < #line and is_run(line:sub(to + 1, to + 1)) do
    to = to + 1
  end
  return from - 1, to
end

--- Find an item list around the cursor without tree-sitter.
---@param bufnr integer
---@param row integer
---@param col integer
---@return integer[][]? ranges
function M.around_cursor(bufnr, row, col)
  local fallback = config.options.fallback
  if not fallback.enabled then
    return nil
  end

  local total = vim.api.nvim_buf_line_count(bufnr)
  local top = math.max(0, row - fallback.max_lines)
  local bot = math.min(total, row + fallback.max_lines + 1)
  local text = util.get_text(bufnr, top, 0, bot - 1, #(vim.api.nvim_buf_get_lines(bufnr, bot - 1, bot, false)[1] or ""))
  local offset = util.pos_to_offset(bufnr, top, 0, row, col)

  local from, to = M.enclosing_brackets(text, offset)
  if from then
    local inner = text:sub(from + 1, to)
    local ranges = M.split(inner)
    if ranges and #ranges >= 2 then
      for _, r in ipairs(ranges) do
        r[1], r[2] = r[1] + from, r[2] + from
      end
      return M.to_buf_ranges(top, 0, text, ranges)
    end
  end

  -- No usable bracket pair: try the current line on its own.
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local ranges = M.split(line, { whitespace = false })
  if ranges and #ranges >= 2 then
    return M.to_buf_ranges(row, 0, line, ranges)
  end

  if fallback.whitespace then
    local wfrom, wto = word_run(line, col)
    if wfrom then
      local run = line:sub(wfrom + 1, wto)
      local words = M.split(run, { delimiters = {}, whitespace = true })
      if words and #words >= 2 then
        for _, r in ipairs(words) do
          r[1], r[2] = r[1] + wfrom, r[2] + wfrom
        end
        return M.to_buf_ranges(row, 0, line, words)
      end
    end
  end

  return nil
end

return M
