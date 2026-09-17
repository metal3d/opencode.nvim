--- opencode.nvim — Neovim + OpenCode v2 integration.
---
--- The plugin opens the real `opencode` application in a side terminal and, on
--- top of that, can drive sessions through the OpenCode HTTP API (REST + SSE):
--- prompts, context injection, reviews, permissions and diffs. This module is
--- the public entry point.
local M = {}

local config = require("opencode.config")
local discovery = require("opencode.discovery")
local client = require("opencode.client")
local session = require("opencode.session")
local context = require("opencode.context")
local input = require("opencode.input")
local panel = require("opencode.panel")
local events = require("opencode.event")
local permission = require("opencode.permission")
local diff = require("opencode.diff")
local bindings = require("opencode.bindings")

local state = { connected = false, connecting = false }
M.state = state

local function notify(msg, level)
  vim.notify("opencode: " .. msg, level or vim.log.levels.ERROR)
end

--- Connect to an OpenCode server (discovery, auth and event subscription).
---@param cb? fun(err?: string)
function M.connect(cb)
  cb = cb or function() end
  if client.connected() and state.connected then
    cb(nil)
    return
  end
  if state.connecting then
    return
  end
  state.connecting = true

  local opts = config.get()
  local finish = function(err, server)
    state.connecting = false
    if err then
      cb(err)
      return
    end
    client.set_server(server)
    state.connected = true
    if opts.server.connect then
      events.subscribe()
    end
    cb(nil)
  end

  local function validate(server)
    client.set_server(server)
    client.api("GET", "/api/info", nil, function(res)
      if res.err then
        finish(res.err)
      else
        -- Detect legacy TUI control so prompts can target the active tab.
        client.detect_tui(function()
          finish(nil, server)
        end)
      end
    end)
  end

  local function try_disco()
    local reg = discovery.read_registration()
    if reg then
      validate({ url = reg.url, password = reg.password, username = opts.server.username })
      return
    end
    discovery.start(function(start_err)
      if start_err then
        finish(start_err)
        return
      end
      local r2 = discovery.read_registration()
      if r2 then
        validate({ url = r2.url, password = r2.password, username = opts.server.username })
      else
        finish("could not start the opencode service")
      end
    end)
  end

  if opts.server.url then
    if opts.server.password then
      validate({ url = opts.server.url, password = opts.server.password, username = opts.server.username })
    else
      finish("server.url is set but server.password is missing")
    end
  else
    try_disco()
  end
end

--- Ensure a connected server and a targeted session, then run `cb`.
---@param cb fun(err?: string)
function M.ensure(cb)
  if client.connected() and session.get_target() then
    cb(nil)
    return
  end
  M.connect(function(err)
    if err then
      cb(err)
      return
    end
    session.ensure(vim.fn.getcwd(), function(res)
      if res.err then
        cb(res.err)
        return
      end
      cb(nil)
    end)
  end)
end

--- Ensure a connection, then run `cb`.
---@param cb fun(err?: string)
local function with_target(cb)
  M.ensure(cb)
end

--- Toggle the side terminal running the OpenCode application. When possible,
--- the app opens directly in the active session (see `panel.open`).
function M.toggle()
  if panel.is_open() then
    panel.close()
    return
  end
  -- Resolve the active session first so the app can open into it. Always open,
  -- even if connecting fails (the app manages its own service discovery).
  M.ensure(function()
    panel.open()
  end)
end

--- Kill and respawn the OpenCode terminal (apply `panel.open` changes).
function M.restart()
  panel.restart()
end

--- Open a floating input popup to ask about the current context (selection or
--- cursor line). The popup is empty; the context reference is injected into the
--- prompt on submit (not shown to the user).
function M.ask()
  -- Capture the context now (we may be in visual mode and lose it in the popup).
  local ref = context.render("@this")
  input.input("", function(text)
    local full = ref ~= "" and (ref .. ": " .. text) or text
    M.prompt(full)
  end)
end

--- Send a prompt through the legacy TUI control (lands in the active tab).
---@param text string
---@param cb fun(result: { err?: string })
local function tui_send(text, cb)
  client.api("POST", "/tui/append-prompt", { text = text }, function(r1)
    if r1.err then
      cb({ err = r1.err })
      return
    end
    client.api("POST", "/tui/execute-command", { command = "prompt.submit" }, function(r2)
      cb(r2.err and { err = r2.err } or {})
    end)
  end)
end

--- Deliver a prompt to OpenCode.
---
--- Prefers injecting into the running TUI terminal, so the text lands in the tab
--- the user is looking at. Falls back to `/tui/append-prompt` when available, or
--- to the v2 API targeting the owned session otherwise.
---@param text string
---@param cb fun(result: { err?: string })
local function deliver(text, cb)
  local spawned = panel.open()
  local function go()
    if panel.send(text) then
      cb({})
      return
    end
    if client.tui then
      tui_send(text, cb)
      return
    end
    session.prompt(text, {}, function(res)
      cb(res.err and { err = res.err } or {})
    end)
  end
  -- Give a freshly spawned TUI a moment to be ready for input.
  if spawned then
    panel.wait_ready(function()
      vim.defer_fn(go, 200)
    end)
  else
    go()
  end
end

--- Send a prompt, expanding any context placeholders.
---@param text string
---@param cb? fun(result: { err?: string })
function M.prompt(text, cb)
  cb = cb or function() end
  with_target(function(err)
    if err then
      notify(err)
      cb({ err = err })
      return
    end
    deliver(context.render(text), function(res)
      if res.err then
        notify(res.err)
      end
      cb(res)
    end)
  end)
