-- Run with:  nvim -l tests/run.lua  [spec ...]
-- or, equivalently:  SPEC="ts keys" make test
local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

-- Tree-sitter parsers of the host configuration, when there are any, so that
-- the language tests have something to parse.
for _, dir in ipairs(vim.fn.globpath(vim.o.packpath, "*/*/*/parser", false, true)) do
  vim.opt.runtimepath:append(vim.fs.dirname(dir))
end
for _, dir in ipairs(vim.fn.glob(vim.fn.stdpath("data") .. "/lazy/*/parser", false, true)) do
  vim.opt.runtimepath:append(vim.fs.dirname(dir))
end

vim.cmd("runtime! plugin/swap.lua")

-- Spec files to run: the basenames given as arguments or in `$SPEC`, every
-- `tests/*_spec.lua` otherwise.
local selected = _G.arg or {}
if #selected == 0 then
  selected = vim.split(vim.env.SPEC or "", "%s+", { trimempty = true })
end

local specs = {}
if #selected > 0 then
  for _, name in ipairs(selected) do
    specs[#specs + 1] = root .. "/tests/" .. name .. "_spec.lua"
  end
else
  specs = vim.fn.glob(root .. "/tests/*_spec.lua", false, true)
  table.sort(specs)
end

local harness = dofile(root .. "/tests/harness.lua")
_G.H = harness
os.exit(harness.run(specs) and 0 or 1)
