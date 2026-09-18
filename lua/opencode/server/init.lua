---@class opencode.server.Opts
---Full URL of an OpenCode server, e.g. `"http://127.0.0.1:4096"`.
---Bypasses local process discovery and connects directly.
---You _must_ run `opencode` with the `--port` flag to expose its server.
---If pointing to a headless server, you _must_ attach a TUI via `opencode attach <URL>`.
---@field url? string | fun(callback: fun(url?: string))
---@field connect? boolean Whether to connect to an OpenCode server before interacting with it, listening for events and targeting it for future interactions.
---@field username? string Basic auth username.
---@field password? string Basic auth password.
---@field start? fun() | false Start an OpenCode server. Called when none are found; will retry after.

---@class opencode.server.Credentials
---@field username? string
---@field password? string

---An OpenCode server.
---@class opencode.server.Server
---@field url string
---@field username string
---@field password? string
---@field cwd string
---@field title string
---@field subagents opencode.server.Agent[]
---@field session_id? string The currently active session ID, tracked for session-scoped endpoints.
---@field version? string
---@field tui boolean Whether the server exposes the legacy `/tui/*` control endpoints (OpenCode >= dev, not v2.0.x).
---@field subscription_job_id? number
---@field heartbeat_timer? uv.uv_timer_t
local Server = {}
Server.__index = Server

---Built-in OpenCode commands exposed by `command()`.
---Aliases retained from v1; mapped onto v2 API calls where possible and the
---legacy `/tui/*` control endpoints when the server exposes them.
---@alias opencode.server.Command
---| 'agent.cycle'
---| 'prompt.clear'
---| 'prompt.submit'
---| 'session.compact'
---| 'session.first'
---| 'session.half.page.up'
---| 'session.half.page.down'
---| 'session.interrupt'
---| 'session.last'
---| 'session.new'
---| 'session.page.up'
---| 'session.page.down'
---| 'session.share'
---| 'session.redo'
---| 'session.undo'

---@class opencode.server.Session
---@field id string
---@field title string
---@field time { created: integer, updated: integer }

---@class opencode.server.Agent
---@field name string
---@field description string
---@field mode "primary" | "subagent"

---@class opencode.server.PermissionRequest
---@field id string
---@field sessionID string
---@field action string
---@field resources string[]
---@field save? string[]
---@field metadata? table
---@field source? { type: "tool", messageID: string, id: string }
---@field message? string

---@alias opencode.server.PermissionReply
---| "once"
---| "always"
---| "reject"

---Events emitted by OpenCode v2.
---Note the v2 shape: `{ id, type, data }` (v1 used `{ type, properties }`).
---Not exhaustive.
---@alias opencode.server.Event
---| { id: string, type: "filesystem.changed", data: { file: string, event: "add" | "change" | "unlink" } }
---| { id: string, type: "permission.asked", data: opencode.server.PermissionRequest }
---| { id: string, type: "permission.replied", data: { sessionID: string, requestID: string, reply: opencode.server.PermissionReply } }
---| { id: string, type: "server.connected", data: {} }
---| { id: string, type: "global.disposed", data: table }
---| { id: string, type: "location.shutdown", data: table }
---| { id: string, type: "session.status", data: { sessionID: string, status: { type: "idle" | "busy" | "retry" } } }
---| { id: string, type: "session.created", data: table }
---| { id: string, type: string, data: table }

---Credentials for discovered servers, keyed by normalized URL.
---OpenCode v2 always requires basic auth, and event listeners reconstruct server
---objects from a bare URL, so cache the discovered credentials for reuse —
---keyed so one service's password is never sent to another host.
---@type table<string, opencode.server.Credentials>
Server.credentials = {}

---Panel session targets, keyed by server URL so a target is never reused against
---a different service. `seen` flips once the TUI's `tabs.json` catches up.
---@type table<string, { id: string, seen: boolean }>
Server.panel_targets = {}

---Attempt to connect to an OpenCode server and fetch its health and details.
---Rejects if the health fails — the last line of defense against false-positive server discovery.
---Rejection message is non-empty if from a valid OpenCode server.
---
---@param url string
---@param credentials? opencode.server.Credentials
---@return Promise<opencode.server.Server>
function Server.new(url, credentials)
  local self = setmetatable({}, Server)
  url = url:gsub("/$", "")
  if credentials then
    Server.credentials[url] = credentials
  end
  local config = require("opencode.config").opts.server or {}
  local creds = credentials or Server.credentials[url] or {}
  self.url = url
  self.username = creds.username or config.username or "opencode"
  self.password = creds.password or config.password
  self.heartbeat_timer = vim.uv.new_timer()

  local Promise = require("opencode.promise")
  -- Serially check health first to confirm that this is a valid and authenticated OpenCode server.
  return self
    :get_info()
    :next(function(info)
      self.version = info.version
      return Promise.all({
        self:get_location(),
        self:get_sessions(),
        self:get_agents(),
      })
    end)
    :next(
      function(results) ---@param results { [1]: { directory: string }, [2]: opencode.server.Session[], [3]: opencode.server.Agent[] }
        self.cwd = vim.fn.getcwd() or results[1].directory
        self.title = results[2][1] and results[2][1].title or "<No sessions>"
        self.subagents = vim.tbl_filter(function(agent) ---@param agent opencode.server.Agent
          return agent.mode == "subagent"
        end, results[3])

        return self:probe_tui():next(function()
          return Promise.resolve(self)
        end)
      end
    )
