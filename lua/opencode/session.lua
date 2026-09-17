--- Session targeting and messaging against the OpenCode v2 API.
---
--- The target session is owned by this Neovim instance and chosen explicitly
--- (or once, as the most recently viewed session in the current directory), then
--- kept for the life of the connection. It is never inferred from OpenCode's
--- global TUI state: that state is shared by every client attached to the
--- service and would route prompts to another folder's session.
local client = require("opencode.client")

local M = {}

-- The session the plugin currently operates on.
M.target = nil

---@param id string?
function M.set_target(id)
  M.target = id
end

---@return string?
function M.get_target()
  return M.target
end

--- Recency of a session, preferring when it was last viewed (like the base).
---@param s table
---@return number
local function recency(s)
  local t = s.time or {}
  return t.viewed or t.updated or 0
end

--- Extract an entity id from an API response regardless of wrapping.
local function id_of(data)
  if type(data) ~= "table" then
    return nil
  end
  if type(data.id) == "string" then
    return data.id
  end
  if type(data.data) == "table" and type(data.data.id) == "string" then
    return data.data.id
  end
  return nil
end

--- List all sessions.
---@param cb fun(result: { data?: table[], err?: string })
function M.list(cb)
  client.api("GET", "/api/session", nil, function(res)
    if res.err then
      cb({ err = res.err })
      return
    end
    cb({ data = (res.data and res.data.data) or {} })
  end)
end

--- Create a session in a directory.
---@param directory string
---@param cb fun(result: { err?: string })
function M.create(directory, cb)
  client.api("POST", "/api/session", { location = { directory = directory } }, function(res)
    if res.err then
      cb({ err = res.err })
      return
    end
    local id = id_of(res.data)
    if not id then
      cb({ err = "create session response missing id" })
      return
    end
    M.target = id
    cb({})
  end)
end

--- Reuse the most recent session for `directory`, or create one.
---@param directory string
---@param cb fun(result: { session?: string, err?: string })
function M.ensure(directory, cb)
  if M.target then
    cb({ session = M.target })
    return
  end

  local function create()
    M.create(directory, function(res)
      if res.err then
        cb({ err = res.err })
      else
        cb({ session = M.target })
      end
    end)
  end

  if require("opencode.config").get().session.mode == "new" then
    create()
    return
  end
  M.list(function(list)
    if list.err then
      cb({ err = list.err })
      return
    end
    local matches = {}
    for _, s in ipairs(list.data or {}) do
      if s and (s.location or {}).directory == directory then
        matches[#matches + 1] = s
      end
    end
    if #matches > 0 then
      table.sort(matches, function(a, b)
        return recency(a) > recency(b)
      end)
      M.target = matches[1].id
      cb({ session = M.target })
      return
    end
    create()
  end)
end

--- Fetch the metadata of the target session.
---@param cb fun(result: { data?: table, err?: string })
function M.get(cb)
  if not M.target then
    cb({ data = {} })
    return
  end
  client.api("GET", "/api/session/" .. M.target, nil, function(res)
    if res.err then
      cb({ err = res.err })
      return
    end
    cb({ data = res.data or {} })
  end)
end

--- Fetch the messages of the target session.
---@param cb fun(result: { data?: table[], err?: string })
function M.messages(cb)
  if not M.target then
    cb({ data = {} })
    return
  end
  client.api("GET", "/api/session/" .. M.target .. "/message", nil, function(res)
    if res.err then
      cb({ err = res.err })
      return
    end
    cb({ data = (res.data and res.data.data) or {} })
  end)
end

--- Send a prompt to the target session.
---@param text string
---@param opts? { files?: table[], agents?: string[] }
---@param cb? fun(result: { err?: string })
function M.prompt(text, opts, cb)
  opts = opts or {}
  cb = cb or function() end
  if not M.target then
    cb({ err = "no active session" })
    return
  end
  local body = { text = text }
  if opts.files and #opts.files > 0 then
    body.files = opts.files
  end
  if opts.agents and #opts.agents > 0 then
    body.agents = opts.agents
  end
  client.api("POST", "/api/session/" .. M.target .. "/prompt", body, function(res)
    if res.err then
      cb({ err = res.err })
      return
    end
    cb({})
  end)
end

--- Interrupt the target session.
---@param cb? fun(result: { err?: string })
function M.interrupt(cb)
  cb = cb or function() end
  if not M.target then
    cb({ err = "no active session" })
    return
  end
  client.api("POST", "/api/session/" .. M.target .. "/interrupt", nil, function(res)
    cb(res.err and { err = res.err } or {})
  end)
end

--- Compact the target session.
---@param cb? fun(result: { err?: string })
function M.compact(cb)
  cb = cb or function() end
  if not M.target then
    cb({ err = "no active session" })
    return
  end
  client.api("POST", "/api/session/" .. M.target .. "/compact", {}, function(res)
    cb(res.err and { err = res.err } or {})
  end)
end

--- Run a command in the target session.
---@param name string
---@param text string
---@param cb? fun(result: { err?: string })
function M.command(name, text, cb)
  cb = cb or function() end
  if not M.target then
    cb({ err = "no active session" })
    return
  end
  client.api("POST", "/api/session/" .. M.target .. "/command", { name = name, text = text }, function(res)
    if res.err then
      cb({ err = res.err })
      return
    end
    cb({})
  end)
end

return M