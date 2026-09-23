# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Neovim 0.11+ plugin (pure Lua, no runtime dependencies) that reorders delimited
items — call arguments, parameters, list elements, table fields. It is a
tree-sitter rewrite of [vim-swap](https://github.com/machakann/vim-swap) and
follows its key layout (`g<`, `g>`, `gs`). `README.md` documents the user-facing
behaviour and the full default configuration; `doc/swap.txt` is the same in
`:help` form. Keep all three in sync when behaviour changes.

## Commands

```sh
make test                  # whole suite: nvim --clean -l tests/run.lua
make fmt                   # stylua lua plugin tests
make fmt-check             # what CI enforces
nvim -l tests/run.lua ts   # one spec: the argument is the *_spec.lua basename
nvim -l tests/run.lua ts keys
make test NVIM=/path/to/nvim
```

Specs are `ts`, `keys`, `region`, `scan`, `config`. Tests that need a parser call
`H.skip()` when it is missing, so a green run locally may have skipped the
language cases — check the `skipped` count. CI installs the `c lua python rust
json bash` parsers via nvim-treesitter and runs against Neovim stable and
nightly.

`doc/tags` is generated (`:helptags doc`) and gitignored; regenerate rather than
edit it.

## Architecture

The pipeline is: cursor position → candidate item ranges → `Region` → mutate →
`Region:apply()`.

- `lua/swap/resolve.lua` is the single entry to "what are the items here". It
  asks `ts.lua` first and only falls back to `scan.lua` when tree-sitter returns
  nothing. `candidates()` returns *all* enclosing lists, innermost first — that
  list is what swap mode's `+`/`-` walks.
- `lua/swap/ts.lua` deliberately has no per-language node-name table. It walks up
  from the cursor node and recognises three shapes: children separated by
  anonymous separator tokens, flattened associative operator chains, and the
  opt-in `whitespace_nodes`. Two mechanisms keep items honest: `trim_brackets()`
  drops what a bracket separates from the list, and `common_fields()` uses the
  grammar's field names so `int a, b` yields `a · b` rather than `int a · b`.
  Prefer extending these shape heuristics over adding language-specific cases.
- `lua/swap/scan.lua` is the bracket- and quote-aware fallback, and is also what
  splits a charwise visual selection.
- `lua/swap/region.lua` is the core data model: `cells` (movable items) and
  `gaps` (the `#cells - 1` separators). **Gaps never move.** That invariant is
  why a wrapped argument list keeps its line breaks and indentation, and why
  every reordering operation rewrites cells only. A group is a cell with `kids`
  and the `kidgap` it absorbed.
- `lua/swap/mode.lua` is swap mode: an interactive `getcharstr()` loop. It holds
  its own undo/redo stacks of region snapshots and uses `undojoin` so the whole
  session collapses into one Neovim undo step. It also records an op log
  (`{"swap", i, j}`, `{"sort", desc}`, `{"level", n}`, …) that `M.replay()`
  re-runs for `.`.
- `lua/swap/ops.lua` is the `<Plug>` layer. Everything is funnelled through
  `'operatorfunc'` + `g@` purely to get dot-repeat; `M.prepare()` arms a
  `pending` table and `M.opfunc()` does the work.
- `plugin/swap.lua` defines the `<Plug>` mappings and default-linked highlight
  groups at load time, then calls `require("swap").apply_keymaps()`. The plugin
  is therefore usable with no `setup()` call, and `setup()` must stay optional.
  `apply_keymaps()` deletes the maps it previously created so a later `setup()`
  can rebind, and skips any key the user already mapped to the `<Plug>` target.

## Conventions

- Positions are `(row, col)`, 0-based row, 0-based **byte** column, ranges
  end-exclusive — matching `nvim_buf_*`. Converting to Vim's 1-based or
  inclusive forms happens only at the edges (`util.set_cursor`, `textobj.lua`).
- Multi-byte text is real: step over UTF-8 continuation bytes when converting an
  exclusive end to an inclusive visual end.
- stylua: 2 spaces, 120 columns.
- Every module and public function carries a LuaCATS annotation and a comment
  saying *why*, not what. Match that density; classes are `swap.Config`,
  `swap.Region`, `swap.Cell`, `swap.Candidate`.
- Config lists are replaced wholesale by `vim.tbl_deep_extend("force", …)`;
  `config.setup()` re-applies `keymaps` afterwards so a user's `false` survives.
  Per-language tables are read through `config.lang_set()`, which merges the
  `"*"` entry.
