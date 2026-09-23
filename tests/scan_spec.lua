local H = _G.H
local resolve = require("swap.resolve")
local scan = require("swap.scan")
local util = require("swap.util")

---@return string[]
local function pieces(text, opts)
  local ranges = scan.split(text, opts)
  return vim.tbl_map(function(r)
    return text:sub(r[1] + 1, r[2])
  end, ranges or {})
end

---@return string[]
local function around(lines, needle, filetype)
  local bufnr = H.buf(lines, filetype)
  H.cursor_on(bufnr, needle)
  local row, col = util.cursor(0)
  local ranges = scan.around_cursor(bufnr, row, col)
  if not ranges then
    return {}
  end
  local region = require("swap.region").from_ranges(bufnr, ranges)
  return vim.tbl_map(function(cell)
    return cell.text
  end, region.cells)
end

H.group("scanner", function()
  H.test("splits on a delimiter and drops the surrounding space", function()
    H.eq(pieces("foo, bar,baz"), { "foo", "bar", "baz" })
  end)

  H.test("ignores delimiters inside brackets", function()
    H.eq(pieces("a, f(b, c), d"), { "a", "f(b, c)", "d" })
  end)

  H.test("ignores delimiters inside quotes", function()
    H.eq(pieces([[a, "b, c", d]]), { "a", '"b, c"', "d" })
  end)

  H.test("respects escaped quotes", function()
    H.eq(pieces([[a, "b\", c", d]]), { "a", [["b\", c"]], "d" })
  end)

  H.test("splits on whitespace when asked", function()
    H.eq(pieces("one two  three", { delimiters = {}, whitespace = true }), { "one", "two", "three" })
  end)

  H.test("finds the innermost enclosing brackets", function()
    local text = "f(a, g(b, c), d)"
    local from, to = scan.enclosing_brackets(text, 8) -- on `b`
    H.eq(text:sub(from + 1, to), "b, c")
  end)

  H.test("works without a parser at all", function()
    H.eq(around({ "call(one, two, three)" }, "two"), { "one", "two", "three" })
  end)

  H.test("spans several lines", function()
    H.eq(around({ "call(one,", "     two,", "     three)" }, "two"), { "one", "two", "three" })
  end)

  H.test("falls back to the current line when there are no brackets", function()
    H.eq(around({ "alpha, beta, gamma" }, "beta"), { "alpha", "beta", "gamma" })
  end)
end)

H.group("visual selection", function()
  local function selected(lines, mode, spos, epos)
    local bufnr = H.buf(lines)
    local region = resolve.from_selection(bufnr, mode, spos, epos)
    if not region then
      return {}
    end
    return vim.tbl_map(function(cell)
      return cell.text
    end, region.cells)
  end

  H.test("charwise selections split on whitespace too", function()
    H.eq(selected({ "one two three" }, "v", { 0, 0 }, { 0, 12 }), { "one", "two", "three" })
  end)

  H.test("linewise selections make every line an item", function()
    H.eq(selected({ "foo", "bar", "baz" }, "V", { 0, 0 }, { 2, 0 }), { "foo", "bar", "baz" })
  end)

  H.test("linewise selections leave the indentation in place", function()
    local bufnr = H.buf({ "    foo", "  bar" })
    local region = resolve.from_selection(bufnr, "V", { 0, 0 }, { 1, 0 })
    region:swap(1, 2)
    region:apply()
    H.eq(H.lines(bufnr), { "    bar", "  foo" })
  end)

  H.test("blockwise selections swap the selected columns", function()
    local bufnr = H.buf({ "ab cd", "ef gh" })
    local region = resolve.from_selection(bufnr, vim.keycode("<C-v>"), { 0, 0 }, { 1, 1 })
    region:swap(1, 2)
    region:apply()
    H.eq(H.lines(bufnr), { "ef cd", "ab gh" })
  end)
end)
