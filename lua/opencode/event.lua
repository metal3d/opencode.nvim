--- Server-Sent-Events pipeline.
---
--- Subscribes to the OpenCode `/api/event` stream, parses each event and
--- broadcasts it as an `OpencodeEvent:<type>` User autocmd while notifying an
--- optional in-process handler (used to redraw the panel live).
local client = require("opencode.client")

local M = {}

--- Whether the subscription is wanted (set by `subscribe`, cleared by
--- `unsubscribe`). Reconnection only happens while this is true.
M.subscribed = false
--- Whether a stream is currently open.
M.streaming = false
--- Partial SSE bytes carried between chunks.
M.buffer = ""
--- Optional in-process handler.
M.on_event = nil
--- Optional predicate: when set, only events it accepts are dispatched.
---@type fun(ev: table): boolean?
M.filter = nil

--- Reconnection backoff, in milliseconds: the delay doubles on each failure up
--- to `retry_max_ms` and resets to `retry_initial_ms` as soon as data arrives.
M.retry_initial_ms = 1000
M.retry_max_ms = 30000
M.retry_ms = 1000
--- Pending reconnection timer, if any.
M.retry_timer = nil

--- Cancel a pending reconnection.
local function cancel_retry()
  if M.retry_timer and not M.retry_timer:is_closing() then
    M.retry_timer:stop()
    M.retry_timer:close()
  end
  M.retry_timer = nil
end

--- Open one SSE stream, re-arming on end while a subscription is still wanted.
local function connect()
  M.streaming = true
  -- Drop any partial event left over from the previous (dead) connection.
  M.buffer = ""
  client.stream("/api/event", {
    on_data = function(chunk)
      -- Data flowing means the stream is healthy: reset the backoff.
      M.retry_ms = M.retry_initial_ms
      M.ingest(chunk)
    end,
    on_done = function()
      M.streaming = false
      if not M.subscribed then
        return
      end
      cancel_retry()
      local delay = M.retry_ms
      M.retry_ms = math.min(M.retry_ms * 2, M.retry_max_ms)
      M.retry_timer = vim.uv.new_timer()
      M.retry_timer:start(
        delay,
        0,
        vim.schedule_wrap(function()
          M.retry_timer = nil
          if M.subscribed and not M.streaming then
            connect()
          end
        end)
      )
    end,
  })
end

--- Begin (or re-arm) the SSE subscription.
---
--- Idempotent while a subscription is wanted, and automatically reconnects
--- (with exponential backoff) when the stream drops.
function M.subscribe()
  if M.subscribed then
    return
  end
  M.subscribed = true
  M.retry_ms = M.retry_initial_ms
  connect()
end

--- Stop the subscription and cancel any pending reconnection.
function M.unsubscribe()
  M.subscribed = false
  cancel_retry()
end

--- Dispatch a decoded event to Neovim and the in-process handler.
local function dispatch(ev)
  if type(ev) ~= "table" or type(ev.type) ~= "string" then
    return
  end
  if M.filter and not M.filter(ev) then
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
      local _, stop = line:find("^data: ")
      if stop then
        local body = line:sub(stop + 1)
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
