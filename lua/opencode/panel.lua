--- Side panel: the real OpenCode application in a Neovim terminal.
---
--- Opens `opencode` in a vertical split (left or right). The terminal is created
--- with `:terminal` inside the already-sized window so the pseudo-terminal
--- matches the window and the TUI renders correctly. The buffer and job are kept
--- alive so toggling hides and shows the same running instance.
local config = require("opencode.config")

local M = {}

M.win = nil
M.buf = nil
M.session = nil

---@return boolean
function M.is_open()
  return M.win ~= nil and vim.api.nvim_win_is_valid(M.win)
end

--- Whether the tracked terminal still has a live job.
---@return boolean
local function alive()
  return M.buf ~= nil and vim.api.nvim_buf_is_valid(M.buf) and (vim.bo[M.buf].channel or 0) > 0
end

--- Build the command string used to launch the app, based on `panel.open`.
---@return string
local function build_cmd()
  local opts = config.get().panel
  local target = require("opencode.session").get_target()
  if opts.open == "session" and target then
    return "opencode --session " .. target
  elseif opts.open == "mini" then
    return target and ("opencode mini --session " .. target) or "opencode mini"
  elseif opts.open == "continue" then
    return "opencode --continue"
  end
  return "opencode"
end

--- Open the panel (or focus it when already open).
---@return boolean spawned # Whether a new terminal instance was started.
function M.open()
  if M.is_open() then
    M.focus()
    return false
  end

  local opts = config.get().panel
  local target = require("opencode.session").get_target()

  -- If the app is running on a different session, restart it.
  if alive() and M.session ~= target then
    pcall(vim.fn.jobstop, vim.bo[M.buf].channel)
    M.buf = nil
  end

  -- Create the split first, so `:terminal` inherits the correct window size.
  if opts.position == "left" then
    vim.cmd("topleft vsplit")
  else
    vim.cmd("botright vsplit")
  end
  local win = vim.api.nvim_get_current_win()
  if type(opts.size) == "number" and opts.size > 0 then
    vim.api.nvim_win_set_width(win, opts.size)
  end

  local spawned = false
  if alive() then
    vim.api.nvim_win_set_buf(win, M.buf)
  else
    vim.cmd("terminal " .. build_cmd())
    M.buf = vim.api.nvim_get_current_buf()
    M.session = target
    spawned = true
  end

  M.win = win
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.api.nvim_set_current_win(win)
  return spawned
end

--- Inject text into the running TUI and submit it.
---
--- This writes to the terminal's pty, so the text lands in the tab the user is
--- looking at (unlike the HTTP API, which targets a specific session).
---@param text string
---@return boolean sent
function M.send(text)
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    return false
  end
  local chan = vim.bo[M.buf].channel
  if not chan or chan <= 0 then
    return false
  end
  -- `\n` inserts a newline in the TUI prompt (like Ctrl+J); `\r` submits. Keep
  -- newlines so multi-line prompts (diagnostics lists) stay readable.
  local body = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  vim.fn.chansend(chan, body)
  vim.defer_fn(function()
    if M.buf and vim.api.nvim_buf_is_valid(M.buf) and (vim.bo[M.buf].channel or 0) > 0 then
      vim.fn.chansend(vim.bo[M.buf].channel, "\r")
    end
  end, 150)
  return true
end

--- Type text into the running TUI without submitting (prefill the prompt).
---@param text string
---@return boolean typed
function M.type(text)
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    return false
  end
  local chan = vim.bo[M.buf].channel
  if not chan or chan <= 0 then
    return false
  end
  local body = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  vim.fn.chansend(chan, body)
  return true
end

--- Wait until the terminal has finished its initial draw (content is stable).
---@param cb fun(ready: boolean)
---@param timeout? integer Milliseconds before giving up (default 12000).
function M.wait_ready(cb, timeout)
  local deadline = vim.uv.now() + (timeout or 12000)
  local last = nil
  local function check()
    if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
      cb(false)
      return
    end
    local lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)
    local snapshot = table.concat(lines, "\n")
    if #snapshot > 50 and snapshot == last then
      cb(true)
      return
    end
    last = snapshot
    if vim.uv.now() > deadline then
      cb(false)
      return
    end
    vim.defer_fn(check, 300)
  end
  check()
end

--- Close the panel (the terminal job keeps running, hidden).
function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(M.win, true)
  end
  M.win = nil
end

--- Toggle the panel open/closed.
function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

--- Focus the panel window if it is currently open.
function M.focus()
  if M.is_open() then
    vim.api.nvim_set_current_win(M.win)
  end
end

--- Focus the panel and enter terminal input mode so typing reaches opencode.
function M.enter()
  M.focus()
  if M.is_open() then
    vim.cmd("startinsert")
  end
end

--- Kill the running instance and respawn it (e.g. after changing `panel.open`).
function M.restart()
  if alive() then
    pcall(vim.fn.jobstop, vim.bo[M.buf].channel)
  end
  M.buf = nil
  M.session = nil
  local was_open = M.is_open()
  if was_open then
    M.close()
    M.open()
  end
end

return M