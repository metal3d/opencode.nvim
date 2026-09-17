--- Session diff review.
---
--- OpenCode applies file edits itself once permissions are granted. This module
--- lets the user *inspect* the changes the agent produced in the active session
--- (from `/api/session/{id}/diff`) in a dedicated scratch buffer.
local M = {}

local client = require("opencode.client")
local session = require("opencode.session")

--- Fetch the session diff entries.
---@param cb fun(result: { data?: table[], err?: string })
function M.diff(cb)
  if not session.get_target() then
    cb({ data = {} })
    return
  end
  client.api("GET", "/api/session/" .. session.get_target() .. "/diff", nil, function(res)
    if res.err then
      cb({ err = res.err })
      return
    end
    cb({ data = (res.data and res.data.data) or {} })
  end)
end

--- Render a single diff entry into lines.
local function render_entry(entry)
  local lines = {}
  lines[#lines + 1] = "── " .. (entry.file or "?") .. "  (" .. (entry.status or "?") .. ")"
  if entry.additions or entry.deletions then
    lines[#lines + 1] = ("additions: %d, deletions: %d"):format(entry.additions or 0, entry.deletions or 0)
  end
  if entry.patch and entry.patch ~= "" then
    for line in (entry.patch .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line:gsub("\r$", "")
    end
  end
  lines[#lines + 1] = ""
  return lines
end

--- Open a read-only preview of the session's file changes.
function M.preview()
  M.diff(function(res)
    if res.err then
      vim.notify("opencode: " .. res.err, vim.log.levels.ERROR)
      return
    end
    local entries = res.data or {}
    if #entries == 0 then
      vim.notify("opencode: no pending diffs", vim.log.levels.INFO)
      return
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "diff"

    local lines = {}
    for _, entry in ipairs(entries) do
      vim.list_extend(lines, render_entry(entry))
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.cmd("topleft vertical split")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf, desc = "opencode: close diff" })
  end)
end

return M
