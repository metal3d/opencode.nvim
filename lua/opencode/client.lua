--- Async HTTP client for the OpenCode v2 API.
---
--- Requests are made with `curl` through Neovim's `vim.system`, which keeps the
--- plugin free of external Lua dependencies. Every request carries HTTP basic
--- auth using the credentials stored on the connected server.
local M = {}

---@type { url: string, username?: string, password: string }?
M.server = nil

--- Timeouts (in seconds) for non-streaming requests. They keep a dead or
--- unreachable server from leaving a caller waiting forever (which, before
--- connection state was fixed, could lock out every later attempt).
M.connect_timeout = 5
M.max_time = 60

---@param srv table? # nil clears the connected server.
function M.set_server(srv)
  M.server = srv
end

---@return boolean
function M.connected()
  return M.server ~= nil
end

--- Build the basic-auth curl arguments for a server.
local function auth_args(server)
  local user = server.username or "opencode"
  return { "-u", user .. ":" .. server.password }
end

--- Perform a request and give `cb` the raw body (or an error).
---@param method string HTTP method.
---@param path string API path beginning with `/`.
---@param opts? { body?: string, headers?: string[], extra?: string[], server?: { url: string, username?: string, password: string } }
---@param cb fun(result: { body?: string, err?: string, status?: integer })
function M.request(method, path, opts, cb)
  opts = opts or {}
  -- `opts.server` lets callers probe a candidate server without committing it
  -- to the shared client (used during connection validation).
  local server = opts.server or M.server
  if not server then
    cb({ err = "No OpenCode server connected" })
    return
  end

  local args = {
    "curl",
    "-sS",
    "--fail-with-body",
    "--connect-timeout",
    tostring(M.connect_timeout),
    "--max-time",
    tostring(M.max_time),
    "-w",
    "\n%{http_code}",
    "-X",
    method,
  }
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
      local out = obj.stdout or ""
      -- curl `-w "\n%{http_code}"` appends the HTTP status as the last line.
      local status = tonumber(out:match("\n(%d%d%d)%s*$"))
      local body = out:gsub("\n%d%d%d%s*$", "")
      if obj.code ~= 0 then
        local detail = vim.trim(obj.stderr or "")
        if detail == "" then
          detail = vim.trim(body)
        end
        cb({
          err = "opencode request failed (" .. tostring(obj.code) .. "): " .. detail,
          body = body,
          status = status,
        })
        return
      end
      cb({ body = body, status = status })
    end)
  end)
end

--- Perform a JSON request and give `cb` the decoded response.
---@param method string
---@param path string
---@param body? table Request payload; encoded as JSON when provided.
---@param cb fun(result: { data?: any, body?: string, err?: string, status?: integer })
---@param server? { url: string, username?: string, password: string } Optional
---  server to target instead of the shared client (connection validation).
function M.api(method, path, body, cb, server)
  M.request(method, path, {
    body = body ~= nil and vim.json.encode(body) or nil,
    server = server,
  }, function(res)
    if res.err then
      cb({ err = res.err, body = res.body, status = res.status })
      return
    end
    local ok, data = pcall(vim.json.decode, res.body or "null", { luanil = { object = true } })
    if not ok then
      cb({ err = "invalid JSON from API", body = res.body, status = res.status })
      return
    end
    cb({ data = data, body = res.body, status = res.status })
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
    -- `vim.system` invokes the stdout callback as `(err, data)`; the final call
    -- is `(nil, nil)` at end of stream.
    stdout = function(_, data)
      if data and opts.on_data then
        opts.on_data(data)
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
