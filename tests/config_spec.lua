local H = _G.H
local swap = require("swap")

local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "mtx", false)
end

--- Run `fn` with a configuration, then put the defaults back.
local function with(opts, fn)
  swap.setup(opts)
  local ok, err = pcall(fn)
  swap.setup()
  if not ok then
    error(err, 0)
  end
end

H.group("configuration", function()
  H.test("custom keys replace the default ones", function()
    with({ keymaps = { next = "<Leader>l", prev = false } }, function()
      H.eq(vim.fn.maparg("<Leader>l", "n"), "<Plug>(swap-next)")
      H.eq(vim.fn.maparg("g<", "n"), "")
    end)
    H.eq(vim.fn.maparg("g<", "n"), "<Plug>(swap-prev)", "the defaults come back")
  end)

  H.test("a custom separator makes a new kind of list", function()
    with({ treesitter = { separators = { ",", ";", "|" } } }, function()
      local bufnr = H.buf({ "int x = a | b;" }, "c")
      H.cursor_on(bufnr, "a |")
      feed("g>")
      H.eq(H.lines(bufnr), { "int x = b | a;" })
    end)
  end)

  H.test("a custom sort function is used by s", function()
    with({
      swap_mode = {
        sort = function(a, b)
          return #a < #b
        end,
      },
    }, function()
      local bufnr = H.buf({ "foo(ccc, a, bb);" }, "c")
      H.cursor_on(bufnr, "ccc")
      feed("gss<Esc>")
      H.eq(H.lines(bufnr), { "foo(a, bb, ccc);" })
    end)
  end)

  H.test("accumulated digits reach items past the ninth", function()
    with({ swap_mode = { digits = "accumulate" } }, function()
      local bufnr = H.buf({ "f(a, b, c, d, e, f, g, h, i, j);" }, "c")
      H.cursor_on(bufnr, "a,")
      feed("gs10<CR>h<Esc>")
      H.eq(H.lines(bufnr), { "f(a, b, c, d, e, f, g, h, j, i);" })
    end)
  end)

  H.test("BS corrects an accumulated number", function()
    with({ swap_mode = { digits = "accumulate" } }, function()
      local bufnr = H.buf({ "f(a, b, c);" }, "c")
      H.cursor_on(bufnr, "a,")
      feed("gs13<BS><CR>l<Esc>")
      H.eq(H.lines(bufnr), { "f(b, a, c);" })
    end)
  end)

  H.test("rebound swap mode keys take effect", function()
    with({ swap_mode = { keys = { move_next = { "<C-l>" } } } }, function()
      local bufnr = H.buf({ "f(a, b);" }, "c")
      H.cursor_on(bufnr, "a,")
      feed("gs<C-l><Esc>")
      H.eq(H.lines(bufnr), { "f(b, a);" })
    end)
  end)

  H.test("- goes back into the list that + left", function()
    local bufnr = H.buf({ "f(a, g(b, c), d);" }, "c")
    H.cursor_on(bufnr, "b,")
    feed("gs+-l<Esc>")
    H.eq(H.lines(bufnr), { "f(a, g(c, b), d);" })
  end)

  H.test("with tree-sitter off the scanner takes over", function()
    with({ treesitter = { enabled = false } }, function()
      local bufnr = H.buf({ "int a = f(x, y, z);" }, "c")
      H.cursor_on(bufnr, "y")
      feed("g>")
      H.eq(H.lines(bufnr), { "int a = f(x, z, y);" })
    end)
  end)

  H.test("with both engines off nothing happens", function()
    with({ treesitter = { enabled = false }, fallback = { enabled = false } }, function()
      local bufnr = H.buf({ "f(x, y, z);" }, "c")
      H.cursor_on(bufnr, "y")
      feed("g>")
      H.eq(H.lines(bufnr), { "f(x, y, z);" })
    end)
  end)

  H.test("highlighting can be turned off", function()
    with({ highlight = { enabled = false } }, function()
      local bufnr = H.buf({ "f(a, b, c);" }, "c")
      H.cursor_on(bufnr, "a,")
      local region = swap.region_at()
      require("swap.highlight").show(region, 1)
      H.eq(vim.api.nvim_buf_get_extmarks(bufnr, require("swap.highlight").ns, 0, -1, {}), {})
    end)
  end)
end)

H.group("api", function()
  H.test("region_at exposes the list for scripting", function()
    local bufnr = H.buf({ "f(ccc, a, bb);" }, "c")
    H.cursor_on(bufnr, "ccc")
    local region = swap.region_at()
    H.eq(region:count(), 3)
    region:sort(function(a, b)
      return #a < #b
    end)
    region:apply()
    H.eq(H.lines(bufnr), { "f(a, bb, ccc);" })
  end)

  H.test("nothing is written to the buffer before apply", function()
    local bufnr = H.buf({ "f(a, b);" }, "c")
    H.cursor_on(bufnr, "a,")
    local region = swap.region_at()
    region:swap(1, 2)
    H.eq(H.lines(bufnr), { "f(a, b);" })
    region:apply()
    H.eq(H.lines(bufnr), { "f(b, a);" })
  end)
end)

H.group("swap mode status line", function()
  local mode = require("swap.mode")

  local function width_of(chunks)
    local text = ""
    for _, chunk in ipairs(chunks) do
      text = text .. chunk[1]
    end
    return vim.fn.strdisplaywidth(text)
  end

  H.test("fits into a narrow window", function()
    for _, width in ipairs({ 20, 40, 60, 80, 100, 200 }) do
      local chunks = mode.status(3, 2, "", width)
      H.ok(width_of(chunks) <= width, ("status is wider than " .. width .. " columns"))
    end
  end)

  H.test("keeps the item counter even when very narrow", function()
    local text = ""
    for _, chunk in ipairs(mode.status(12, 7, "", 10)) do
      text = text .. chunk[1]
    end
    H.eq(text, "item 7/12")
  end)

  H.test("shows the digits waiting for <CR>", function()
    local chunks = mode.status(12, 1, "11", 200)
    H.ok(chunks[2][1]:find("11", 1, true), "the pending number is shown")
  end)

  H.test("drops hints from the right, keeping the most used", function()
    local chunks = mode.status(3, 1, "", 40)
    H.ok(chunks[3][1]:find("h/l move", 1, true), "the move hint survives")
  end)
end)
