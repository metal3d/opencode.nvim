local M = {}

---@class opencode.server.discovery.Registration
---@field url string
---@field password? string
---@field pid? number
---@field version? string

---Resolve OpenCode's state directory, honoring `$XDG_STATE_HOME`.
---
---@return string
local function state_dir()
  local state_home = vim.env.XDG_STATE_HOME
  if state_home and state_home ~= "" then
    return vim.fs.joinpath(state_home, "opencode")
  end
  return vim.fs.joinpath(vim.env.HOME or "", ".local", "state", "opencode")
end

---Read the registered OpenCode server (URL + password) that OpenCode writes when
---its background service starts (`opencode service start`, or `opencode serve --register`).
---
---The registration file was named `server.json` historically and is `service.json`
---in v2.0.x; check both for forward compatibility.
---
---@return opencode.server.discovery.Registration?
local function registered()
  local dir = state_dir()
  for _, name in ipairs({ "service.json", "server.json" }) do
    local path = vim.fs.joinpath(dir, name)
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok and lines and #lines > 0 then
      local decoded_ok, decoded = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
      if decoded_ok and type(decoded) == "table" and type(decoded.url) == "string" then
        return {
          url = decoded.url,
          password = decoded.password,
          pid = decoded.pid,
          version = decoded.version,
        }
      end
    end
  end
  return nil
end

local function find()
  local Promise = require("opencode.promise")
  local connected_server = require("opencode.server").connected

  return connected_server and Promise.resolve(connected_server)
    or M.configured()
    or M.registered()
    or Promise.reject("No OpenCode server found")
end

---Look for an OpenCode server every second, rejecting if not found after five seconds.
---
---@return Promise<opencode.server.Server>
local function poll()
  local Promise = require("opencode.promise")
  local poll_timer, timer_err, timer_errname = vim.uv.new_timer()
  if not poll_timer then
    return Promise.reject("Failed to create timer to poll for OpenCode: " .. timer_errname .. ": " .. timer_err)
  end

  local retries = 0
  return Promise.new(function(resolve, reject)
    poll_timer:start(
      1000,
      1000,
      vim.schedule_wrap(function()
        find()
          :next(function(server)
            resolve(server)
          end)
          :catch(function(err)
            retries = retries + 1
            if retries >= 5 then
              reject(err)
            else
              -- Wait for next retry
            end
          end)
      end)
    )
  end):finally(function()
    poll_timer:stop()
    poll_timer:close()
  end)
end

---Find and connect to an OpenCode server. Tries, in order:
---
---1. The currently connected server.
---2. The configured URL in `require("opencode.config").opts.server.url`.
---3. The background service registered in OpenCode's state directory.
---4. Calling `vim.g.opencode_opts.server.start` and retrying the above over five seconds.
---
---@return Promise<opencode.server.Server>
function M.get()
  local Promise = require("opencode.promise")

  return find()
    :catch(function(err)
      if not err then
        -- Do nothing when server selection was cancelled
        return Promise.reject()
      end

      local start = require("opencode.config").opts.server.start

      if not start then
        -- Propagate original error
        return Promise.reject(err)
      end

      local start_ok, start_result = pcall(start)
      if not start_ok then
        return Promise.reject("Failed to start OpenCode: " .. start_result)
      end

      return poll()
    end)
    :next(function(server)
      if require("opencode.config").opts.server.connect then
        return server:connect()
      else
        return Promise.resolve(server)
      end
    end)
end

---The registered OpenCode background service (URL + password), if any.
---Useful for callers that need the raw registration before a full server connection.
---
---@return opencode.server.discovery.Registration?
function M.registration()
  return registered()
end

---Attempt to connect to the OpenCode background service registered on this machine.
---
---@return Promise<opencode.server.Server>?
function M.registered()
  local Promise = require("opencode.promise")
  local info = registered()
  if info == nil then
    return nil
  end

  return require("opencode.server").new(info.url, { password = info.password }):catch(function(err)
    return Promise.reject(err or ("Failed to connect to registered OpenCode server at " .. info.url))
  end)
end

---Attempt to connect to the OpenCode server at `vim.g.opencode_opts.server.url`.
---
---@return Promise<opencode.server.Server>?
function M.configured()
  local url = require("opencode.config").opts.server and require("opencode.config").opts.server.url
  if url == nil then
    return nil
  end

  return type(url) == "string"
      and require("opencode.server").new(url):catch(function()
        return require("opencode.promise").reject("Failed to connect to configured OpenCode server URL: " .. url)
      end)
    or type(url) == "function"
      and require("opencode.promise")
        .new(function(resolve, reject)
          url(function(resolved_url) ---@param resolved_url string?
            if resolved_url then
              resolve(resolved_url)
            else
              reject("Configured OpenCode server URL resolved to `nil`")
            end
          end)
        end)
        :next(function(resolved_url)
          return require("opencode.server").new(resolved_url)
        end)
end

return M
