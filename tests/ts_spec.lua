local H = _G.H
local resolve = require("swap.resolve")

--- Resolve the list around `needle` and return the item texts.
---@return string[]
local function items(lines, filetype, needle)
  local bufnr = H.buf(lines, filetype)
  H.cursor_on(bufnr, needle)
  local row, col = require("swap.util").cursor(0)
  local region = resolve.at_cursor(bufnr, row, col)
  if not region then
    return {}
  end
  return vim.tbl_map(function(cell)
    return cell.text
  end, region.cells)
end

H.group("treesitter", function()
  H.test("c argument list", function()
    H.eq(items({ "int main(void) { foo(arg1, arg2, arg3); }" }, "c", "arg2"), { "arg1", "arg2", "arg3" })
  end)

  H.test("c parameter list", function()
    H.eq(items({ "int f(int a, char *b, double c);" }, "c", "char"), { "int a", "char *b", "double c" })
  end)

  H.test("c for-loop clauses, separated by semicolons", function()
    H.eq(items({ "for (i = 0; i < n; ++i) {}" }, "c", "i <"), { "i = 0", "i < n", "++i" })
  end)

  H.test("lua table fields", function()
    H.eq(items({ "local t = { a = 1, b = 2, c = 3 }" }, "lua", "b = 2"), { "a = 1", "b = 2", "c = 3" })
  end)

  H.test("lua does not mistake `=` inside a field for a separator", function()
    local got = items({ "local t = { a = 1, b = 2 }" }, "lua", "1")
    H.eq(got, { "a = 1", "b = 2" })
  end)

  H.test("python parameters of every shape", function()
    H.eq(items({ "def f(a, b=2, *args, **kw): pass" }, "python", "b=2"), { "a", "b=2", "*args", "**kw" })
  end)

  H.test("rust call arguments", function()
    H.eq(items({ "fn f() { g(x, y, z) }" }, "rust", "y"), { "x", "y", "z" })
  end)

  H.test("json object members", function()
    H.eq(items({ '{"a": 1, "b": 2}' }, "json", '"b"'), { '"a": 1', '"b": 2' })
  end)

  H.test("a nested call counts as one item", function()
    H.eq(items({ "int x = f(a, g(b, c), d);" }, "c", "a,"), { "a", "g(b, c)", "d" })
  end)

  H.test("a string hides its commas", function()
    H.eq(items({ 'char *x[] = { "a, b", c };' }, "c", '"a, b"'), { '"a, b"', "c" })
  end)

  H.test("a wrapped argument list spans lines", function()
    local got = items({ "void f() {", "  g(alpha,", "    beta,", "    gamma);", "}" }, "c", "beta")
    H.eq(got, { "alpha", "beta", "gamma" })
  end)

  H.test("a trailing comma is left outside the region", function()
    H.eq(items({ "local t = { a, b, c, }" }, "lua", "b"), { "a", "b", "c" })
  end)

  H.test("an operator chain is flattened across nesting", function()
    H.eq(items({ "int x = a + b + c + d;" }, "c", "b"), { "a", "b", "c", "d" })
  end)

  H.test("the innermost list wins", function()
    H.eq(items({ "int x = f(a + b, c);" }, "c", "a +"), { "a", "b" })
  end)

  H.test("a type prefix is not swallowed by the first item", function()
    H.eq(items({ "int a, b;" }, "c", "a,"), { "a", "b" })
  end)

  H.test("c struct initialiser", function()
    H.eq(items({ "struct p q = { .x = 1, .y = 2 };" }, "c", ".y"), { ".x = 1", ".y = 2" })
  end)

  H.test("markdown is left alone", function()
    H.eq(items({ "one two three" }, "markdown", "two"), {})
  end)

  H.test("bash command words, an opt-in whitespace list", function()
    H.eq(items({ "ls -l foo bar" }, "bash", "foo"), { "ls", "-l", "foo", "bar" })
  end)

  H.test("candidates are ordered innermost first", function()
    local bufnr = H.buf({ "int x = f(a, g(b, c), d);" }, "c")
    H.cursor_on(bufnr, "b,")
    local row, col = require("swap.util").cursor(0)
    local candidates = resolve.candidates(bufnr, row, col)
    H.ok(#candidates >= 2, "expected an inner and an outer list")
    H.eq(#candidates[1], 2, "inner list has two items")
    H.eq(#candidates[2], 3, "outer list has three items")
  end)

  H.test("nothing to swap outside a list", function()
    H.eq(items({ "int x = 1;" }, "c", "x"), {})
  end)
end)
