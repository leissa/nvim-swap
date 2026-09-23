local H = _G.H

---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "mtx", false)
end

H.group("mappings", function()
  H.test("g> swaps with the next item", function()
    local bufnr = H.buf({ "foo(arg1, arg2, arg3);" }, "c")
    H.cursor_on(bufnr, "arg2")
    feed("g>")
    H.eq(H.lines(bufnr), { "foo(arg1, arg3, arg2);" })
  end)

  H.test("g< swaps with the previous item", function()
    local bufnr = H.buf({ "foo(arg1, arg2, arg3);" }, "c")
    H.cursor_on(bufnr, "arg2")
    feed("g<")
    H.eq(H.lines(bufnr), { "foo(arg2, arg1, arg3);" })
  end)

  H.test("the cursor follows the item it moved", function()
    local bufnr = H.buf({ "foo(arg1, arg2, arg3);" }, "c")
    H.cursor_on(bufnr, "arg2")
    feed("g>")
    local row, col = require("swap.util").cursor(0)
    H.eq({ row, col }, { 0, 16 })
  end)

  H.test("a count moves the item that far", function()
    local bufnr = H.buf({ "foo(a, b, c, d);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("3g>")
    H.eq(H.lines(bufnr), { "foo(b, c, d, a);" })
  end)

  H.test("g> at the last item does nothing", function()
    local bufnr = H.buf({ "foo(a, b);" }, "c")
    H.cursor_on(bufnr, "b)")
    feed("g>")
    H.eq(H.lines(bufnr), { "foo(a, b);" })
  end)

  H.test("the dot command repeats g>", function()
    local bufnr = H.buf({ "foo(a, b, c, d);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("g>")
    feed(".")
    H.eq(H.lines(bufnr), { "foo(b, c, a, d);" })
  end)

  H.test("u undoes a swap in one step", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "b")
    feed("g>")
    feed("u")
    H.eq(H.lines(bufnr), { "foo(a, b, c);" })
  end)
end)

H.group("swap mode", function()
  H.test("l moves the current item to the right", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gsl<Esc>")
    H.eq(H.lines(bufnr), { "foo(b, a, c);" })
  end)

  H.test("repeated l walks the item along", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gsll<Esc>")
    H.eq(H.lines(bufnr), { "foo(b, c, a);" })
  end)

  H.test("h moves it back", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "c)")
    feed("gsh<Esc>")
    H.eq(H.lines(bufnr), { "foo(a, c, b);" })
  end)

  H.test("j and k pick another item without moving anything", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gsjl<Esc>")
    H.eq(H.lines(bufnr), { "foo(a, c, b);" })
  end)

  H.test("a digit jumps to that item", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gs3h<Esc>")
    H.eq(H.lines(bufnr), { "foo(a, c, b);" })
  end)

  H.test("u inside swap mode steps back", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gsllu<Esc>")
    H.eq(H.lines(bufnr), { "foo(b, a, c);" })
  end)

  H.test("undo and redo cancel out", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gsllu<C-r><Esc>")
    H.eq(H.lines(bufnr), { "foo(b, c, a);" })
  end)

  H.test("r reverses the list", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gsr<Esc>")
    H.eq(H.lines(bufnr), { "foo(c, b, a);" })
  end)

  H.test("s sorts, S sorts the other way", function()
    local bufnr = H.buf({ "foo(c, a, b);" }, "c")
    H.cursor_on(bufnr, "c,")
    feed("gss<Esc>")
    H.eq(H.lines(bufnr), { "foo(a, b, c);" })
    feed("gsS<Esc>")
    H.eq(H.lines(bufnr), { "foo(c, b, a);" })
  end)

  H.test("g groups two items so they move together", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gsgl<Esc>")
    H.eq(H.lines(bufnr), { "foo(c, a, b);" })
  end)

  H.test("G ungroups again", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gsgGl<Esc>")
    H.eq(H.lines(bufnr), { "foo(b, a, c);" })
  end)

  H.test("+ widens to the enclosing list", function()
    local bufnr = H.buf({ "f(a, g(b, c), d);" }, "c")
    H.cursor_on(bufnr, "b,")
    feed("gs+h<Esc>")
    H.eq(H.lines(bufnr), { "f(g(b, c), a, d);" })
  end)

  H.test("the whole session is a single undo step", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gsll<Esc>")
    feed("u")
    H.eq(H.lines(bufnr), { "foo(a, b, c);" })
  end)

  H.test("the dot command replays the session", function()
    local bufnr = H.buf({ "foo(a, b, c);", "bar(x, y, z);" }, "c")
    H.cursor_on(bufnr, "a,")
    feed("gsr<Esc>")
    H.cursor_on(bufnr, "x,")
    feed(".")
    H.eq(H.lines(bufnr), { "foo(c, b, a);", "bar(z, y, x);" })
  end)

  H.test("swap mode works on a visual selection", function()
    local bufnr = H.buf({ "foo", "bar", "baz" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    feed("Vjjgsl<Esc>")
    H.eq(H.lines(bufnr), { "bar", "foo", "baz" })
  end)

  H.test("leaves the buffer alone when there is nothing to swap", function()
    local bufnr = H.buf({ "int x = 1;" }, "c")
    H.cursor_on(bufnr, "x")
    feed("gs")
    H.eq(H.lines(bufnr), { "int x = 1;" })
  end)
end)

H.group("text objects", function()
  H.test("i, selects the item under the cursor", function()
    local bufnr = H.buf({ "foo(arg1, arg2, arg3);" }, "c")
    H.cursor_on(bufnr, "arg2")
    feed("y<Plug>(swap-textobject-i)")
    H.eq(vim.fn.getreg('"'), "arg2")
  end)

  H.test("a, takes the delimiter along", function()
    local bufnr = H.buf({ "foo(arg1, arg2, arg3);" }, "c")
    H.cursor_on(bufnr, "arg2")
    feed("y<Plug>(swap-textobject-a)")
    H.eq(vim.fn.getreg('"'), ", arg2")
  end)

  H.test("i, with a count spans several items", function()
    local bufnr = H.buf({ "foo(arg1, arg2, arg3);" }, "c")
    H.cursor_on(bufnr, "arg1")
    feed("y2<Plug>(swap-textobject-i)")
    H.eq(vim.fn.getreg('"'), "arg1, arg2")
  end)

  H.test("d works with the text object", function()
    local bufnr = H.buf({ "foo(arg1, arg2, arg3);" }, "c")
    H.cursor_on(bufnr, "arg2")
    feed("d<Plug>(swap-textobject-a)")
    H.eq(H.lines(bufnr), { "foo(arg1, arg3);" })
  end)
end)

H.group("highlighting", function()
  local highlight = require("swap.highlight")
  local Region = require("swap.region")

  local function marks(bufnr)
    return vim.api.nvim_buf_get_extmarks(bufnr, highlight.ns, 0, -1, { details = true })
  end

  H.test("every item is highlighted and the current one stands out", function()
    local bufnr = H.buf({ "foo(a, b, c);" })
    local region = Region.from_ranges(bufnr, { { 0, 4, 0, 5 }, { 0, 7, 0, 8 }, { 0, 10, 0, 11 } })
    highlight.show(region, 2)

    local groups = {}
    for _, mark in ipairs(marks(bufnr)) do
      local hl = mark[4].hl_group
      if hl then
        groups[#groups + 1] = hl
      end
    end
    H.eq(groups, { "SwapItem", "SwapCurrentItem", "SwapItem" })
  end)

  H.test("items are numbered", function()
    local bufnr = H.buf({ "foo(a, b, c);" })
    local region = Region.from_ranges(bufnr, { { 0, 4, 0, 5 }, { 0, 7, 0, 8 }, { 0, 10, 0, 11 } })
    highlight.show(region, 1)

    local labels = {}
    for _, mark in ipairs(marks(bufnr)) do
      if mark[4].virt_text then
        labels[#labels + 1] = mark[4].virt_text[1][1]
      end
    end
    H.eq(labels, { "1", "2", "3" })
  end)

  H.test("leaving swap mode removes the highlights", function()
    local bufnr = H.buf({ "foo(a, b, c);" }, "c")
    H.cursor_on(bufnr, "a,")
    vim.api.nvim_feedkeys(vim.keycode("gsl<Esc>"), "mtx", false)
    H.eq(marks(bufnr), {})
  end)
end)

H.group("edge cases", function()
  H.test("a text object reaching the end of the line", function()
    local bufnr = H.buf({ "f(a, bbb)" }, "c")
    H.cursor_on(bufnr, "bbb")
    vim.api.nvim_feedkeys(vim.keycode("y<Plug>(swap-textobject-i)"), "mtx", false)
    H.eq(vim.fn.getreg('"'), "bbb")
  end)

  H.test("multibyte items keep their boundaries", function()
    local bufnr = H.buf({ "f(ähm, öhm, üh);" }, "c")
    H.cursor_on(bufnr, "öhm")
    vim.api.nvim_feedkeys(vim.keycode("g>"), "mtx", false)
    H.eq(H.lines(bufnr), { "f(ähm, üh, öhm);" })
  end)

  H.test("a text object over a multibyte item", function()
    local bufnr = H.buf({ "f(ähm, öhm);" }, "c")
    H.cursor_on(bufnr, "öhm")
    vim.api.nvim_feedkeys(vim.keycode("y<Plug>(swap-textobject-i)"), "mtx", false)
    H.eq(vim.fn.getreg('"'), "öhm")
  end)

  H.test("leaving swap mode at once changes nothing", function()
    local bufnr = H.buf({ "f(a, b);" }, "c")
    H.cursor_on(bufnr, "a,")
    local before = vim.fn.undotree().seq_cur
    vim.api.nvim_feedkeys(vim.keycode("gs<Esc>"), "mtx", false)
    H.eq(vim.fn.undotree().seq_cur, before, "no change was written")
    vim.api.nvim_feedkeys(vim.keycode("."), "mtx", false)
    H.eq(H.lines(bufnr), { "f(a, b);" })
  end)

  H.test("a two-item list still swaps", function()
    local bufnr = H.buf({ "f(a, b);" }, "c")
    H.cursor_on(bufnr, "a,")
    vim.api.nvim_feedkeys(vim.keycode("g>"), "mtx", false)
    H.eq(H.lines(bufnr), { "f(b, a);" })
  end)
end)
