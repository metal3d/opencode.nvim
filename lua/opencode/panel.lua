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

--- Whether a live `opencode` terminal exists, even when its split is closed.
---
--- Useful to tell "the panel was hidden" (reopen it) apart from "nothing is
--- running" (asking the user to start it).
---@return boolean
function M.has_job()
  return alive()
end

--- Build the argv used to launch the app, based on `panel.open`.
---
--- Returned as a list (not a shell string) so the session id is passed as a
--- literal argument and can never be interpreted as shell syntax.
---@return string[]
local function build_argv()
  local opts = config.get().panel
  local target = require("opencode.session").get_target()
  if opts.open == "session" and target then
    return { "opencode", "--session", target }
  elseif opts.open == "mini" then
    return target and { "opencode", "mini", "--session", target } or { "opencode", "mini" }
  elseif opts.open == "continue" then
    return { "opencode", "--continue" }
  end
  return { "opencode" }
end

--- Environment overrides for the terminal job.
---
--- Neovim (unlike most terminal emulators) does not propagate `COLORTERM` to a
--- `termopen()` pty, but OpenCode's OpenTUI renderer relies on it to pick
--- 24-bit colour (`if (COLORTERM === "truecolor" || COLORTERM === "24bit")`).
--- Without it the app falls back to a degraded palette. Forward whatever the
--- host terminal advertised, and default to truecolor when nothing is known,
--- so the TUI renders in full colour.
---@return table<string, string>
local function build_env()
  local colorterm = vim.env.COLORTERM
  if not colorterm or colorterm == "" then
    colorterm = "truecolor"
  end
  return { COLORTERM = colorterm }
end

--- Enter Terminal mode so typed keys reach the app without pressing `i`.
---
--- For a terminal buffer, `:startinsert` is documented to enter *Terminal-mode*
--- (the mode that forwards keys to the job), so the panel is immediately
--- typeable. Scoped to the panel's own buffer and gated by `panel.insert`, so
--- nothing changes for other buffers or terminals.
local function enter_terminal_mode()
  if config.get().panel.insert == false then
    return
  end
  if M.buf and vim.api.nvim_get_current_buf() == M.buf then
    vim.cmd("startinsert")
  end
end

--- Apply the configured buffer-local Terminal-mode mappings to `buf`.
---
--- Terminal mode forwards every key to the job except `<C-\>`, so Neovim never
--- sees keys such as `<C-w>` unless we intercept them. The default rewrites
--- `<C-w>` as:
---
---     <C-\><C-n>   leave Terminal mode (Neovim's native escape)
---     <C-w>        start the usual Normal-mode window prefix
---
--- so `<C-w><arrow>` — or `<C-w>h/j/k/l`, `<C-w>s`, … — navigates windows in a
--- single gesture, exactly like any other buffer. A raw `<C-w>` can still be
--- sent to the app with `<C-\><C-w>` (the `<C-\>` prefix forwards the next key).
---
--- `{ buffer = buf }` keeps every mapping on the panel's terminal buffer alone:
--- no global `tnoremap`, so other terminals and plugins keep their own maps.
---@param buf integer
local function apply_terminal_keys(buf)
  local keys = config.get().panel.terminal_keys
  if type(keys) ~= "table" then
    return
  end
  for lhs, rhs in pairs(keys) do
    if type(rhs) == "string" or type(rhs) == "function" then
      vim.keymap.set("t", lhs, rhs, { buffer = buf, desc = "opencode: terminal key" })
    end
  end
end

--- Install the panel terminal's buffer-local behaviour: its mappings and the
--- auto-insert on focus. Called once, when the terminal buffer is created.
---
--- The `BufEnter` autocmd (buffer-local) re-enters Terminal mode whenever the
--- panel regains focus by hand (e.g. `<C-w>w`). It defers through
--- `vim.schedule` because a `startinsert` fired in the middle of the
--- buffer/window switch can be undone by that very switch.
---@param buf integer
local function setup_terminal_buffer(buf)
  apply_terminal_keys(buf)
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    desc = "opencode: enter Terminal mode when the panel gains focus",
    callback = function()
      -- Deferred: `startinsert` right inside BufEnter can be undone by the
      -- surrounding buffer/window switch.
      vim.schedule(function()
        if vim.api.nvim_get_current_buf() == buf then
          enter_terminal_mode()
        end
      end)
    end,
  })
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

  -- Create the split first, so the terminal inherits the correct window size.
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
    -- Give the terminal its own buffer before launching it. `jobstart` with
    -- `term = true` calls `termopen()`, which turns the *current* buffer into a
    -- terminal. After a `vsplit`, both windows show that same buffer, so the
    -- terminal would also take over the editor window (and could clobber an open
    -- file). A dedicated buffer confines it to the panel.
    vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
    -- Launch the app with an argv list: no shell is involved, so a session id is
    -- never reinterpreted as shell syntax. `env` restores `COLORTERM`, which
    -- Neovim does not forward to the pty (see `build_env`).
    local ok, id = pcall(vim.fn.jobstart, build_argv(), { term = true, env = build_env() })
    if not ok or id <= 0 then
      vim.api.nvim_win_close(win, true)
      vim.notify("opencode: could not start the opencode CLI", vim.log.levels.ERROR)
      return false
    end
    M.buf = vim.api.nvim_get_current_buf()
    M.session = target
    setup_terminal_buffer(M.buf)
    spawned = true
  end

  M.win = win
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.api.nvim_set_current_win(win)
  enter_terminal_mode()
  return spawned
end

--- Write raw text into the running TUI without submitting it.
---
--- `\n` inserts a newline in the TUI prompt (like Ctrl+J) rather than sending,
--- so multi-line context stays readable. No `\r` is ever sent: submitting is
--- `send`'s job, and mixing the two is what made the old plugin fire a prompt
--- when it only meant to prefill.
---@param text string
---@return boolean typed
function M.append(text)
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    return false
  end
  local chan = vim.bo[M.buf].channel
  if not chan or chan <= 0 then
    return false
  end
  local body = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  return vim.fn.chansend(chan, body) > 0
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

--- Wait until the terminal has finished its initial draw.
---
--- "Ready" means the terminal buffer stayed identical (and non-trivial) for a
--- few consecutive polls. It is only a heuristic: when it cannot be trusted the
--- caller is told `ready = false` and must not inject blindly (see `deliver`,
--- which falls back to the API in that case).
---@param cb fun(ready: boolean)
---@param timeout? integer Milliseconds before giving up (default 8000).
function M.wait_ready(cb, timeout)
  local deadline = vim.uv.now() + (timeout or 8000)
  local last = nil
  local stable = 0
  local function check()
    if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
      cb(false)
      return
    end
    local lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)
    local snapshot = table.concat(lines, "\n")
    if #snapshot > 50 and snapshot == last then
      stable = stable + 1
      if stable >= 3 then
        cb(true)
        return
      end
    else
      stable = 0
    end
    last = snapshot
    if vim.uv.now() > deadline then
      cb(false)
      return
    end
    vim.defer_fn(check, 200)
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

--- Focus the panel window if it is currently open.
function M.focus()
  if M.is_open() then
    vim.api.nvim_set_current_win(M.win)
    enter_terminal_mode()
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
