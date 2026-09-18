local M = {}

---@param prompt string
---@param context opencode.context.Context
---@return Promise<any>
function M.prompt(prompt, context)
  local Promise = require("opencode.promise")
  return (
    prompt:match("%.%.%.$") and require("opencode.ui.ask").ask(prompt:gsub("%.%.%.$", ""), context)
    or Promise.resolve(prompt)
  )
    :next(function(_prompt)
      local plaintext = context:render(_prompt).output:plaintext()
      local server = context.server

      -- Servers exposing the legacy TUI control endpoints keep the v1 behavior:
      -- append to the TUI prompt, then submit unless the prompt ends with a space.
      if server.tui then
        return server:tui_append_prompt(plaintext):next(function()
          if not _prompt:match(" $") then
            return server:tui_execute_command("prompt.submit")
          end
        end)
      end

      -- Otherwise send the prompt straight to the active session. OpenCode v2
      -- has no "append without submitting" concept outside the TUI.
      return server:resolve_session_id():next(function(session_id)
        return server:send_prompt(session_id, plaintext)
      end)
    end)
    :next(function()
      context:clear()
    end)
    :catch(function(err)
      context:resume()
      return Promise.reject(err)
    end)
end

return M
