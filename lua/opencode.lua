---opencode.nvim public API.
local M = {}

---@param err? string
local function on_error(err)
  if err then
    vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
  end
end

---Input a prompt for OpenCode.
---
--- - Passes the text to `prompt()`.
--- - Press `<Up>` to browse recent asks.
--- - Highlights and completes contexts and OpenCode subagents.
---   - Press `<Tab>` to trigger built-in completion.
---   - Provided by in-process LSP when using [snacks.input](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---
---@param default? string Text to pre-fill the input with.
function M.ask(default)
  M.open()
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      local context = require("opencode.context").new(server)
      return require("opencode.ui.ask").ask(default, context):next(function(input)
        return require("opencode.api.prompt").prompt(input, context)
      end)
    end)
    :catch(on_error)
end

---Select from all opencode.nvim functionality.
---
--- - Prompts
--- - Commands
--- - Servers
---
--- Highlights and previews items when using [snacks.picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md).
---
---@param opts? opencode.select.Opts Override configured options for this call.
function M.select(opts)
  M.open()
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      local context = require("opencode.context").new(server)
      return require("opencode.ui.select").select(context, opts)
    end)
    :catch(on_error)
end

M.statusline = require("opencode.events.status").statusline

---Prompt OpenCode.
---
--- - Injects configured contexts.
--- - Trailing space appends; trailing "..." opens in `ask()`.
--- - OpenCode will interpret references to files or subagents.
---
---@param prompt string
function M.prompt(prompt)
  M.open()
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      local context = require("opencode.context").new(server)
      return require("opencode.api.prompt").prompt(prompt, context)
    end)
    :catch(on_error)
end

---Command OpenCode.
---
---@param command opencode.server.Command | string
function M.command(command)
  M.open()
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      return require("opencode.api.command").command(command, server)
    end)
    :catch(on_error)
end

---Wraps `prompt` as an operator, supporting ranges and dot-repeat.
---
---@param prompt string
function M.operator(prompt)
  _G.opencode_prompt_operator = function(kind) ---@param kind "char" | "line" | "block"
    local start_pos = vim.api.nvim_buf_get_mark(0, "[")
    local end_pos = vim.api.nvim_buf_get_mark(0, "]")
    if start_pos[1] > end_pos[1] or (start_pos[1] == end_pos[1] and start_pos[2] > end_pos[2]) then
      start_pos, end_pos = end_pos, start_pos
    end

    require("opencode.server.discovery")
      .get()
      :next(function(server)
        local context = require("opencode.context").new(server, {
          from = { start_pos[1], start_pos[2] },
          to = { end_pos[1], end_pos[2] },
          kind = kind,
        })

        return require("opencode.api.prompt").prompt(prompt, context)
      end)
      :catch(on_error)
  end

  vim.o.operatorfunc = "v:lua.opencode_prompt_operator"
  return "g@"
end

---The buffer backing an OpenCode TUI opened by `toggle()`, if any.
---@type integer?
local tui_buf = nil
---The window currently showing that TUI, if visible.
---@type integer?
local tui_win = nil

---Whether the tracked TUI terminal still has a live job.
---
---@return boolean
local function tui_alive()
  return tui_buf ~= nil and vim.api.nvim_buf_is_valid(tui_buf) and (vim.bo[tui_buf].channel or 0) > 0
end

---Show the OpenCode TUI panel on the right.
---
---Opens `opencode` in a right-hand split, reusing the existing terminal when one
---is already running. The TUI runs in the Neovim working directory so opencode
---creates and manages sessions for THIS project — the server's `/api/session`
---cannot place a new session in a target directory, so prompts target the
---project's existing sessions instead.
function M.open()
  if tui_win and vim.api.nvim_win_is_valid(tui_win) then
    return
  end

  -- The panel is a local TUI attached to the local background service. When a
  -- URL is configured (e.g. a remote server), leave it alone (PR #330 review).
  if require("opencode.config").opts.server.url ~= nil then
    return
  end

  local origin = vim.api.nvim_get_current_win()
  vim.cmd("botright vsplit")
  if tui_alive() and tui_buf then
    vim.api.nvim_win_set_buf(0, tui_buf)
  else
    -- Run the TUI in the Neovim working directory. The terminal inherits nvim's
    -- cwd, so opencode builds sessions for this project; prompts then target
    -- those project sessions (see :resolve_session_id). When the TUI already has
    -- open tabs here, resume the last one instead of opening a fresh session.
    local session_id = require("opencode.util.state").last_tab_session(vim.fn.getcwd())
    if session_id and session_id ~= "" then
      vim.cmd("terminal opencode --session " .. session_id)
    else
      vim.cmd("terminal opencode")
    end
    tui_buf = vim.api.nvim_get_current_buf()
  end
  tui_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(origin)
end

---Toggle the OpenCode TUI panel on the right.
---
---Opens `opencode` in a right-hand split if hidden, or hides it if visible.
---The terminal keeps running across toggles.
function M.toggle()
  if tui_win and vim.api.nvim_win_is_valid(tui_win) then
    vim.api.nvim_win_hide(tui_win)
    tui_win = nil
    return
  end
  M.open()
end

M.format = require("opencode.context").format

return M
