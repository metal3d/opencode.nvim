--- Server-Sent-Events pipeline.
---
--- Subscribes to the OpenCode `/api/event` stream, parses each event and
--- broadcasts it as an `OpencodeEvent:<type>` User autocmd while notifying an
--- optional in-process handler (used to redraw the panel live).
local client = require("opencode.client")

local M = {}

M.subscribed = false
M.buffer = ""
M.on_event = nil

--- Begin (or re-arm) the SSE subscription.
function M.subscribe()
  if M.subscribed then
    return
  end
  M.subscribed = true
  client.stream("/api/event", {
    on_data = function(chunk)
      M.ingest(chunk)
    end,
    on_done = function()
      M.subscribed = false
    end,
  })
end

--- Dispatch a decoded event to Neovim and the in-process handler.
local function dispatch(ev)
  if type(ev) ~= "table" or type(ev.type) ~= "string" then
    return
  end
  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "OpencodeEvent:" .. ev.type,
    data = { event = ev },
  })
  if M.on_event then
    M.on_event(ev)
  end
end

--- Consume raw SSE bytes, extracting complete `data:` events.
---@param chunk string
function M.ingest(chunk)
  if type(chunk) ~= "string" or chunk == "" then
    return
  end
  M.buffer = M.buffer .. chunk
  local pending = {}
  while true do
    local tail = M.buffer:find("\n\n", 1, true)
    if not tail then
      break
    end
    local raw = M.buffer:sub(1, tail - 1)
    M.buffer = M.buffer:sub(tail + 2)
    local payload = nil
    for line in raw:gmatch("[^\r\n]+") do
      local s, _ = line:find("^data: ")
      if s then
        local body = line:sub(4)
        local ok, decoded = pcall(vim.json.decode, body)
        if ok and decoded then
          payload = decoded
        end
      end
    end
    if payload then
      pending[#pending + 1] = payload
    end
  end
  if #pending > 0 then
    -- This callback arrives from the fast-event SSE stream; defer dispatch so
    -- autocmds and buffer updates run in the normal context.
    local queued = pending
    vim.schedule(function()
      for _, ev in ipairs(queued) do
        dispatch(ev)
      end
    end)
  end
end

return M