end

--- Send the current line to OpenCode.
function M.send()
  local line = vim.fn.getline(".")
  if line == "" then
    return
  end
  M.prompt(line)
end

--- Run one of the built-in named prompts (review, fix, explain, …).
---@param name string
local function run_prompt(name)
  with_target(function(err)
    if err then
      notify(err)
      return
    end
    local templates = config.get().prompts
    deliver(context.render(templates[name] or "@this"), function(res)
      if res.err then
        notify(res.err)
      end
    end)
  end)
end

function M.review()
  run_prompt("review")
end

function M.fix()
  run_prompt("fix")
end

function M.explain()
  run_prompt("explain")
end

--- Audit the referenced lines (bugs, edge cases, security).
function M.audit()
  run_prompt("audit")
end

--- Action/command palette. With no argument it opens a picker; with an action
--- id it runs that action directly.
---@param action string?
function M.command(action)
  local actions = {
    { id = "toggle", label = "Open OpenCode" },
    { id = "ask", label = "Ask OpenCode…" },
    { id = "review", label = "Review @this" },
    { id = "audit", label = "Audit @this" },
    { id = "fix", label = "Fix @diagnostics" },
    { id = "explain", label = "Explain @this" },
    { id = "session", label = "Switch session" },
    { id = "diff", label = "View session diff" },
    { id = "permissions", label = "Pending permissions" },
    { id = "compact", label = "Compact session" },
    { id = "interrupt", label = "Interrupt session" },
  }
  if not action then
    vim.ui.select(actions, {
      prompt = "opencode:",
      format_item = function(i)
        return i.label
      end,
    }, function(choice)
      if choice then
        M.command(choice.id)
      end
    end)
    return
  end
  if action == "toggle" then
    return M.toggle()
  elseif action == "ask" then
    return M.ask()
  elseif action == "review" then
    return M.review()
  elseif action == "audit" then
    return M.audit()
  elseif action == "fix" then
    return M.fix()
  elseif action == "explain" then
    return M.explain()
  elseif action == "session" then
    return M.session()
  elseif action == "diff" then
    return M.diff()
  elseif action == "permissions" then
    return M.permissions()
  elseif action == "compact" then
    return M.compact()
  elseif action == "interrupt" then
    return M.interrupt()
  end
end

--- List sessions and switch the target (or create a new one).
function M.session()
  session.list(function(res)
    if res.err then
      notify(res.err)
      return
    end
    local items = { { id = "__new__", title = "+ New session" } }
    for _, s in ipairs(res.data or {}) do
      items[#items + 1] = s
    end
    vim.ui.select(items, {
      prompt = "opencode: session",
      format_item = function(s)
        if s.id == "__new__" then
          return s.title
        end
        local title = (s.title ~= nil and s.title ~= "") and s.title or s.id
        local dir = (s.location or {}).directory or "?"
        return title .. "  [" .. dir .. "]"
      end,
    }, function(choice)
      if not choice then
        return
      end
      if choice.id == "__new__" then
        session.create(vim.fn.getcwd(), function(r)
          if r.err then
            notify(r.err)
            return
          end
          panel.restart()
          notify("new session: " .. tostring(session.get_target()), vim.log.levels.INFO)
        end)
      else
        session.set_target(choice.id)
        panel.restart()
        notify("switched to " .. choice.id, vim.log.levels.INFO)
      end
    end)
  end)
end

--- Inspect the current session's file changes.
function M.diff()
  diff.preview()
end

--- Surface pending permission requests.
function M.permissions()
  permission.prompt_pending()
end

--- Compact the target session.
function M.compact()
  M.ensure(function(err)
    if err then
      notify(err)
      return
    end
    session.compact(function(res)
      if res.err then
        notify(res.err)
      end
    end)
  end)
end

--- Interrupt the target session.
function M.interrupt()
  M.ensure(function(err)
    if err then
      notify(err)
      return
    end
    session.interrupt(function(res)
      if res.err then
        notify(res.err)
      end
    end)
  end)
end

--- A short status string for statuslines.
---@return string
function M.statusline()
  if not state.connected then
    return ""
  end
  if not session.get_target() then
    return "opencode:connecting"
  end
  return "opencode"
end

--- Format an editor location as an OpenCode reference.
---@param entry { path?: string, buf?: integer, from?: integer[], to?: integer[] }
---@return string
function M.format(entry)
  return require("opencode.context").format(entry) or ""
end

--- Operator-style prompt over a motion/selection.
---@param text string
---@return string # The `g@` operator invocation.
function M.operator(text)
  local function run()
    local a = vim.fn.getpos("'[")
    local b = vim.fn.getpos("']")
    local lines = vim.api.nvim_buf_get_lines(0, a[2] - 1, b[2], false)
    local sel = table.concat(lines, "\n")
    if sel ~= "" then
      M.prompt((text or "") .. sel)
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  end
  vim.go.operatorfunc = run
  return "g@"
end

--- Call the plugin setup: applies user keymaps and reload settings.
function M.setup()
  local opts = config.get()
  if opts.events.reload then
    vim.opt.autoread = true
  end
  bindings.apply()
end

-- Alias kept for discoverability; config still lives in `vim.g.opencode_opts`.
M.config = config

return M