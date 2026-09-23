if vim.g.loaded_swap then
  return
end
vim.g.loaded_swap = true

local function hl(name, link)
  vim.api.nvim_set_hl(0, name, { link = link, default = true })
end

hl("SwapCurrentItem", "IncSearch")
hl("SwapItem", "Underlined")
hl("SwapIndex", "LineNr")

-- Everything goes through 'operatorfunc' (`g@`) so that the dot command
-- repeats it. `:<C-u>` in the visual mapping leaves visual mode first; `gv`
-- then hands the very same selection to the operator.
local function plug(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { silent = true, desc = desc })
end

plug("n", "<Plug>(swap-prev)", "<Cmd>lua require('swap.ops').prev()<CR>g@l", "swap item with the previous one")
plug("n", "<Plug>(swap-next)", "<Cmd>lua require('swap.ops').next()<CR>g@l", "swap item with the next one")
plug("n", "<Plug>(swap-interactive)", "<Cmd>lua require('swap.ops').interactive()<CR>g@l", "swap mode")
plug("x", "<Plug>(swap-interactive)", ":<C-u>lua require('swap.ops').visual()<CR>gvg@", "swap mode on the selection")

plug({ "o", "x" }, "<Plug>(swap-textobject-i)", function()
  require("swap.textobj").select("i")
end, "swappable item")

plug({ "o", "x" }, "<Plug>(swap-textobject-a)", function()
  require("swap.textobj").select("a")
end, "swappable item and delimiter")

require("swap").apply_keymaps()