end

---Detect whether the server exposes the legacy `/tui/*` control endpoints.
---These were removed in OpenCode v2.0.x and re-added later; when absent, all
---TUI-driving commands degrade gracefully to no-ops.
---
---Checked via the published OpenAPI spec: OpenCode v2.0.x exposes only the
---`/api/*` surface there, while newer builds that restore the TUI routes include
---`/tui/*` as well.
---
---@return Promise<boolean>
function Server:probe_tui()
  local Promise = require("opencode.promise")
  return self
    :request("/openapi.json", "GET")
    :next(function(spec)
      self.tui = spec ~= nil and spec.paths ~= nil and spec.paths["/tui/execute-command"] ~= nil
      return Promise.resolve(self.tui)
    end)
    :catch(function()
      self.tui = false
      return Promise.resolve(false)
    end)
end

---Human-readable name, stripping the protocol prefix.
---
---@return string
function Server:display_name()
  local name = self.url:gsub("^%w+://", "")
  return name
end

---Build the `Authorization` header value, if credentials are configured.
---
---@return string? authorization
function Server:authorization()
  if not self.password or self.password == "" then
    return nil
  end
  local credentials = self.username .. ":" .. self.password
  local token
  if vim.base64 and vim.base64.encode then
    token = vim.base64.encode(credentials)
  else
    token = vim.trim(vim.fn.system({ "base64" }, credentials):gsub("%s+", ""))
  end
  return "Basic " .. token
end

---@param path string
---@param method "GET" | "POST" | "PATCH" | "DELETE"
---@param body table?
---@param on_success fun(response: table?)
---@param on_error fun(msg: string, code: number, status: number?)
---@param opts? { persistent?: boolean, max_time?: number }
---@return number job_id
function Server:curl(path, method, body, on_success, on_error, opts)
  local url = self.url .. path
  opts = opts or {}

  local cmd = {
    "curl",
    "-s", -- Silent
    "-S", -- Except for errors/stderr
    "--fail-with-body",
    "-X",
    method,
    "-H",
    "Content-Type: application/json",
    "-H",
    "Accept: application/json",
    "-H",
    "Accept: text/event-stream",
    "-N",
  }

  local authorization = self:authorization()
  if authorization then
    -- We can always send credentials; servers with no auth set just ignore them
    table.insert(cmd, "-H")
    table.insert(cmd, "Authorization: " .. authorization)
  end

  -- OpenCode v2 routes instance requests to a project by directory. Without it, a
  -- shared service answers for its own ambient cwd (PR #330 review).
  local directory = vim.fn.getcwd() or self.cwd
  if directory and directory ~= "" then
    table.insert(cmd, "-H")
    table.insert(cmd, "x-opencode-directory: " .. vim.uri_encode(directory))
  end

  if not opts.persistent then
    table.insert(cmd, "--max-time")
    table.insert(cmd, opts.max_time or 2)
  end

  if body then
    -- `vim.fn.json_encode({})` encodes an empty table as `[]`, but the OpenCode
    -- API expects `{}` for empty object bodies (e.g. session create).
    local encoded = next(body) == nil and "{}" or vim.fn.json_encode(body)
    table.insert(cmd, "-d")
    table.insert(cmd, encoded)
  end

  table.insert(cmd, url)

  local response_buffer = {}
  local function process_response_buffer()
    if #response_buffer > 0 then
      local full_event = table.concat(response_buffer)
      response_buffer = {}
      vim.schedule(function()
        local ok, result = pcall(vim.fn.json_decode, full_event)
        if ok then
          if on_success then
            on_success(result)
          end
        else
          local error_message = "Failed to decode response from "
            .. url
            .. "\nResponse: "
            .. full_event
            .. "\nError: "
            .. result
          on_error(error_message, -1)
        end
      end)
    end
  end

  local stderr_lines = {}
  return vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line == "" then
          -- Blank line: SSE event terminator when persistent, otherwise a
          -- line-split artifact (e.g. an empty 204 body) to ignore.
          if opts.persistent then
            process_response_buffer()
          end
        elseif not line:match("^:") then
          local clean_line = (line:gsub("^data: ?", ""))
          table.insert(response_buffer, clean_line)
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_lines, line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        if #response_buffer > 0 then
          process_response_buffer()
        elseif on_success then
          -- Empty success body (e.g. 204 No Content from DELETE): resolve anyway.
          vim.schedule(function()
            on_success(nil)
          end)
        end
      else
        local response_message = #response_buffer > 0 and table.concat(response_buffer, "\n") or nil
        local stderr_message = #stderr_lines > 0 and table.concat(stderr_lines, "") or nil
        local status

        local detail_lines = { "Request to " .. url .. " failed with exit code: " .. code }
        if response_message and response_message ~= "" then
          table.insert(detail_lines, "Response:\n" .. response_message)
        end
        if stderr_message and stderr_message ~= "" then
          table.insert(detail_lines, "Stderr:\n" .. stderr_message)
          -- Afaict `curl` requires manual parsing of the response code one way or another regardless of flags :/
          status = stderr_message:match("The requested URL returned error: (%d+)$")
          status = tonumber(status)
        end

        local error_message = table.concat(detail_lines, "\n")
        on_error(error_message, code, status)
      end
    end,
  })
