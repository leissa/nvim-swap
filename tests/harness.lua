--- A very small test harness, so that the suite needs nothing but Neovim.
local H = { cases = {}, failures = {}, skipped = 0, passed = 0 }

local current = ""

---@param name string
---@param fn fun()
function H.test(name, fn)
  H.cases[#H.cases + 1] = { name = current .. name, fn = fn }
end

---@param name string
---@param fn fun()
function H.group(name, fn)
  local previous = current
  current = previous .. name .. " / "
  fn()
  current = previous
end

local function render(value)
  return type(value) == "string" and string.format("%q", value) or vim.inspect(value)
end

function H.eq(actual, expected, msg)
  if not vim.deep_equal(actual, expected) then
    error(string.format("%s\n  expected: %s\n  actual:   %s", msg or "not equal", render(expected), render(actual)), 2)
  end
end

function H.ok(value, msg)
  if not value then
    error(msg or "expected a truthy value", 2)
  end
end

function H.skip(reason)
  error({ skip = reason }, 2)
end

--- Load a spec file and run everything it registered.
---@param files string[]
---@return boolean success
function H.run(files)
  for _, file in ipairs(files) do
    dofile(file)
  end

  for _, case in ipairs(H.cases) do
    local ok, err = pcall(case.fn)
    if ok then
      H.passed = H.passed + 1
      io.write("  ok    " .. case.name .. "\n")
    elseif type(err) == "table" and err.skip then
      H.skipped = H.skipped + 1
      io.write("  skip  " .. case.name .. "  (" .. err.skip .. ")\n")
    else
      H.failures[#H.failures + 1] = { name = case.name, err = err }
      io.write("  FAIL  " .. case.name .. "\n")
      io.write("        " .. tostring(err):gsub("\n", "\n        ") .. "\n")
    end
  end

  io.write(string.format("\n%d passed, %d failed, %d skipped\n", H.passed, #H.failures, H.skipped))
  return #H.failures == 0
end

--- A scratch buffer shown in the current window.
---@param lines string[]
---@param filetype? string
---@return integer bufnr
function H.buf(lines, filetype)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  if filetype then
    vim.bo[bufnr].filetype = filetype
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, nil, { error = false })
    if not ok or not parser then
      H.skip("no " .. filetype .. " parser")
    end
  end
  return bufnr
end

---@param bufnr integer
---@return string[]
function H.lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

--- Put the cursor on the first occurrence of `needle`.
---@param bufnr integer
---@param needle string
function H.cursor_on(bufnr, needle)
  for row, line in ipairs(H.lines(bufnr)) do
    local at = line:find(needle, 1, true)
    if at then
      vim.api.nvim_win_set_cursor(0, { row, at - 1 })
      return
    end
  end
  error("no such text in the buffer: " .. needle)
end

return H
