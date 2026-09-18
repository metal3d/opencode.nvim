--- Keymap installation.
---
--- The plugin never binds keys implicitly. Users either define their own maps to
--- `require("opencode")` methods, or opt into the recommended `<leader>oc*` set
--- with `opts.keys = "recommended"`.
local M = {}

---@param mode string|string[]
---@param lhs string
---@param rhs fun()
---@param desc string
local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = "opencode: " .. desc })
end

--- Install the recommended keymaps (`opts.keys = "recommended"`).
---
--- A `<leader>oc*` namespace covering the common actions. They can be freely
--- overridden by the user's own mappings.
function M.install()
  local oc = require("opencode")
  map({ "n", "x" }, "<leader>oct", function()
    oc.toggle()
  end, "toggle the panel")
  map({ "n", "x" }, "<leader>oca", function()
    oc.ask()
  end, "ask about the context")
  map({ "n", "x" }, "<leader>ocA", function()
    oc.append()
  end, "add context to the prompt")
  map({ "n", "x" }, "<leader>ocr", function()
    oc.review()
  end, "review @this")
  map({ "n", "x" }, "<leader>ocf", function()
    oc.fix()
  end, "fix @diagnostics")
  map("n", "<leader>oce", function()
    oc.explain()
  end, "explain @this")
  map("n", "<leader>ocu", function()
    oc.audit()
  end, "audit @this")
  map("n", "<leader>ocs", function()
    oc.session()
  end, "switch session")
  map("n", "<leader>occ", function()
    oc.command()
  end, "action palette")
  map("n", "<leader>ocd", function()
    oc.diff()
  end, "session diff")
end

--- Apply the maps configured through `opts.keys`.
---
--- `keys` is either the string `"recommended"` (the `<leader>oc*` set) or a
--- table mapping an lhs to a function or a built-in action id.
function M.apply()
  local keys = require("opencode.config").get().keys
  if keys == "recommended" then
    M.install()
    return
  end
  if type(keys) ~= "table" then
    return
  end
  for lhs, action in pairs(keys) do
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
