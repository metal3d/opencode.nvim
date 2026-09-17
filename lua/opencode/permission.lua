--- Permission request handling.
---
--- When the OpenCode agent asks for a permission, the plugin surfaces it to the
--- user whose decision (`once`, `always` or `reject`) is sent back to the API.
local client = require("opencode.client")
local session = require("opencode.session")

local M = {}

--- List pending permission requests for the target session.
---@param cb fun(result: { data?: table[], err?: string })
function M.list(cb)
  if not session.get_target() then
    cb({ data = {} })
    return
  end
  client.api("GET", "/api/session/" .. session.get_target() .. "/permission", nil, function(res)
    if res.err then
      cb({ err = res.err })
      return
    end
    local data = (res.data and res.data.data) or {}
    cb({ data = data })
  end)
end

--- Reply to a permission request.
---@param requestID string
---@param decision "once" | "always" | "reject"
---@param cb? fun(result: { err?: string })
function M.reply(requestID, decision, cb)
  cb = cb or function() end
  if not session.get_target() then
    cb({ err = "no active session" })
    return
  end
  client.api(
    "POST",
    "/api/session/" .. session.get_target() .. "/permission/" .. requestID .. "/reply",
    { decision = decision },
    function(res)
      if res.err then
        cb({ err = res.err })
        return
      end
      cb({})
    end
  )
end

--- Prompt the user to allow or deny a single request.
---@param request table
function M.ask(request)
  local action = request.action or "?"
  local resources = table.concat(request.resources or {}, ", ")
  local label = action .. (resources ~= "" and (": " .. resources) or "")
  vim.ui.select({ "once", "always", "reject" }, {
    prompt = "OpenCode permission: " .. label,
  }, function(choice)
    if choice then
      M.reply(request.id, choice, function(res)
        if res.err then
          vim.notify("opencode: " .. res.err, vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

--- Prompt for every currently pending permission request.
function M.prompt_pending()
  M.list(function(res)
    if res.err then
      return
    end
    local items = res.data or {}
    if #items == 0 then
      vim.notify("opencode: no pending permissions", vim.log.levels.INFO)
      return
    end
    for _, req in ipairs(items) do
      M.ask(req)
    end
  end)
end

return M