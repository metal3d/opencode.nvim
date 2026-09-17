--- Keymap installation.
---
--- The plugin never binds keys implicitly. Users either define their own maps to
--- `require("opencode")` methods, or opt into the recommended defaults.
local M = {}

---@param mode string|string[]
---@param lhs string
---@param rhs fun()
---@param desc string
local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = "opencode: " .. desc })
end

--- Install the recommended keymaps.
---
--- These intentionally only cover the most common actions and can be freely
--- overridden by the user's own mappings.
function M.install()
  local oc = require("opencode")
  map({ "n", "x" }, "<C-a>", function()
    oc.ask()
  end, "ask OpenCode about the current context")
  map({ "n", "x" }, "<C-x>", function()
    oc.command()
  end, "choose an OpenCode command")
  map("n", "<C-.>", function()
    oc.toggle()
  end, "toggle the OpenCode panel")
  map("n", "<cr>", function()
    oc.send()
  end, "send the current line to OpenCode")
end

--- Apply the maps configured through `opts.keys`.
function M.apply()
  local keys = require("opencode.config").get().keys
  for lhs, action in pairs(keys or {}) do
    if type(action) == "function" then
      map({ "n", "x" }, lhs, action, "user action")
    elseif type(action) == "string" then
      local oc = require("opencode")
      map({ "n", "x" }, lhs, function()
        oc.command(action)
      end, action)
    end
  end
end

return M