--- Extmark based highlighting of the items in swap mode.
local config = require("swap.config")

local M = {}

M.ns = vim.api.nvim_create_namespace("swap")

---@param bufnr integer
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
end

--- Highlight every item of the region and mark the current one.
---@param region swap.Region
---@param current integer 1-based index of the current item
function M.show(region, current)
  local opts = config.options.highlight
  if not opts.enabled then
    return
  end
  local bufnr = region.bufnr
  M.clear(bufnr)

  for i, r in ipairs(region:ranges()) do
    vim.api.nvim_buf_set_extmark(bufnr, M.ns, r[1], r[2], {
      end_row = r[3],
      end_col = r[4],
      hl_group = i == current and opts.current or opts.item,
      priority = i == current and 201 or 200,
    })
    if opts.indices then
      vim.api.nvim_buf_set_extmark(bufnr, M.ns, r[1], r[2], {
        virt_text = { { tostring(i), opts.index } },
        virt_text_pos = "inline",
        priority = 202,
      })
    end
  end
end

return M
