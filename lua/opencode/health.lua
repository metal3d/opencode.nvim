--- Health check for `:checkhealth opencode`.
local M = {}

---@param name string
---@return string?
local function exepath(name)
  local ok, path = pcall(vim.fn.exepath, name)
  if ok and path ~= "" then
    return path
  end
  return nil
end

--- Run the health checks.
function M.check()
  vim.health.start("opencode")

  local curl = exepath("curl")
  if curl then
    vim.health.ok("curl found: " .. curl)
  else
    vim.health.error("curl is required but was not found")
  end

  local opencode = exepath("opencode")
  if opencode then
    vim.health.ok("opencode CLI found: " .. opencode)
  else
    vim.health.error("the opencode CLI is required but was not found")
  end

  local discovery = require("opencode.discovery")
  local reg = discovery.read_registration()
  if reg then
    vim.health.ok("background service registered at " .. reg.url)
  else
    vim.health.warn("no service.json registration found; the plugin can start one via `opencode service start`")
  end

  local config = require("opencode.config")
  local opts = config.get()
  vim.health.info("panel: " .. tostring(opts.panel.position) .. "," .. tostring(opts.panel.size))
  vim.health.info("server connect: " .. tostring(opts.server.connect))
end

return M
