--- Tree-sitter based detection of swappable item lists.
---
--- Rather than a table of per-language node names, this walks the syntax tree
--- upwards from the cursor and recognises three shapes that occur in virtually
--- every grammar:
---
---   * a node whose children are separated by anonymous `,` / `;` tokens —
---     argument lists, parameter lists, arrays, tables, object literals, …
---   * a run of nested binary nodes sharing one operator — `a + b + c`;
---   * a node listed in `whitespace_nodes`, whose named children are the items.
local config = require("swap.config")

local M = {}

---@class swap.Candidate
---@field ranges integer[][] item ranges, { srow, scol, erow, ecol }
---@field node TSNode the node the items came from
---@field kind 'separator'|'chain'|'whitespace'

---@class swap.Child
---@field node TSNode
---@field field string|false the grammar field name, or false when unnamed

---@param node TSNode
---@return swap.Child[]
local function children(node)
  local out = {}
  for child, field in node:iter_children() do
    out[#out + 1] = { node = child, field = field or false }
  end
  return out
end

--- Bracket tokens end a list: in `for (a; b; c) body` the `)` tells us that
--- `body` is not a fourth clause.
local OPENING = { ["("] = true, ["["] = true, ["{"] = true, ["<"] = true }
local CLOSING = { [")"] = true, ["]"] = true, ["}"] = true, [">"] = true }

---@param set string[]
---@return table<string, boolean>
local function to_set(set)
  local out = {}
  for _, v in ipairs(set) do
    out[v] = true
  end
  return out
end

--- Drop what a bracket token separates from the list: anything before an
--- opening bracket that precedes the first named child, and anything from the
--- first closing bracket onwards.
---@param group swap.Child[]
---@return swap.Child[]
local function trim_brackets(group)
  local from = 1
  for i, child in ipairs(group) do
    if child.node:named() then
      break
    elseif OPENING[child.node:type()] then
      from = i + 1
    end
  end
  local to = #group
  for i = from, #group do
    local child = group[i]
    if not child.node:named() and CLOSING[child.node:type()] then
      to = i - 1
      break
    end
  end
  return vim.list_slice(group, from, to)
end

--- The grammar field names shared by every group. When a grammar labels its
--- children, this is what tells the items apart from the rest: in C's
--- `int a, b;` both `a` and `b` are `declarator`s while `int` is the `type`,
--- so the type does not become part of the first item.
---@param groups swap.Child[][]
---@return table<string, boolean>?
local function common_fields(groups)
  local common
  for _, group in ipairs(groups) do
    local fields, named = {}, false
    for _, child in ipairs(group) do
      if child.node:named() then
        named = true
        fields[child.field or ""] = true
      end
    end
    if named then
      if not common then
        common = fields
      else
        for key in pairs(common) do
          if not fields[key] then
            common[key] = nil
          end
        end
      end
    end
  end
  return (common and next(common)) and common or nil
end

--- Bounding range of the named nodes in `group`, or nil if it has none.
---@param group swap.Child[]
---@return integer[]?
local function group_range(group)
  local first, last
  for _, child in ipairs(group) do
    if child.node:named() then
      first = first or child.node
      last = child.node
    end
  end
  if not first then
    return nil
  end
  local srow, scol = first:start()
  local erow, ecol = last:end_()
  return { srow, scol, erow, ecol }
end

--- Items of a node whose children are separated by one of `separators`.
---@param node TSNode
---@param separators table<string, boolean>
---@return integer[][]?
local function separator_items(node, separators)
  local groups, current, seen = {}, {}, false
  for _, child in ipairs(children(node)) do
    if not child.node:named() and separators[child.node:type()] then
      groups[#groups + 1] = current
      current, seen = {}, true
    else
      current[#current + 1] = child
    end
  end
  groups[#groups + 1] = current
  if not seen then
    return nil
  end

  for i, group in ipairs(groups) do
    groups[i] = trim_brackets(group)
  end
  local fields = common_fields(groups)
  if fields then
    for i, group in ipairs(groups) do
      groups[i] = vim.tbl_filter(function(child)
        return not child.node:named() or fields[child.field or ""]
      end, group)
    end
  end

  local ranges = {}
  for i, group in ipairs(groups) do
    local range = group_range(group)
    if range then
      ranges[#ranges + 1] = range
    elseif i ~= 1 and i ~= #groups then
      -- An empty group in the middle means something unusual (an error node, a
      -- doubled delimiter); leave that text alone.
      return nil
    end
  end
  return #ranges >= 2 and ranges or nil
end

--- The single operator token of a two-operand node, if it has one.
---@param node TSNode
---@param operators table<string, boolean>
---@return string?
local function chain_operator(node, operators)
  local op, named = nil, 0
  for _, child in ipairs(children(node)) do
    if child.node:named() then
      named = named + 1
    elseif operators[child.node:type()] then
      if op then
        return nil
      end
      op = child.node:type()
    end
  end
  if named ~= 2 or not op then
    return nil
  end
  return op
end

--- Operands of an associative operator chain, flattened across nesting.
---@param node TSNode
---@param operators table<string, boolean>
---@return integer[][]?
local function chain_items(node, operators)
  local op = chain_operator(node, operators)
  if not op then
    return nil
  end

  -- Only the outermost node of a chain produces a candidate, so that `a + b + c`
  -- is one list of three items rather than two overlapping lists.
  local parent = node:parent()
  if parent and parent:type() == node:type() and chain_operator(parent, operators) == op then
    return nil
  end

  local ranges = {}
  local function walk(n)
    if n:type() == node:type() and chain_operator(n, operators) == op then
      for _, child in ipairs(children(n)) do
        if child.node:named() then
          walk(child.node)
        end
      end
    else
      local srow, scol, erow, ecol = n:range()
      ranges[#ranges + 1] = { srow, scol, erow, ecol }
    end
  end
  walk(node)
  return #ranges >= 2 and ranges or nil
end

--- Items of a node whose named children are separated by whitespace only.
---@param node TSNode
---@return integer[][]?
local function whitespace_items(node)
  local ranges = {}
  for _, child in ipairs(children(node)) do
    if child.node:named() then
      local srow, scol, erow, ecol = child.node:range()
      ranges[#ranges + 1] = { srow, scol, erow, ecol }
    elseif #ranges > 0 then
      -- A trailing token such as a redirection ends the list.
      break
    end
  end
  return #ranges >= 2 and ranges or nil
end

--- All item lists containing the position, innermost first.
---@param bufnr integer
---@param row integer
---@param col integer
---@return swap.Candidate[]
function M.candidates(bufnr, row, col)
  local opts = config.options.treesitter
  if not opts.enabled then
    return {}
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, nil, { error = false })
  if not ok or not parser then
    return {}
  end
  if not pcall(parser.parse, parser, true) then
    return {}
  end

  local lang = parser:lang()
  local ltree = parser:language_for_range({ row, col, row, col })
  if ltree then
    lang = ltree:lang()
  end

  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })
  if not node then
    return {}
  end

  local separators = to_set(opts.separators)
  local operators = to_set(opts.chains.operators)
  local ignore = config.lang_set(opts.ignore, lang)
  local ws_nodes = config.lang_set(opts.whitespace_nodes, lang)

  local candidates = {}
  local seen = {}
  while node do
    if not ignore[node:type()] then
      local found = {}
      local function add(kind, ranges)
        if ranges then
          found[#found + 1] = { kind = kind, ranges = ranges }
        end
      end
      add("separator", separator_items(node, separators))
      if opts.chains.enabled then
        add("chain", chain_items(node, operators))
      end
      if ws_nodes[node:type()] then
        add("whitespace", whitespace_items(node))
      end

      for _, cand in ipairs(found) do
        local first, last = cand.ranges[1], cand.ranges[#cand.ranges]
        local key = table.concat({ first[1], first[2], last[3], last[4] }, ":")
        if not seen[key] then
          seen[key] = true
          candidates[#candidates + 1] = { ranges = cand.ranges, node = node, kind = cand.kind }
        end
      end
    end
    node = node:parent()
  end
  return candidates
end

return M
