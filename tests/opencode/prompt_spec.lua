local oc = require("opencode")
local session = require("opencode.session")
local panel = require("opencode.panel")

describe("opencode.prompt delivery", function()
  local real

  before_each(function()
    real = {
      ensure = oc.ensure,
      open = panel.open,
      send = panel.send,
      append = panel.append,
      prompt = session.prompt,
    }
    oc.ensure = function(cb)
      cb(nil)
    end
  end)

  after_each(function()
    oc.ensure = real.ensure
    panel.open = real.open
    panel.send = real.send
    panel.append = real.append
    session.prompt = real.prompt
  end)

  it("sends through the v2 API, which is the point of truth", function()
    local asked
    session.prompt = function(text, _, cb)
      asked = text
      cb({})
    end

    oc.prompt("hi")

    assert.are.equal("hi", asked)
  end)

  it("never writes a prompt to the terminal", function()
    panel.send = function()
      error("the pty must not be used to send prompts")
    end
    panel.append = function()
      error("the pty must not be used to send prompts")
    end
    panel.open = function()
      error("sending a prompt must not open the panel")
    end
    session.prompt = function(_, _, cb)
      cb({})
    end

    oc.prompt("hi")
  end)

  it("works without a running panel", function()
    panel.open = function()
      return false
    end
    local asked
    session.prompt = function(text, _, cb)
      asked = text
      cb({})
    end

    oc.prompt("hi")

    assert.are.equal("hi", asked)
  end)

  it("surfaces API errors to the caller", function()
    session.prompt = function(_, _, cb)
      cb({ err = "boom" })
    end
    local err
    local real_notify = vim.notify
    vim.notify = function() end

    oc.prompt("hi", function(res)
      err = res.err
    end)

    vim.notify = real_notify
    assert.are.equal("boom", err)
  end)
end)
