--- User configuration and its defaults.
local M = {}

---@class swap.Config
local defaults = {
  --- Key mappings created on startup. Set a field to `false` to skip it; the
  --- corresponding `<Plug>` mapping stays available either way.
  keymaps = {
    prev = "g<", --- swap the item under the cursor with the previous one
    next = "g>", --- swap the item under the cursor with the next one
    interactive = "gs", --- enter swap mode (normal and visual)
    textobject_i = false, --- e.g. 'i,' — the item under the cursor
    textobject_a = false, --- e.g. 'a,' — the item plus one delimiter
  },

  treesitter = {
    enabled = true,

    --- Anonymous tokens that separate items of a list. Keep this set small:
    --- tokens such as `=` or `:` join an item to its value rather than
    --- separating two items of the same kind.
    separators = { ",", ";" },

    --- Binary operator chains such as `a + b + c` are parsed as nested
    --- two-operand nodes. When enabled, a run of nested nodes of the same type
    --- sharing one operator is flattened into a single list of operands.
    chains = {
      enabled = true,
      --- Only associative operators are listed: reordering the operands of
      --- `a - b` or `a < b` changes what the expression means, so those are
      --- left alone unless you ask for them.
      operators = { "+", "*", "..", "|", "&", "||", "&&", "or", "and" },
    },

    --- Nodes whose named children are whitespace-separated items, by language.
    --- These have no separator token, so they are opt-in per node type to keep
    --- unrelated constructs (an `if` and its body, say) from looking like a
    --- list.
    whitespace_nodes = {
      bash = { "command" },
      make = { "prerequisites" },
      ninja = { "build" },
    },

    --- Node types that are never treated as a list, by language. `'*'` applies
    --- to every language.
    ignore = {
      ["*"] = { "ERROR" },
    },
  },

  --- Regex-based scanner used when tree-sitter finds nothing, when no parser
  --- is installed, and for visual selections.
  fallback = {
    enabled = true,
    --- Bracket pairs searched for an enclosing region.
    brackets = { { "(", ")" }, { "[", "]" }, { "{", "}" } },
    --- Quote characters that hide delimiters from the scanner.
    quotes = { '"', "'", "`" },
    --- Delimiters tried in order; the first one that occurs in the region wins.
    delimiters = { ",", ";" },
    --- Split on whitespace when no delimiter occurs in the region. Off in
    --- normal mode, where it would turn `int x = 1` into a list of words; a
    --- visual selection always splits on whitespace, because there the region
    --- is the one you picked.
    whitespace = false,
    --- How many lines above and below the cursor the scanner may look at.
    max_lines = 200,
  },

  highlight = {
    enabled = true,
    --- Show the position number of each item as inline virtual text, so that
    --- the digit keys of swap mode have something to point at.
    indices = true,
    --- Highlight groups, linked in `plugin/swap.lua`.
    current = "SwapCurrentItem",
    item = "SwapItem",
    index = "SwapIndex",
  },

  swap_mode = {
    --- Show the item indices and the available keys in the command line.
    echo = true,
    --- Keys handled in swap mode. Every value is a list of keys, so a command
    --- can have several bindings; an empty list disables it.
    keys = {
      move_prev = { "h" }, --- move the current item towards the front
      move_next = { "l" }, --- move the current item towards the back
      select_prev = { "k" }, --- make the previous item current
      select_next = { "j" }, --- make the next item current
      group = { "g" }, --- group the current item with the next one
      ungroup = { "G" }, --- undo one grouping
      sort = { "s" }, --- sort ascending
      sort_reverse = { "S" }, --- sort descending
      reverse = { "r" }, --- reverse the item order
      undo = { "u" },
      redo = { "<C-r>" },
      widen = { "+" }, --- use the next enclosing list instead
      shrink = { "-" }, --- use the previously widened list again
      quit = { "<Esc>", "q" },
    },
    --- With `digits = 'immediate'` a digit selects that item right away, so
    --- only items 1 to 9 are reachable. With `digits = 'accumulate'` digits are
    --- collected until <CR> confirms them and <BS> corrects them, which reaches
    --- any item. (vim-swap calls these `impatient` and `discreet`.)
    digits = "immediate",
    --- Comparison used by `sort`. Receives two item strings.
    ---@type fun(a: string, b: string): boolean
    sort = function(a, b)
      return vim.trim(a) < vim.trim(b)
    end,
  },
}

---@type swap.Config
M.options = vim.deepcopy(defaults)

M.defaults = defaults

---@param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  -- `tbl_deep_extend` merges lists by replacing them, which is what we want for
  -- key lists, but a user-supplied `keymaps.x = false` must survive too.
  for k, v in pairs((opts or {}).keymaps or {}) do
    M.options.keymaps[k] = v
  end
  return M.options
end

--- Look up the per-language entry of a `{ [lang] = {...} }` table, merged with
--- its `'*'` entry.
---@param tbl table<string, string[]>
---@param lang string
---@return table<string, boolean>
function M.lang_set(tbl, lang)
  local set = {}
  for _, key in ipairs(tbl["*"] or {}) do
    set[key] = true
  end
  for _, key in ipairs(tbl[lang] or {}) do
    set[key] = true
  end
  return set
end

return M
