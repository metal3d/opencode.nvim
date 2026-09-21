--- Keymap installation.
---
--- The plugin never binds keys implicitly. Users either define their own maps to
--- `require("opencode")` methods, or opt into the recommended `<leader>oc*` set
--- with `opts.keys = "recommended"`.
local M = {}

--- Namespace shared by the recommended keymaps. Defined once so the mappings and
--- the which-key group cannot drift apart.
local RECOMMENDED_PREFIX = "<leader>oc"

---@param mode string|string[]
---@param lhs string
---@param rhs fun()
---@param desc string
local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = "opencode: " .. desc })
end

--- Name the recommended prefix as a which-key group, so the popup shows
--- `+opencode` instead of a bare `c` before the mappings are expanded.
---
--- The recommended set shares a common prefix, but nothing maps the prefix
--- itself: without a name which-key renders the intermediate key unlabelled.
--- Uses which-key v3's `add`, and is a no-op when which-key is absent.
local function register_which_key_group()
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk) ~= "table" or type(wk.add) ~= "function" then
    return
  end
  wk.add({ { RECOMMENDED_PREFIX, group = "opencode" } })
end

--- Install the recommended keymaps (`opts.keys = "recommended"`).
---
--- A `<leader>oc*` namespace covering the common actions. They can be freely
--- overridden by the user's own mappings.
function M.install()
  local oc = require("opencode")
  local p = RECOMMENDED_PREFIX
  map({ "n", "x" }, p .. "t", function()
    oc.toggle()
  end, "toggle the panel")
  map({ "n", "x" }, p .. "a", function()
    oc.ask()
  end, "ask about the context")
  map({ "n", "x" }, p .. "A", function()
    oc.append()
  end, "add context to the prompt")
  map({ "n", "x" }, p .. "r", function()
    oc.review()
  end, "review @this")
  map({ "n", "x" }, p .. "f", function()
    oc.fix()
  end, "fix @diagnostics")
  map("n", p .. "e", function()
    oc.explain()
  end, "explain @this")
  map("n", p .. "u", function()
    oc.audit()
  end, "audit @this")
  map("n", p .. "s", function()
    oc.session()
  end, "switch session")
  map("n", p .. "c", function()
    oc.command()
  end, "action palette")
  map("n", p .. "d", function()
    oc.diff()
  end, "session diff")
  register_which_key_group()
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
