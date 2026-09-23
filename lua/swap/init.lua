--- nvim-swap: reorder delimited items, driven by tree-sitter.
---
--- The public surface is small: |swap.setup()| for configuration, and a handful
--- of functions matching the `<Plug>` mappings for anyone who would rather map
--- things by hand.
local config = require("swap.config")

local M = {}

--- The `<Plug>` mapping each keymap option is bound to.
local plugs = {
  prev = "<Plug>(swap-prev)",
  next = "<Plug>(swap-next)",
  interactive = "<Plug>(swap-interactive)",
  textobject_i = "<Plug>(swap-textobject-i)",
  textobject_a = "<Plug>(swap-textobject-a)",
}

local modes = {
  prev = { "n" },
  next = { "n" },
  interactive = { "n", "x" },
  textobject_i = { "o", "x" },
  textobject_a = { "o", "x" },
}

--- Keymaps this plugin created, so that a later `setup()` can take them back.
local created = {}

--- Create the default key mappings described by `config.options.keymaps`.
function M.apply_keymaps()
  for _, map in ipairs(created) do
    pcall(vim.keymap.del, map.mode, map.lhs)
  end
  created = {}

  for name, lhs in pairs(config.options.keymaps) do
    if lhs and plugs[name] then
      for _, m in ipairs(modes[name]) do
        if vim.fn.hasmapto(plugs[name], m) == 0 then
          vim.keymap.set(m, lhs, plugs[name], { remap = true, silent = true, desc = "swap: " .. name })
          created[#created + 1] = { mode = m, lhs = lhs }
        end
      end
    end
  end
end

---@param opts? swap.Config
function M.setup(opts)
  config.setup(opts)
  M.apply_keymaps()
end

--- Swap the item under the cursor with the previous one.
function M.prev()
  require("swap.ops").prev()
end

--- Swap the item under the cursor with the next one.
function M.next()
  require("swap.ops").next()
end

--- Start swap mode on the list around the cursor.
function M.interactive()
  require("swap.ops").interactive()
end

--- Start swap mode on the visual selection.
function M.visual()
  require("swap.ops").visual()
end

--- Select the item under the cursor.
---@param kind 'i'|'a'
---@param count? integer
function M.textobject(kind, count)
  require("swap.textobj").select(kind, count)
end

--- The item list around a position, for scripting. Returns a |swap.Region|
--- whose `:swap()`, `:sort()`, `:reverse()` and `:apply()` methods do the work.
---@param bufnr? integer
---@param row? integer 0-based
---@param col? integer 0-based
---@return swap.Region?
function M.region_at(bufnr, row, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not row then
    row, col = require("swap.util").cursor(0)
  end
  return (require("swap.resolve").at_cursor(bufnr, row, col))
end

return M
