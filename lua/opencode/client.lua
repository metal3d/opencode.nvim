--- Async HTTP client for the OpenCode v2 API.
---
--- Requests are made with `curl` through Neovim's `vim.system`, which keeps the
--- plugin free of external Lua dependencies. Every request carries HTTP basic
--- auth using the credentials stored on the connected server.
local M = {}

---@type { url: string, username?: string, password: string }?
M.server = nil

---Whether the server exposes the legacy `/tui/*` control endpoints.
---@type boolean
M.tui = false

---@param srv table
function M.set_server(srv)
  M.server = srv
end

---@return boolean
function M.connected()
  return M.server ~= nil
end

--- Detect the legacy `/tui/*` endpoints from the server's OpenAPI document.
--- These let the plugin drive the running TUI (append to its prompt, select a
--- session) so prompts land in the tab the user is looking at.
---@param cb fun(tui: boolean)
function M.detect_tui(cb)
  M.request("GET", "/openapi.json", nil, function(res)
    if res.err then
      M.tui = false
      cb(false)
      return
    end
    local ok, spec = pcall(vim.json.decode, res.body or "")
    local has = ok and type(spec) == "table" and type(spec.paths) == "table" and spec.paths["/tui/execute-command"] ~= nil
    M.tui = has and true or false
    cb(M.tui)
  end)
end

--- Build the basic-auth curl arguments for a server.
local function auth_args(server)
  local user = server.username or "opencode"
  return { "-u", user .. ":" .. server.password }
end

--- Perform a request and give `cb` the raw body (or an error).
---@param method string HTTP method.
---@param path string API path beginning with `/`.
---@param opts? { body?: string, headers?: string[], extra?: string[] }
---@param cb fun(result: { body?: string, err?: string })
function M.request(method, path, opts, cb)
  opts = opts or {}
  local server = M.server
  if not server then
    cb({ err = "No OpenCode server connected" })
    return
  end

  local args = { "curl", "-sS", "--fail-with-body", "-X", method }
  local a = auth_args(server)
  args[#args + 1] = a[1]
  args[#args + 1] = a[2]

  if opts.body ~= nil then
    args[#args + 1] = "-H"
    args[#args + 1] = "Content-Type: application/json"
    args[#args + 1] = "--data-raw"
    args[#args + 1] = opts.body
  end
  for _, header in ipairs(opts.headers or {}) do
    args[#args + 1] = "-H"
    args[#args + 1] = header
  end
  for _, extra in ipairs(opts.extra or {}) do
    args[#args + 1] = extra
  end
  args[#args + 1] = server.url .. path

  vim.system(args, { text = true }, function(obj)
    -- `vim.system` callbacks run in a fast-event context where most `vim.fn`
    -- and buffer/window APIs are forbidden. Defer the result so callers can use
    -- the normal Neovim API freely.
    vim.schedule(function()
      if obj.code ~= 0 then
        local detail = vim.trim(obj.stderr or "")
        if detail == "" then
          detail = vim.trim(obj.stdout or "")
        end
        cb({ err = "opencode request failed (" .. tostring(obj.code) .. "): " .. detail })
        return
      end
      cb({ body = obj.stdout or "" })
    end)
  end)
end

--- Perform a JSON request and give `cb` the decoded response.
---@param method string
---@param path string
---@param body? table Request payload; encoded as JSON when provided.
---@param cb fun(result: { data?: any, body?: string, err?: string })
function M.api(method, path, body, cb)
  M.request(method, path, { body = body ~= nil and vim.json.encode(body) or nil }, function(res)
    if res.err then
      cb({ err = res.err })
      return
    end
    local ok, data = pcall(vim.json.decode, res.body or "null")
    if not ok then
      cb({ err = "invalid JSON from API" })
      return
    end
    cb({ data = data, body = res.body })
  end)
end

--- Open a streaming request (used for the Server-Sent-Events feed).
---@param path string
---@param opts { headers?: string[], on_data: fun(chunk: string), on_done?: fun(ok: boolean) }
---@return vim.SystemObj?
function M.stream(path, opts)
  local server = M.server
  if not server then
    if opts.on_done then
      opts.on_done(false)
    end
    return nil
  end

  local args = { "curl", "-sS", "-N" }
  local a = auth_args(server)
  args[#args + 1] = a[1]
  args[#args + 1] = a[2]
  for _, header in ipairs(opts.headers or {}) do
    args[#args + 1] = "-H"
    args[#args + 1] = header
  end
  args[#args + 1] = server.url .. path

  return vim.system(args, {
    text = true,
    stdout = function(chunk)
      -- The streaming callback may be invoked with nil at end of stream.
      if chunk and opts.on_data then
        opts.on_data(chunk)
      end
    end,
  }, function(obj)
    vim.schedule(function()
      if opts.on_done then
        opts.on_done(obj.code == 0)
      end
    end)
  end)
end

return M