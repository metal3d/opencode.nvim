--- Small, dependency-free helpers shared across the plugin.
local M = {}

--- Deep-merge multiple tables into a new table. Later arguments win.
---@return table
function M.merge(...)
  return vim.tbl_deep_extend("force", ...)
end

--- Join path components with a slash.
---@param ... string
---@return string
function M.join(...)
  return table.concat({ ... }, "/")
end

--- Locate `name` by walking upward from `start`, returning the first match or nil.
---@param name string
---@param start? string Directory to start searching from.
---@return string?
function M.find_up(name, start)
  local dir = vim.fn.fnamemodify(start or vim.fn.getcwd(), ":p")
  while true do
    local stat = vim.uv.fs_stat(dir .. name)
    if stat and stat.type == "file" then
      return dir .. name
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      return nil
    end
    dir = parent
  end
end

--- Read and parse a JSON file, returning the decoded value or nil.
---@param path string
---@return table|nil
function M.read_json(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    return nil
  end
  return data
end

return M