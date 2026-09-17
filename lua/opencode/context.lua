--- Editor context capture for prompts.
---
--- OpenCode gathers the actual file content from disk when it sees a location
--- reference, so the plugin's job is to emit references — not to copy text.
--- The reference syntax is `path:L<line>:C<col>-L<line>:C<col>` (1-based),
--- relative to the session directory when the file lives inside it.
local M = {}

--- Base directory used to make references relative.
---@return string
local function rel_base()
  return vim.fn.getcwd()
end

--- Read a buffer range as plain text (used for buffers with no backing file).
---@param buf integer
---@param from integer[]
---@param to integer[]
---@return string
local function buffer_text(buf, from, to)
  local start_line = math.max(1, from[1])
  local end_line = math.min(to[1], vim.api.nvim_buf_line_count(buf))
  return table.concat(vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false), "\n")
end

--- Make `path` relative to the working directory.
---
--- Also matches through symlinks: the buffer path and the working directory may
--- reach the same file through different symbolic links (`/link/proj` vs
--- `/mnt/proj`), which would otherwise yield an absolute reference.
---@param path string
---@return string
local function relative_to_cwd(path)
  local base = vim.fn.fnamemodify(rel_base(), ":p"):gsub("/$", "")
  local abs = vim.fn.fnamemodify(path, ":p")
  local candidates = {
    { abs, base },
    { vim.fn.resolve(abs), vim.fn.resolve(base) },
  }
  for _, pair in ipairs(candidates) do
    local p, b = pair[1], pair[2]
    if p:sub(1, #b + 1) == b .. "/" then
      return p:sub(#b + 2)
    end
  end
  return abs
end

--- Format a location the way OpenCode expects.
---@param opts { path?: string, buf?: integer, from?: integer[], to?: integer[] }
---@return string? # Reference, or inline text for non-file buffers, or nil.
function M.format(opts)
  local path = opts.path or (opts.buf and vim.api.nvim_buf_get_name(opts.buf)) or nil
  if not path or path == "" then
    return nil
  end

  local from, to = opts.from, opts.to
  if from and to and (from[1] > to[1] or (from[1] == to[1] and (from[2] or 0) > (to[2] or 0))) then
    from, to = to, from
  end

  -- A buffer whose backing file is gone: fall back to inline text when we have
  -- a buffer to read from (a bare `path` with no buffer yields nothing).
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then
    if not opts.buf then
      return nil
    end
    return buffer_text(opts.buf, from or { 1 }, to or { vim.api.nvim_buf_line_count(opts.buf) })
  end

  local result = relative_to_cwd(path)

  if from then
    result = result .. ":L" .. from[1]
    if from[2] then
      result = result .. ":C" .. from[2]
    end
    if to then
      result = result .. "-L" .. to[1]
      if to[2] then
        result = result .. ":C" .. to[2]
      end
    end
  end
  return result
end

--- The current visual selection range, if any.
---
--- When the mapping fires from visual mode, the `'<`/`'>` marks are not yet
--- updated, so read the live selection (`v` mark + cursor) instead.
---@return { from: integer[], to: integer[], kind: string }?
local function selection_range()
  local mode = vim.fn.mode()
  local visual = mode == "v" or mode == "V" or mode == "\22"
  local a, b
  if visual then
    a = vim.fn.getpos("v")
    b = vim.fn.getpos(".")
  else
    a = vim.fn.getpos("'<")
    b = vim.fn.getpos("'>")
  end
  if a[2] == 0 and b[2] == 0 then
    return nil
  end
  local from = { a[2], a[3] }
  local to = { b[2], b[3] }
  if from[1] == to[1] and from[2] == to[2] then
    return nil
  end
  if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
    from, to = to, from
  end
  return { from = from, to = to, kind = visual and mode or vim.fn.visualmode() }
end

--- Reference for the range (selection if present) or the cursor line.
---@return string?
function M.this()
  local buf = vim.api.nvim_get_current_buf()
  local range = selection_range()
  if range then
    if range.kind == "V" then
      return M.format({ buf = buf, from = { range.from[1] }, to = { range.to[1] } })
    end
    return M.format({ buf = buf, from = range.from, to = range.to })
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  return M.format({ buf = buf, from = { pos[1], pos[2] + 1 } })
end

--- Reference for the visual selection.
---@return string?
function M.selection()
  local buf = vim.api.nvim_get_current_buf()
  local range = selection_range()
  if not range then
    return nil
  end
  if range.kind == "V" then
    return M.format({ buf = buf, from = { range.from[1] }, to = { range.to[1] } })
  end
  return M.format({ buf = buf, from = range.from, to = range.to })
end

--- Reference for the whole current buffer.
---@return string?
function M.buffer()
  return M.format({ buf = vim.api.nvim_get_current_buf() })
end

--- References for every listed buffer.
---@return string?
function M.buffers()
  local refs = {}
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local ref = M.format({ buf = info.bufnr })
    if ref then
      refs[#refs + 1] = ref
    end
  end
  if #refs == 0 then
    return nil
  end
  return table.concat(refs, ", ")
end

--- Reference for the current file.
---@return string?
function M.file()
  return M.format({ buf = vim.api.nvim_get_current_buf() })
end

--- Diagnostics for the current buffer (or the selection), as a reference list.
--- Falls back to all diagnostics when the current buffer has none. The list is
--- capped so a "fix" prompt never balloons.
---@return string?
function M.diagnostics()
  local buf = vim.api.nvim_get_current_buf()
  local diags = vim.diagnostic.get(buf)

  local range = selection_range()
  if range then
    local from_line, to_line = range.from[1], range.to[1]
    diags = vim.tbl_filter(function(d)
      return d.lnum + 1 <= to_line and (d.end_lnum or d.lnum) + 1 >= from_line
    end, diags)
  end

  if #diags == 0 then
    -- Nothing in the current buffer: use every known diagnostic so a "fix"
    -- request is still useful.
    diags = vim.diagnostic.get()
  end

  if #diags == 0 then
    return nil
  end

  local total = #diags
  local limit = 50
  local lines = {
    total > limit and ("%d diagnostic(s) (showing %d):"):format(total, limit) or ("%d diagnostic(s):"):format(total),
  }
  for i, d in ipairs(diags) do
    if i > limit then
      break
    end
    local ref = M.format({
      buf = d.bufnr,
      from = { d.lnum + 1, d.col + 1 },
      to = { (d.end_lnum or d.lnum) + 1, (d.end_col or d.col) + 1 },
    })
    lines[#lines + 1] = ("- %s (%s): %s"):format(
      ref or "?",
      d.source or "unknown",
      vim.trim((d.message or ""):gsub("%s+", " "))
    )
  end
  if total > limit then
    lines[#lines + 1] = ("… and %d more"):format(total - limit)
  end
  return table.concat(lines, "\n")
end

-- Placeholder name -> reference producer.
local handlers = {
  this = M.this,
  selection = M.selection,
  buffer = M.buffer,
  buffers = M.buffers,
  file = M.file,
  diagnostics = M.diagnostics,
}

--- Placeholder names, longest first so `@buffers` is never shadowed by
--- `@buffer`. Computed once at load time.
local names = {}
for name in pairs(handlers) do
  names[#names + 1] = name
end
table.sort(names, function(a, b)
  return #a > #b
end)

--- Match a placeholder name starting at `at`, requiring a word boundary after
--- the token (so `@buffers` is not read as `@buffer` followed by `s`).
---@param prompt string
---@param at integer Byte index of the `@`.
---@return string? name
local function match_name(prompt, at)
  for _, name in ipairs(names) do
    local stop = at + #name + 1
    if prompt:sub(at, stop - 1) == "@" .. name then
      local after = prompt:sub(stop, stop)
      if after == "" or not after:match("%w") then
        return name
      end
    end
  end
  return nil
end

--- Expand `@placeholder` occurrences in `prompt` into references.
---
--- Single left-to-right pass: inserted values are never rescanned (so a value
--- containing `@name` is left intact), and the replacement is built with plain
--- concatenation rather than `string.gsub`, so a `%` in a value (e.g. a
--- diagnostic message like "100% done") is preserved verbatim.
---@param prompt string
---@return string
function M.render(prompt)
  local out = {}
  local pos = 1
  local n = #prompt
  while pos <= n do
    local at = prompt:find("@", pos, true)
    if not at then
      out[#out + 1] = prompt:sub(pos)
      break
    end
    local name = match_name(prompt, at)
    if name then
      out[#out + 1] = prompt:sub(pos, at - 1)
      out[#out + 1] = handlers[name]() or ""
      pos = at + #name + 1
    else
      -- Not a known placeholder: keep the `@` and resume after it.
      out[#out + 1] = prompt:sub(pos, at)
      pos = at + 1
    end
  end
  return vim.trim(table.concat(out))
end

return M