end

---Wrap a single JSON request in a Promise.
---
---@param path string
---@param method "GET" | "POST" | "PATCH" | "DELETE"
---@param body table?
---@return Promise<any>
function Server:request(path, method, body)
  return require("opencode.promise").new(function(resolve, reject)
    self:curl(path, method, body, resolve, function(msg, code, status)
      if status == 401 then
        reject("Unauthorized response from OpenCode at " .. self:display_name())
      else
        reject(msg)
      end
    end)
  end)
end

---@return Promise<{ version: string, pid: number, urls: string[], paths: table }>
function Server:get_info()
  return self:request("/api/info", "GET")
end

---@return Promise<{ directory: string, project: table }>
function Server:get_location()
  return self:request("/api/location", "GET")
end

---@return Promise<opencode.server.Session[]>
function Server:get_sessions()
  local Promise = require("opencode.promise")
  return self:request("/api/session", "GET"):next(function(response)
    return Promise.resolve(response.data or {})
  end)
end

---@return Promise<opencode.server.Agent[]>
function Server:get_agents()
  local Promise = require("opencode.promise")
  return self:request("/api/agent", "GET"):next(function(response)
    return Promise.resolve(response.data or {})
  end)
end

---The ID of the currently active session, if any.
---
---@return Promise<string?>
function Server:get_active_session()
  local Promise = require("opencode.promise")
  return self:request("/api/session/active", "GET"):next(function(response)
    local active = response.data or {}
    local id = next(active)
    self.session_id = id
    return Promise.resolve(id)
  end)
end

