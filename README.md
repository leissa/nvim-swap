# nvim-swap

[![tests](https://img.shields.io/github/actions/workflow/status/leissa/nvim-swap/test.yml?branch=master&label=tests&style=flat-square&logo=neovim&logoColor=white)](https://github.com/leissa/nvim-swap/actions/workflows/test.yml)

Reorder delimited items — arguments, parameters, list elements, table fields —
without cutting and pasting. A Lua and tree-sitter rewrite of
[vim-swap](https://github.com/machakann/vim-swap), for Neovim 0.11+.

```c
foo(alpha, beta, gamma);
//         ^ cursor here, press g<

foo(beta, alpha, gamma);
```

## Why tree-sitter

vim-swap recognises lists with a table of regular expressions, one rule per
shape of list. nvim-swap asks the syntax tree instead, which means it knows what
is an item and what is punctuation in the language you are actually editing —
without a rule per language:

```python
def f(a, b=2, *args, **kw):   # items: a · b=2 · *args · **kw
```
```c
for (i = 0; i < n; ++i)       # items: i = 0 · i < n · ++i
int a, b;                     # items: a · b        (not "int a")
f(a, g(b, c), d)              # items: a · g(b, c) · d
x = a + b + c                 # items: a · b · c    (chains are flattened)
```

Strings and nested brackets take care of themselves, wrapped argument lists keep
their line breaks and indentation, and injected languages (a SQL string, a code
block in Markdown) are parsed as themselves. Buffers with no parser fall back to
a bracket- and quote-aware scanner, so the plugin still works in a plain text
file.

## Install

Neovim 0.11 or later. Tree-sitter parsers come from wherever you already install
them — there is no extra dependency.

The plugin maps its keys as soon as it is loaded, so on every manager below the
plugin alone is enough; `setup()` is optional and only needed to change
something.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{ "leissa/nvim-swap", opts = {} }
```

### [vim.pack](https://neovim.io/doc/user/pack.html) (built in, Neovim 0.12+)

```lua
vim.pack.add({ "https://github.com/leissa/nvim-swap" })
```

### [mini.deps](https://github.com/echasnovski/mini.deps)

```lua
MiniDeps.add({ source = "leissa/nvim-swap" })
```

### [paq-nvim](https://github.com/savq/paq-nvim)

```lua
require("paq")({ "leissa/nvim-swap" })
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use({ "leissa/nvim-swap" })
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'leissa/nvim-swap'
```

### Without a manager

```
git clone https://github.com/leissa/nvim-swap \
  ~/.local/share/nvim/site/pack/plugins/start/nvim-swap
```

## Keys

| key  | mode   | what it does                                         |
| ---- | ------ | ---------------------------------------------------- |
| `g<` | normal | swap the item under the cursor with the previous one |
| `g>` | normal | swap the item under the cursor with the next one     |
| `gs` | normal | enter swap mode on the list around the cursor        |
| `gs` | visual | enter swap mode on the selection                     |

`g<` and `g>` take a count — `3g>` moves the item three places to the right —
and everything repeats with `.`.

### Swap mode

`gs` highlights and numbers every item of the list, marks the one under the
cursor, and then waits:

```
foo(1alpha, 2beta, 3gamma);
    ^^^^^ the current item
```

| key           | what it does                                     |
| ------------- | ------------------------------------------------ |
| `h` / `l`     | move the current item left / right               |
| `j` / `k`     | make the next / previous item current            |
| `1` … `9`     | make the *n*th item current                      |
| `g` / `G`     | group the current item with the next one / split |
| `s` / `S`     | sort ascending / descending                      |
| `r`           | reverse                                          |
| `u` / `<C-r>` | undo / redo                                      |
| `+` / `-`     | widen to the enclosing list / back in again      |
| `<Esc>`, `q`  | leave                                            |

The whole session is one undo step, so a single `u` afterwards puts everything
back, and `.` replays the session on the next list.

`+` and `-` have no counterpart in vim-swap: because the syntax tree knows how
lists nest, `gs+` on `b` in `f(a, g(b, c), d)` switches from `b · c` to
`a · g(b, c) · d` without leaving swap mode.

In visual mode, a charwise selection is split on delimiters (or on whitespace if
it holds none), and a linewise or blockwise selection makes each line an item —
which is how you reorder a few lines, or a column of a block.

## Text objects

Unmapped by default:

```lua
{
  "leissa/nvim-swap",
  opts = {
    keymaps = { textobject_i = "i,", textobject_a = "a," },
  },
}
```

`i,` is the item under the cursor, `a,` includes one delimiter, and both take a
count: `d2a,` deletes two arguments, comma and all.

## Configuration

Every default, in full:

```lua
require("swap").setup({
  keymaps = {
    prev = "g<",
    next = "g>",
    interactive = "gs",
    textobject_i = false,
    textobject_a = false,
  },

  treesitter = {
    enabled = true,
    -- Tokens that separate items. Keep this small: `=` and `:` join an item to
    -- its value rather than separating two items.
    separators = { ",", ";" },
    chains = {
      enabled = true,
      -- Only associative operators, since reordering the operands of `a - b`
      -- changes what it means.
      operators = { "+", "*", "..", "|", "&", "||", "&&", "or", "and" },
    },
    -- Nodes whose named children are whitespace-separated items.
    whitespace_nodes = {
      bash = { "command" },
      make = { "prerequisites" },
      ninja = { "build" },
    },
    ignore = { ["*"] = { "ERROR" } },
  },

  -- Used when tree-sitter has no parser or finds no list.
  fallback = {
    enabled = true,
    brackets = { { "(", ")" }, { "[", "]" }, { "{", "}" } },
    quotes = { '"', "'", "`" },
    delimiters = { ",", ";" },
    whitespace = false, -- a visual selection always splits on whitespace
    max_lines = 200,
  },

  highlight = {
    enabled = true,
    indices = true, -- the little item numbers
    current = "SwapCurrentItem", -- linked to IncSearch
    item = "SwapItem", -- linked to Underlined
    index = "SwapIndex", -- linked to LineNr
  },

  swap_mode = {
    echo = true,
    keys = {
      move_prev = { "h" },
      move_next = { "l" },
      select_prev = { "k" },
      select_next = { "j" },
      group = { "g" },
      ungroup = { "G" },
      sort = { "s" },
      sort_reverse = { "S" },
      reverse = { "r" },
      undo = { "u" },
      redo = { "<C-r>" },
      widen = { "+" },
      shrink = { "-" },
      quit = { "<Esc>", "q" },
    },
    -- "immediate": a digit selects that item at once, reaching items 1 to 9.
    -- "accumulate": digits are collected until <CR>, reaching any item.
    digits = "immediate",
    sort = function(a, b)
      return vim.trim(a) < vim.trim(b)
    end,
  },
})
```

To map the `<Plug>` mappings yourself, set the `keymaps` entries to `false` and
use `<Plug>(swap-prev)`, `<Plug>(swap-next)`, `<Plug>(swap-interactive)`,
`<Plug>(swap-textobject-i)` and `<Plug>(swap-textobject-a)`.

## Scripting

`require("swap").region_at()` returns the list around the cursor as a region
object with `:swap(i, j)`, `:sort(cmp, descending)`, `:reverse()`, `:group(i)`,
`:ungroup(i)` and `:apply()`:

```lua
local region = require("swap").region_at()
if region then
  region:sort(function(a, b)
    return #a < #b -- shortest argument first
  end)
  region:apply()
end
```

## Differences from vim-swap

- Items come from the syntax tree, not from `g:swap#rules`; there is nothing to
  configure per language.
- `+` and `-` in swap mode move between nested lists.
- Items are numbered on screen, so the digit keys have something to point at.
- Operator chains such as `a + b + c` are flattened into one list.
- Whitespace splitting in normal mode is off by default; in visual mode, where
  you have said what the region is, it is always available.

## Tests

```
make test
```

Runs on Neovim alone — no test framework to install.

## Credits

[machakann](https://github.com/machakann) for vim-swap, whose behaviour and key
layout this follows.
