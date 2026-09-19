---Shared helpers for reading OpenCode's on-disk state.
local M = {}

---Resolve OpenCode's state directory, honoring `$XDG_STATE_HOME`.
---
---@return string
function M.state_dir()
  local state_home = vim.env.XDG_STATE_HOME
  if state_home and state_home ~= "" then
    return vim.fs.joinpath(state_home, "opencode")
  end
  return vim.fs.joinpath(vim.env.HOME or "", ".local", "state", "opencode")
end

---The last open session tab opencode recorded for a directory in its per-directory
---tabs, if any.
---
---@param directory string
---@return string?
function M.last_tab_session(directory)
  local path = vim.fs.joinpath(M.state_dir(), "latest", "tui", "tabs.json")
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    return nil
  end
  local decoded_ok, decoded = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if not decoded_ok or type(decoded) ~= "table" or type(decoded.cwd) ~= "table" then
    return nil
  end
  local tabs = decoded.cwd[directory] and decoded.cwd[directory].tabs
  local last = tabs and tabs[#tabs]
  return last and last.sessionID or nil
end

return M
