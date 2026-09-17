--- Session targeting and messaging against the OpenCode v2 API.
---
--- The target session is owned by this Neovim instance. It is either chosen
--- explicitly by the user (and then kept), or resolved once as the most recent
--- session for the current directory and re-resolved whenever that directory
--- changes. It is never inferred from OpenCode's global TUI state: that state is
--- shared by every client attached to the service and would route prompts to
--- another folder's session.
local client = require("opencode.client")

local M = {}

-- The session the plugin currently operates on.
M.target = nil
-- The directory the target belongs to (used to detect `:cd`).
M.directory = nil
-- Whether the target was chosen by the user (kept across directory changes).
M.explicit = false

---@param id string?
---@param directory? string Directory the session belongs to (defaults to cwd).
function M.set_target(id, directory)
  M.target = id
  M.directory = id and (directory or vim.fn.getcwd()) or nil
  M.explicit = id ~= nil
end

--- Adopt an automatically-resolved target (cleared when the directory changes).
---@param id string?
---@param directory string?
local function adopt(id, directory)
  M.target = id
  M.directory = id and directory or nil
  M.explicit = false
end

---@return string?
function M.get_target()
  return M.target
end

--- Whether the current target can be used for `directory` without re-resolving.
---@param directory string
---@return boolean
function M.matches(directory)
  return M.target ~= nil and (M.explicit or M.directory == directory)
end

--- Clear the target when the server says the session no longer exists.
---@param res { status?: integer }
local function invalidate_if_missing(res)
  if res and res.status == 404 then
    adopt(nil, nil)
  end
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

--- List sessions. `opts` narrows the query server-side.
---
--- The API only returns the newest 50 sessions by default, so `directory`
--- filtering (used by `ensure`) is essential to avoid missing an older session
--- for the current project.
---@param cb fun(result: { data?: table[], cursor?: table, err?: string })
---@param opts? { directory?: string, limit?: integer, cursor?: string, order?: string }
function M.list(cb, opts)
  opts = opts or {}
  local query = {}
  if opts.limit then
    query[#query + 1] = "limit=" .. tostring(opts.limit)
  end
  if opts.order then
    query[#query + 1] = "order=" .. vim.uri_encode(opts.order)
  end
  if opts.cursor then
    query[#query + 1] = "cursor=" .. vim.uri_encode(opts.cursor)
  end
  if opts.directory then
    query[#query + 1] = "directory=" .. vim.uri_encode(opts.directory)
  end
  local path = "/api/session"
  if #query > 0 then
    path = path .. "?" .. table.concat(query, "&")
  end
  client.api("GET", path, nil, function(res)
    if res.err then
      cb({ err = res.err })
      return
    end
    cb({
      data = (res.data and res.data.data) or {},
      cursor = (res.data and res.data.cursor) or nil,
    })
  end)
end

--- List every session by following the API cursor.
---
--- Used by the session picker, which must not be limited to the first page.
---@param cb fun(result: { data?: table[], err?: string })
---@param cap? integer Safety bound on the number of sessions collected.
function M.list_all(cb, cap)
  cap = cap or 1000
  local all = {}
  local function page(cursor)
    M.list(function(res)
      if res.err then
        cb({ err = res.err })
        return
      end
      for _, s in ipairs(res.data or {}) do
        all[#all + 1] = s
      end
      local next_cursor = res.cursor and res.cursor.next
      if next_cursor and #all < cap then
        page(next_cursor)
      else
        cb({ data = all })
      end
    end, { limit = 50, cursor = cursor })
  end
  page(nil)
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
    adopt(id, directory)
    cb({})
  end)
end

--- Reuse the most recent session for `directory`, or create one.
---@param directory string
---@param cb fun(result: { session?: string, err?: string })
function M.ensure(directory, cb)
  if M.target then
    if M.explicit or M.directory == directory then
      cb({ session = M.target })
      return
    end
    -- An automatically-resolved target belongs to another directory (the user
    -- changed project): forget it and resolve for the new directory.
    adopt(nil, nil)
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
      adopt(matches[1].id, directory)
      cb({ session = M.target })
      return
    end
    create()
  end, { directory = directory, limit = 50 })
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
      invalidate_if_missing(res)
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
      invalidate_if_missing(res)
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
      invalidate_if_missing(res)
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
    if res.err then
      invalidate_if_missing(res)
      cb({ err = res.err })
      return
    end
    cb({})
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
    if res.err then
      invalidate_if_missing(res)
      cb({ err = res.err })
      return
    end
    cb({})
  end)
end

return M
