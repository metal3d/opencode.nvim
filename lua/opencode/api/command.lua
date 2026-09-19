local M = {}

local Promise = require("opencode.promise")

---Commands that only the legacy `/tui/*` control endpoints can perform.
---These have no OpenCode v2 HTTP API equivalent (scroll, navigation, prompt box).
---@type table<string, boolean>
local TUI_ONLY = {
  ["prompt.clear"] = true,
  ["prompt.submit"] = true,
  ["session.first"] = true,
  ["session.last"] = true,
  ["session.half.page.up"] = true,
  ["session.half.page.down"] = true,
  ["session.page.up"] = true,
  ["session.page.down"] = true,
  ["session.select"] = true,
  ["session.share"] = true,
  ["session.redo"] = true,
  ["session.undo"] = true,
}

---Cycle the active session's agent through the visible primary agents.
---
---@param server opencode.server.Server
---@return Promise<any>
local function cycle_agent(server)
  return server:resolve_session_id():next(function(session_id)
    return Promise.all({
      server:get_sessions(),
      server:get_agents(),
    }):next(function(results)
      local sessions, agents = results[1], results[2]

      -- The session's current agent is only exposed on list items.
      local current
      for _, session in ipairs(sessions) do
        if session.id == session_id then
          current = session.agent
          break
        end
      end

      local primary = vim.tbl_filter(function(agent) ---@param agent { id: string, mode: string, hidden?: boolean }
        return agent.mode == "primary" and not agent.hidden
      end, agents or {})

      if #primary == 0 then
        return Promise.resolve(nil)
      end

      local next_agent = primary[1]
      for index, agent in ipairs(primary) do
        if agent.id == current then
          next_agent = primary[index % #primary + 1]
          break
        end
      end

      return server:switch_agent(session_id, next_agent.id)
    end)
  end)
end

---Execute a built-in OpenCode command.
---
---Commands map onto v2 HTTP API calls where possible; TUI-only commands
---(scroll, navigation, prompt box) require the legacy `/tui/*` endpoints and
---degrade to a silent no-op when the connected server does not expose them.
---
---@param command opencode.server.Command | string
---@param server opencode.server.Server
---@return Promise<any>
function M.command(command, server)
  if command == "session.new" then
    -- TODO: `create_session()` POSTs /api/session, which on the shared service
    -- always creates the session in the service's ambient cwd (often ~) — the
    -- same limitation as the retired panel session. Revisit once opencode lets
    -- the API place a session in a target directory.
    return server:create_session():next(function(created)
      return Promise.resolve(created)
    end)
  elseif command == "session.interrupt" then
    return server:resolve_session_id():next(function(session_id)
      return server:interrupt(session_id)
    end)
  elseif command == "session.compact" then
    return server:resolve_session_id():next(function(session_id)
      return server:compact(session_id)
    end)
  elseif command == "agent.cycle" then
    return cycle_agent(server)
  end

  if TUI_ONLY[command] then
    if not server.tui then
      -- No `/tui/*` on OpenCode v2.0.x: these have no API equivalent.
      return Promise.resolve(nil)
    end
    return server:tui_execute_command(command):next(function()
      if command == "session.interrupt" then
        -- Evidently OpenCode only uses this command for their "double-tap Esc to interrupt" user keybind.
        -- So we have to double-send it to actually interrupt.
        return server:tui_execute_command(command)
      end
    end)
  end

  -- Unknown command: forward to the TUI when available, otherwise surface it.
  if server.tui then
    return server:tui_execute_command(command)
  end
  return Promise.reject("Unknown OpenCode command: `" .. command .. "`")
end

return M
