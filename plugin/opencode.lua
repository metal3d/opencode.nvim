-- opencode.nvim — plugin entry point.
--
-- Registers user commands and the reload default. The actual behaviour lives in
-- lua/opencode/*.lua; this file only wires up startup concerns and should stay
-- light.

-- Buffers edited by OpenCode reload automatically (unless the user explicitly
-- opted out via `opts.events.reload = false`).
local config_ok, config = pcall(require, "opencode.config")
if config_ok then
  if config.get().events.reload then
    vim.opt.autoread = true
  end

  -- React to OpenCode's SSE file events when it emits them.
  --
  -- `opts.events.reload` may only be known once `setup()` runs (lazy.nvim calls
  -- it after this file is sourced), so the option is checked at event time
  -- rather than at load time.
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("OpencodeReload", { clear = true }),
    pattern = { "OpencodeEvent:filesystem.changed", "OpencodeEvent:file.edited" },
    callback = function()
      if not config.get().events.reload then
        return
      end
      -- Scheduled: blocking the event loop during rapid SSE influx can drop events.
      vim.schedule(function()
        vim.cmd("checktime")
      end)
    end,
    desc = "Reload buffers edited by OpenCode",
  })
end

local function oc()
  return require("opencode")
end

local function user_cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

user_cmd("OpencodeToggle", function()
  oc().toggle()
end, { desc = "Toggle the OpenCode panel" })

user_cmd("OpencodeRestart", function()
  oc().restart()
end, { desc = "Restart the OpenCode terminal instance" })

user_cmd("OpencodeAsk", function()
  oc().ask()
end, { desc = "Ask OpenCode" })

user_cmd("OpencodeReview", function()
  oc().review()
end, { desc = "Review the current context" })

user_cmd("OpencodeFix", function()
  oc().fix()
end, { desc = "Fix the current diagnostics" })

user_cmd("OpencodeExplain", function()
  oc().explain()
end, { desc = "Explain the current context" })

user_cmd("OpencodeAudit", function()
  oc().audit()
end, { desc = "Audit the current context" })

user_cmd("OpencodeCommand", function()
  oc().command()
end, { desc = "Open the OpenCode action palette" })

user_cmd("OpencodeSession", function()
  oc().session()
end, { desc = "Switch the active OpenCode session" })

user_cmd("OpencodePermissions", function()
  oc().permissions()
end, { desc = "Surface pending OpenCode permissions" })

user_cmd("OpencodeDiff", function()
  oc().diff()
end, { desc = "View the current session diff" })
