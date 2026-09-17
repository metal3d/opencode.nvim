local panel = require("opencode.panel")
local session = require("opencode.session")

describe("panel.open", function()
  local tmp
  local real_path

  before_each(function()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    real_path = vim.env.PATH
    vim.env.PATH = tmp .. ":" .. (real_path or "")
  end)

  after_each(function()
    if panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then
      local chan = vim.bo[panel.buf].channel
      if chan and chan > 0 then
        pcall(vim.fn.jobstop, chan)
      end
      pcall(vim.api.nvim_buf_delete, panel.buf, { force = true })
    end
    panel.win, panel.buf, panel.session = nil, nil, nil
    vim.cmd("silent! only!")
    vim.env.PATH = real_path
    session.set_target(nil)
    vim.fn.delete(tmp, "rf")
  end)

  --- Drop a fake `opencode` in the temp dir that records its arguments.
  ---@return string args_file
  local function fake_opencode()
    local args_file = tmp .. "/args.txt"
    local script = tmp .. "/opencode"
    vim.fn.writefile({
      "#!/bin/sh",
      "printf '%s\\n' \"$@\" > " .. args_file,
      "sleep 30",
    }, script)
    vim.fn.setfperm(script, "rwxr-xr-x")
    return args_file
  end

  it("passes the session id as a literal argument, with no shell in between", function()
    local args_file = fake_opencode()
    -- A session id full of shell metacharacters: it must arrive verbatim.
    session.set_target("ses_x; touch pwned && $(echo nope)")

    local spawned = panel.open()

    assert.is_true(spawned)
    assert.is_true(panel.buf ~= nil and vim.api.nvim_buf_is_valid(panel.buf))
    assert.is_true((vim.bo[panel.buf].channel or 0) > 0)

    vim.wait(3000, function()
      return vim.fn.filereadable(args_file) == 1
    end)
    assert.are.equal(1, vim.fn.filereadable(args_file))
    assert.are.same({ "--session", "ses_x; touch pwned && $(echo nope)" }, vim.fn.readfile(args_file))
    -- The metacharacters must not have run anything.
    assert.are.equal(0, vim.fn.filereadable(tmp .. "/pwned"))
  end)

  it("confines the terminal to the panel window and keeps the editor buffer", function()
    fake_opencode()
    session.set_target(nil)
    -- A real file open in the editor window: `termopen()` used to convert this
    -- very buffer into the terminal (and, after a `vsplit`, show the TUI in both
    -- windows) because `jobstart(term = true)` reuses the current buffer.
    local editor_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(editor_buf, 0, -1, false, { "local keep_me = true" })
    vim.bo[editor_buf].modified = false

    local spawned = panel.open()

    assert.is_true(spawned)
    -- The panel has its own buffer...
    assert.is_true(panel.buf ~= nil and panel.buf ~= editor_buf)
    assert.are.equal("terminal", vim.bo[panel.buf].buftype)
    -- ...shown only in the panel window, so the editor buffer is untouched.
    local wins = vim.api.nvim_list_wins()
    local panel_wins = 0
    for _, w in ipairs(wins) do
      if vim.api.nvim_win_get_buf(w) == panel.buf then
        panel_wins = panel_wins + 1
      end
    end
    assert.are.equal(1, panel_wins)
    assert.are.equal("", vim.bo[editor_buf].buftype)
    assert.are.same({ "local keep_me = true" }, vim.api.nvim_buf_get_lines(editor_buf, 0, -1, false))
  end)

  it("forwards COLORTERM to the terminal so the TUI keeps 24-bit colour", function()
    -- `opencode`'s OpenTUI renderer checks COLORTERM to decide between truecolor
    -- and a degraded palette, and Neovim does not forward it to the pty.
    local out_file = tmp .. "/env.txt"
    local script = tmp .. "/opencode"
    vim.fn.writefile({
      "#!/bin/sh",
      "printenv COLORTERM > " .. out_file,
      "sleep 30",
    }, script)
    vim.fn.setfperm(script, "rwxr-xr-x")

    local real_colorterm = vim.env.COLORTERM
    vim.env.COLORTERM = "truecolor"
    panel.open()

    assert.is_true(vim.wait(3000, function()
      return vim.fn.filereadable(out_file) == 1
    end))
    assert.are.same({ "truecolor" }, vim.fn.readfile(out_file))
    vim.env.COLORTERM = real_colorterm
  end)

  it("defaults COLORTERM to truecolor when the host did not set it", function()
    local out_file = tmp .. "/env.txt"
    local script = tmp .. "/opencode"
    vim.fn.writefile({
      "#!/bin/sh",
      "printenv COLORTERM > " .. out_file,
      "sleep 30",
    }, script)
    vim.fn.setfperm(script, "rwxr-xr-x")

    local real_colorterm = vim.env.COLORTERM
    vim.env.COLORTERM = nil
    panel.open()

    assert.is_true(vim.wait(3000, function()
      return vim.fn.filereadable(out_file) == 1
    end))
    assert.are.same({ "truecolor" }, vim.fn.readfile(out_file))
    vim.env.COLORTERM = real_colorterm
  end)

  it("does not crash when the CLI is missing", function()
    vim.env.PATH = "/nonexistent"
    session.set_target(nil)
    local notified
    local real_notify = vim.notify
    vim.notify = function(msg)
      notified = msg
    end

    local spawned = panel.open()

    vim.notify = real_notify
    assert.is_false(spawned)
    assert.is_truthy(notified and notified:find("could not start", 1, true))
  end)
end)

describe("panel.wait_ready", function()
  local real_buf

  before_each(function()
    real_buf = panel.buf
    panel.buf = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then
      pcall(vim.api.nvim_buf_delete, panel.buf, { force = true })
    end
    panel.buf = real_buf
  end)

  local function set(lines)
    vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  end

  it("reports ready once the content has been stable for a few polls", function()
    set({ string.rep("x", 60) })
    local result
    panel.wait_ready(function(ready)
      result = ready
    end, 3000)
    vim.wait(3000, function()
      return result ~= nil
    end)
    assert.is_true(result)
  end)

  it("reports not-ready when the content keeps changing", function()
    local n = 0
    local timer = vim.uv.new_timer()
    timer:start(
      0,
      40,
      vim.schedule_wrap(function()
        n = n + 1
        set({ string.rep("x", 60) .. n })
      end)
    )
    local result
    panel.wait_ready(function(ready)
      result = ready
    end, 300)
    vim.wait(2000, function()
      return result ~= nil
    end)
    timer:stop()
    timer:close()
    assert.is_false(result)
  end)
end)
