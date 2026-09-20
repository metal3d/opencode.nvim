--- Discovery of the OpenCode background service registration file.
---
--- OpenCode v2 runs a background service that clients attach to. Its address
--- and generated password are persisted in `service.json` inside the OpenCode
--- state directory (`$XDG_STATE_HOME/opencode` or `~/.local/state/opencode`).
---
--- Note: this file is an implementation detail of OpenCode, not a documented
--- public contract, so its location or shape may change between releases. The
--- alternatives are limited:
---
---   - `opencode service status` prints the URL but *not* the password;
---   - `opencode pair` prints URL, username and password, but as human-oriented
---     coloured text followed by a QR code, which would mean parsing a display
---     format;
---   - `opencode service get` returns `{}` for the connection details.
---
--- Reading `service.json` stays the pragmatic choice (structured, no extra
--- process, no display to parse). If a future release moves it, `opencode pair`
--- is the fallback to reach for.
local util = require("opencode.util")

local M = {}

--- Candidate OpenCode state directories, most specific first.
---@return string[]
local function state_dirs()
  local dirs = {}
  local xdg = vim.env.XDG_STATE_HOME
  if xdg and xdg ~= "" then
    dirs[#dirs + 1] = util.join(xdg, "opencode")
  end
  dirs[#dirs + 1] = util.join(vim.env.HOME or "/", ".local", "state", "opencode")
  return dirs
end

--- Read OpenCode's service registration from its state directory.
---@return { url: string, password: string, file: string }? # nil when not found.
function M.read_registration()
  for _, dir in ipairs(state_dirs()) do
    local file = util.join(dir, "service.json")
    local data = util.read_json(file)
    if data and data.url and data.password then
      return { url = data.url, password = data.password, file = file }
    end
  end
  return nil
end

--- Start the OpenCode service using the configured strategy.
---@param cb fun(err?: string)
function M.start(cb)
  local start_fn = require("opencode.config").get().server.start
  if start_fn then
    start_fn(cb)
    return
  end
  vim.system({ "opencode", "service", "start" }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        cb("could not start opencode service: " .. (obj.stderr or ""))
        return
      end
      cb(nil)
    end)
  end)
end

return M
