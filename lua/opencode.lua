---opencode.nvim public API.
local M = {}

---@param err? string
local function on_error(err)
  if err then
    vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
  end
end

---Input a prompt for OpenCode.
---
--- - Passes the text to `prompt()`.
--- - Press `<Up>` to browse recent asks.
--- - Highlights and completes contexts and OpenCode subagents.
---   - Press `<Tab>` to trigger built-in completion.
---   - Provided by in-process LSP when using [snacks.input](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---
---@param default? string Text to pre-fill the input with.
function M.ask(default)
  M.open()
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      local context = require("opencode.context").new(server)
      return require("opencode.ui.ask").ask(default, context):next(function(input)
        return require("opencode.api.prompt").prompt(input, context)
      end)
    end)
    :catch(on_error)
end

---Select from all opencode.nvim functionality.
---
--- - Prompts
--- - Commands
--- - Servers
---
--- Highlights and previews items when using [snacks.picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md).
---
---@param opts? opencode.select.Opts Override configured options for this call.
function M.select(opts)
  M.open()
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      local context = require("opencode.context").new(server)
      return require("opencode.ui.select").select(context, opts)
    end)
    :catch(on_error)
end

M.statusline = require("opencode.events.status").statusline

---Prompt OpenCode.
---
--- - Injects configured contexts.
--- - Trailing space appends; trailing "..." opens in `ask()`.
--- - OpenCode will interpret references to files or subagents.
---
---@param prompt string
function M.prompt(prompt)
  M.open()
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      local context = require("opencode.context").new(server)
      return require("opencode.api.prompt").prompt(prompt, context)
    end)
    :catch(on_error)
end

---Command OpenCode.
---
---@param command opencode.server.Command | string
function M.command(command)
  M.open()
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      return require("opencode.api.command").command(command, server)
    end)
    :catch(on_error)
end

---Wraps `prompt` as an operator, supporting ranges and dot-repeat.
---
---@param prompt string
function M.operator(prompt)
  _G.opencode_prompt_operator = function(kind) ---@param kind "char" | "line" | "block"
    local start_pos = vim.api.nvim_buf_get_mark(0, "[")
    local end_pos = vim.api.nvim_buf_get_mark(0, "]")
    if start_pos[1] > end_pos[1] or (start_pos[1] == end_pos[1] and start_pos[2] > end_pos[2]) then
      start_pos, end_pos = end_pos, start_pos
    end

    require("opencode.server.discovery")
      .get()
      :next(function(server)
        local context = require("opencode.context").new(server, {
          from = { start_pos[1], start_pos[2] },
          to = { end_pos[1], end_pos[2] },
          kind = kind,
        })

        return require("opencode.api.prompt").prompt(prompt, context)
      end)
      :catch(on_error)
  end

  vim.o.operatorfunc = "v:lua.opencode_prompt_operator"
  return "g@"
end

---The buffer backing an OpenCode TUI opened by `toggle()`, if any.
---@type integer?
local tui_buf = nil
---The window currently showing that TUI, if visible.
---@type integer?
local tui_win = nil

---Whether the tracked TUI terminal still has a live job.
---
---@return boolean
local function tui_alive()
  return tui_buf ~= nil and vim.api.nvim_buf_is_valid(tui_buf) and (vim.bo[tui_buf].channel or 0) > 0
end

---Path to the file caching one panel session ID per working directory.
---@return string
local function panel_sessions_file()
  return vim.fs.joinpath(vim.fn.stdpath("state"), "opencode.nvim-panel-sessions.json")
end

---@return table<string, string>
local function read_panel_sessions()
  local path = panel_sessions_file()
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end
  local ok, decoded = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(path), "\n"))
  return ok and type(decoded) == "table" and decoded or {}
end

---@param sessions table<string, string>
local function write_panel_sessions(sessions)
  pcall(vim.fn.writefile, { vim.fn.json_encode(sessions) }, panel_sessions_file())
end

---Perform a bounded request against the registered OpenCode service, synchronously.
---
---@param method string
---@param path string
---@param body? string
---@return table?
local function service_request(method, path, body)
  local info = require("opencode.server.discovery").registration()
  if not info then
    return nil
  end

  local server = require("opencode.config").opts.server or {}
  local username = server.username or "opencode"
  local password = info.password or server.password

  local cmd = {
    "curl",
    "-s",
    "-S",
    "--fail-with-body",
    "--connect-timeout",
    "1",
    "--max-time",
    "3",
    "-X",
    method,
    "-H",
    "Content-Type: application/json",
    "-H",
    "Accept: application/json",
    "-H",
    "x-opencode-directory: " .. vim.uri_encode(vim.fn.getcwd()),
  }
  if password and password ~= "" then
    local token = vim.base64 and vim.base64.encode(username .. ":" .. password)
      or vim.trim(vim.fn.system({ "base64" }, username .. ":" .. password):gsub("%s+", ""))
    table.insert(cmd, "-H")
    table.insert(cmd, "Authorization: Basic " .. token)
  end
  if body then
    table.insert(cmd, "-d")
    table.insert(cmd, body)
  end
  table.insert(cmd, info.url .. path)

  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 or out == "" then
    return nil
  end
  local ok, decoded = pcall(vim.fn.json_decode, out)
  return ok and type(decoded) == "table" and decoded or nil
end

---Return the panel's session, reusing this directory's cached one while it still
---exists. Keyed per working directory so concurrent Neovim instances (and
---projects) each get their own panel session.
---
---@return string?
local function panel_session()
  local cwd = vim.fn.getcwd()
  local sessions = read_panel_sessions()
  local cached = sessions[cwd]

  if cached and cached ~= "" then
    local existing = service_request("GET", "/api/session/" .. cached)
    if existing and existing.data then
      return cached
    end
  end

  local created = service_request("POST", "/api/session", "{}")
  local id = created and created.data and created.data.id
  if id then
    sessions[cwd] = id
    write_panel_sessions(sessions)
  end
  return id
end

---Show the OpenCode TUI panel on the right.
---
---Opens `opencode` in a right-hand split, reusing the existing terminal when one
---is already running. A dedicated session is created so prompts from Neovim reach
---this panel instead of whatever session the TUI would otherwise resume.
function M.open()
  if tui_win and vim.api.nvim_win_is_valid(tui_win) then
    return
  end

  -- The panel is a local TUI attached to the local background service. When a
  -- URL is configured (e.g. a remote server), leave it alone (PR #330 review).
  if require("opencode.config").opts.server.url ~= nil then
    return
  end

  local origin = vim.api.nvim_get_current_win()
  vim.cmd("botright vsplit")
  if tui_alive() and tui_buf then
    vim.api.nvim_win_set_buf(0, tui_buf)
  else
    local session_id = panel_session()
    if session_id then
      local info = require("opencode.server.discovery").registration()
      if info then
        require("opencode.server").panel_targets[info.url] = { id = session_id, seen = false }
      end
      vim.cmd("terminal opencode --session " .. session_id)
    else
      vim.cmd("terminal opencode")
    end
    tui_buf = vim.api.nvim_get_current_buf()
  end
  tui_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(origin)
end

---Toggle the OpenCode TUI panel on the right.
---
---Opens `opencode` in a right-hand split if hidden, or hides it if visible.
---The terminal keeps running across toggles.
function M.toggle()
  if tui_win and vim.api.nvim_win_is_valid(tui_win) then
    vim.api.nvim_win_hide(tui_win)
    tui_win = nil
    return
  end
  M.open()
end

M.format = require("opencode.context").format

return M
