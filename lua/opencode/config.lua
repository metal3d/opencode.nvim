--- Configuration management for opencode.nvim.
---
--- Users configure the plugin through `require("opencode").setup(opts)`, which
--- is what lazy.nvim calls automatically when a spec uses `opts = { ... }`.
--- The legacy global `vim.g.opencode_opts` is still honoured, and takes
--- precedence over the defaults but not over `setup(opts)`.
---@diagnostic disable-next-line
local util = require("opencode.util")

---@class opencode.server.Opts
---@field username? string HTTP basic auth username (defaults to "opencode").
---@field url? string Explicit server base URL; nil auto-discovers the service.
---@field password? string Basic auth password; nil reads it from service.json.
---@field connect boolean Subscribe to server events once discovered.
---@field start? fun(cb: fun(err?: string)) Custom server boot function.

---@class opencode.panel.Opts
---@field size? integer Panel width in columns; nil uses the natural split width.
---@field position "left"|"right" Which edge the panel is attached to.
---@field open "session"|"home"|"mini"|"continue" How the app is launched.

---@class opencode.session.Opts
---@field mode "recent"|"new" Adopt the latest session, or always create one.

---@class opencode.events.Opts
---@field reload boolean Set `vim.o.autoread` so edited buffers reload.

---@class opencode.Opts
---@field server opencode.server.Opts
---@field panel opencode.panel.Opts
---@field prompts table<string, string> Named prompt templates.
---@field keys table<string, function|string>|"recommended" Keymaps applied by `setup()`.
---@field session opencode.session.Opts
---@field events opencode.events.Opts

---@type opencode.Opts The default configuration.
local defaults = {
  server = {
    -- HTTP basic auth username. Defaults to "opencode".
    username = nil,
    -- Explicit server base URL. When nil, the background service is discovered.
    url = nil,
    -- Password for basic auth. When nil, it is read from service.json.
    password = nil,
    -- Subscribe to server events once the server is discovered.
    connect = true,
    -- Start the server when no registration is found. Provide a function
    -- `fun()` to customise; nil keeps the default `opencode service start`.
    start = nil,
  },
  panel = {
    -- Panel width, in columns. `nil` uses the natural split width (like a
    -- plain `:vsplit`, i.e. half the screen).
    size = nil,
    -- Which edge the panel is attached to: "left" or "right".
    position = "right",
    -- How the app opens:
    --   "session"  → full TUI, straight into the active session
    --   "home"     → full TUI, default dashboard
    --   "mini"     → minimal interface (much less chrome), into the session
    --   "continue" → full TUI, continue the last session
    open = "session",
  },
  prompts = {
    -- Prompt templates. `@context` placeholders are expanded into location
    -- references (opencode reads the files from disk).
    review = "Review @this for correctness and readability.",
    audit = "Audit @this for bugs, edge cases and security issues.",
    fix = "Fix @diagnostics",
    explain = "Explain @this and its context.",
    document = "Add comments documenting @this.",
    test = "Add tests for @this.",
  },
  keys = {},
  session = {
    -- "recent" adopts the most recent session for the directory; "new" always
    -- creates a dedicated session (avoids hijacking another client's session).
    mode = "recent",
  },
  events = {
    -- Set `vim.o.autoread` so buffers edited by OpenCode reload automatically.
    reload = true,
  },
}

local M = {}
M.defaults = defaults
M.opts = nil
M.user = nil

--- Store the options passed to `require("opencode").setup(opts)`.
---
--- Precedence on resolution is: defaults, then `vim.g.opencode_opts`, then
--- these options. Passing `nil` clears any previously stored options.
---@param opts opencode.Opts?
function M.setup(opts)
  M.user = opts
  M.opts = nil
end

--- Resolve the effective options, merging user settings over the defaults.
---
--- The result is cached until `M.setup()` is called again, so this is cheap to
--- call on every access.
---@return opencode.Opts
function M.get()
  if not M.opts then
    local merged = util.merge(defaults, vim.g.opencode_opts or {})
    if M.user then
      merged = util.merge(merged, M.user)
    end
    M.opts = merged
  end
  return M.opts
end

return M