---Update and return the session the TUI is currently viewing, if discoverable.
---The TUI records its open tabs (per directory) in OpenCode's state directory.
---
---@return string?
function Server:tui_current_session()
  local state_home = vim.env.XDG_STATE_HOME
  local dir = state_home and state_home ~= "" and vim.fs.joinpath(state_home, "opencode")
    or vim.fs.joinpath(vim.env.HOME or "", ".local", "state", "opencode")
  local path = vim.fs.joinpath(dir, "latest", "tui", "tabs.json")
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    return nil
  end
  local decoded_ok, decoded = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if not decoded_ok or type(decoded) ~= "table" or type(decoded.cwd) ~= "table" then
    return nil
  end
  for _, directory in ipairs({ self.cwd, vim.fn.getcwd() }) do
    local entry = directory and decoded.cwd[directory]
    local tabs = entry and entry.tabs
    local last = tabs and tabs[#tabs]
    if last and last.sessionID then
      return last.sessionID
    end
  end
  return nil
end

---Resolve the session to act on.
---Prefers the plugin's explicit panel session until the TUI catches up, then
---the session the TUI is currently viewing, then the most recently viewed
---(else updated) session.
---
---@return Promise<string>
function Server:resolve_session_id()
  local Promise = require("opencode.promise")
  if self.session_id then
    return Promise.resolve(self.session_id)
  end

  local target = Server.panel_targets[self.url]
  local from_tui = self:tui_current_session()
  if target and from_tui and from_tui == target.id then
    -- The TUI now shows the panel session; trust it from here on.
    target.seen = true
  end

  if target and not target.seen then
    return Promise.resolve(target.id)
  end

  if from_tui then
    return Promise.resolve(from_tui)
  end

  if target then
    return Promise.resolve(target.id)
  end

  return self:get_sessions():next(function(sessions)
    if #sessions == 0 then
      return Promise.reject("No OpenCode sessions found")
    end
    table.sort(sessions, function(a, b)
      local av = (a.time and (a.time.viewed or a.time.updated)) or 0
      local bv = (b.time and (b.time.viewed or b.time.updated)) or 0
      return av > bv
    end)
    return Promise.resolve(sessions[1].id)
  end)
end

---@param session_id string
---@param text string
---@return Promise<any>
function Server:send_prompt(session_id, text)
  return self:request("/api/session/" .. session_id .. "/prompt", "POST", { text = text })
end

---@param session_id string
---@param name string
---@param text string
---@return Promise<any>
function Server:run_command(session_id, name, text)
  return self:request("/api/session/" .. session_id .. "/command", "POST", { name = name, text = text })
end

---@param session_id string
---@return Promise<any>
function Server:interrupt(session_id)
  return self:request("/api/session/" .. session_id .. "/interrupt", "POST")
end

---@param session_id string
---@return Promise<any>
function Server:compact(session_id)
  return self:request("/api/session/" .. session_id .. "/compact", "POST", {})
end

---@param session_id string
---@param agent string
---@return Promise<any>
function Server:switch_agent(session_id, agent)
  return self:request("/api/session/" .. session_id .. "/agent", "POST", { agent = agent })
end

---@return Promise<opencode.server.Session>
function Server:create_session()
  return self:request("/api/session", "POST", {})
end

---@param session_id string
---@return Promise<any>
function Server:revert_commit(session_id)
  return self:request("/api/session/" .. session_id .. "/revert/commit", "POST")
end

---@param session_id string
---@return Promise<any>
function Server:revert_clear(session_id)
  return self:request("/api/session/" .. session_id .. "/revert", "DELETE")
end

---@param session_id string
---@param request_id string
---@param reply opencode.server.PermissionReply
---@return Promise<any>
function Server:permit(session_id, request_id, reply)
  return self:request("/api/session/" .. session_id .. "/permission/" .. request_id .. "/reply", "POST", {
    decision = reply,
  })
end

---Legacy TUI control: execute a built-in command (scroll, navigation, …).
---Only available when the server exposes `/tui/*` endpoints.
---
---@param command string
---@return Promise<any>
function Server:tui_execute_command(command)
  return self:request("/tui/execute-command", "POST", { command = command })
end

---Legacy TUI control: append text to the TUI's prompt input.
---Only available when the server exposes `/tui/*` endpoints.
---
---@param text string
---@return Promise<any>
function Server:tui_append_prompt(text)
  return self:request("/tui/append-prompt", "POST", { text = text })
end

---@param on_success fun(response: opencode.server.Event) Invoked with each received event.
---@param on_error fun(msg: string?, code: number)
---@return number job_id
function Server:sse_subscribe(on_success, on_error)
  return self:curl("/api/event", "GET", nil, on_success, on_error, { persistent = true })
end

---How often OpenCode sends heartbeat events.
local OPENCODE_HEARTBEAT_INTERVAL_MS = 10000

---The currently connected server.
---Cleared when the server disposes itself, the connection errors, or the heartbeat disappears.
---@type opencode.server.Server?
Server.connected = nil

---Subscribe to this server's SSE stream and dispatch autocmds for received events.
---Disconnects currently connected server first.
---Idempotent.
---
---@return Promise<opencode.server.Server> server Promise that resolves or rejects according to initial connection success.
function Server:connect()
  local Promise = require("opencode.promise")

  if Server.connected == self then
    return Promise.resolve(self)
  elseif Server.connected then
    Server.connected:disconnect()
  end

  return Promise.new(function(resolve, reject)
    self.subscription_job_id = self:sse_subscribe(
      function(response)
        if self.heartbeat_timer then
          self.heartbeat_timer:start(
            OPENCODE_HEARTBEAT_INTERVAL_MS + 1000,
            0,
            vim.schedule_wrap(function()
              self:disconnect()
            end)
          )
        end

        if response.type == "server.connected" then
          Server.connected = self
          resolve(self)
        elseif response.type == "global.disposed" or response.type == "location.shutdown" then
          self:disconnect()
        end

        require("opencode.events").emit(response, self)
      end,
      -- Server disappeared ungracefully, e.g. process killed, network error, etc.
      -- Also called on manual disconnects, like our `vim.fn.jobstop`.
      function(msg)
        local was_connected = Server.connected == self
        self:disconnect()
        if not was_connected then
          reject(msg)
        end
      end
    )
  end)
end

---Unsubscribe from this server's SSE stream and stop the heartbeat timer.
---Idempotent.
function Server:disconnect()
  if self.subscription_job_id then
    vim.fn.jobstop(self.subscription_job_id)
    self.subscription_job_id = nil
  end
  if self.heartbeat_timer then
    self.heartbeat_timer:stop()
  end

  if Server.connected == self then
    Server.connected = nil
    require("opencode.events.status").reset()
  end
end

return Server
