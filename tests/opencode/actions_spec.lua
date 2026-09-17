local oc = require("opencode")
local session = require("opencode.session")
local diff = require("opencode.diff")
local permission = require("opencode.permission")

describe("opencode actions", function()
  local real

  before_each(function()
    real = {
      ensure = oc.ensure,
      session_list_all = session.list_all,
      diff_preview = diff.preview,
      prompt_pending = permission.prompt_pending,
      select = vim.ui.select,
      notify = vim.notify,
    }
  end)

  after_each(function()
    oc.ensure = real.ensure
    session.list_all = real.session_list_all
    diff.preview = real.diff_preview
    permission.prompt_pending = real.prompt_pending
    vim.ui.select = real.select
    vim.notify = real.notify
  end)

  it("routes session()/diff()/permissions() through ensure", function()
    local ensured, called = 0, {}
    oc.ensure = function(cb)
      ensured = ensured + 1
      cb(nil)
    end
    session.list_all = function(cb)
      called.session = true
      cb({ data = {} })
    end
    diff.preview = function()
      called.diff = true
    end
    permission.prompt_pending = function()
      called.permissions = true
    end
    vim.ui.select = function() end

    oc.session()
    oc.diff()
    oc.permissions()

    assert.are.equal(3, ensured)
    assert.is_true(called.session)
    assert.is_true(called.diff)
    assert.is_true(called.permissions)
  end)

  it("reports the connection error instead of acting", function()
    local called = false
    local notified
    oc.ensure = function(cb)
      cb("no server")
    end
    diff.preview = function()
      called = true
    end
    vim.notify = function(msg)
      notified = msg
    end

    oc.diff()

    assert.is_false(called)
    assert.is_truthy(notified and notified:find("no server", 1, true))
  end)
end)
