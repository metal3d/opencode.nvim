local oc = require("opencode")
local session = require("opencode.session")
local panel = require("opencode.panel")

describe("opencode.prompt delivery", function()
  local real

  before_each(function()
    real = {
      ensure = oc.ensure,
      open = panel.open,
      wait_ready = panel.wait_ready,
      send = panel.send,
      prompt = session.prompt,
    }
    oc.ensure = function(cb)
      cb(nil)
    end
  end)

  after_each(function()
    oc.ensure = real.ensure
    panel.open = real.open
    panel.wait_ready = real.wait_ready
    panel.send = real.send
    session.prompt = real.prompt
  end)

  it("injects into the TUI once it is ready", function()
    panel.open = function()
      return true
    end
    panel.wait_ready = function(cb)
      cb(true)
    end
    local sent
    panel.send = function(text)
      sent = text
      return true
    end
    session.prompt = function()
      error("should not fall back")
    end

    oc.prompt("hi")
    vim.wait(1000, function()
      return sent ~= nil
    end)
    assert.are.equal("hi", sent)
  end)

  it("falls back to the API when the TUI is not ready", function()
    panel.open = function()
      return true
    end
    panel.wait_ready = function(cb)
      cb(false)
    end
    local sent = false
    panel.send = function()
      sent = true
      return true
    end
    local asked
    session.prompt = function(text, _, cb)
      asked = text
      cb({})
    end

    oc.prompt("hi")
    assert.is_false(sent) -- never injected blindly
    assert.are.equal("hi", asked)
  end)

  it("injects immediately when the panel was already open", function()
    panel.open = function()
      return false
    end
    panel.wait_ready = function()
      error("should not wait")
    end
    local sent
    panel.send = function(text)
      sent = text
      return true
    end

    oc.prompt("hi")
    assert.are.equal("hi", sent)
  end)
end)
