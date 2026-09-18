local oc = require("opencode")
local panel = require("opencode.panel")
local context = require("opencode.context")

describe("opencode.append", function()
  local real

  before_each(function()
    real = {
      open = panel.open,
      has_job = panel.has_job,
      is_open = panel.is_open,
      wait_ready = panel.wait_ready,
      append = panel.append,
      render = context.render,
    }
    -- Pretend the panel is already up and healthy by default.
    panel.is_open = function()
      return true
    end
    panel.has_job = function()
      return true
    end
    panel.open = function()
      return false
    end
    context.render = function()
      return "@lua/foo.lua:1"
    end
  end)

  after_each(function()
    panel.open = real.open
    panel.has_job = real.has_job
    panel.is_open = real.is_open
    panel.wait_ready = real.wait_ready
    panel.append = real.append
    context.render = real.render
  end)

  it("adds the rendered context to the prompt without submitting", function()
    local added
    panel.append = function(text)
      added = text
      return true
    end

    local ok = oc.append()

    assert.is_true(ok)
    assert.are.equal("@lua/foo.lua:1", added)
  end)

  it("uses the requested placeholder", function()
    local asked
    context.render = function(ph)
      asked = ph
      return "@sel"
    end
    panel.append = function()
      return true
    end

    oc.append("@selection")

    assert.are.equal("@selection", asked)
  end)

  it("reopens the split when the job is alive but hidden", function()
    panel.is_open = function()
      return false
    end
    local opened = false
    panel.open = function()
      opened = true
      return false
    end
    panel.append = function()
      return true
    end

    assert.is_true(oc.append())
    assert.is_true(opened)
  end)

  it("waits for the TUI when the panel was freshly spawned", function()
    panel.open = function()
      return true
    end
    local waited = false
    panel.wait_ready = function(cb)
      waited = true
      cb(true)
    end
    local added
    panel.append = function(text)
      added = text
      return true
    end

    oc.append()
    vim.wait(1000, function()
      return added ~= nil
    end)
    assert.is_true(waited)
    assert.are.equal("@lua/foo.lua:1", added)
  end)

  it("does not wait when the panel was already open", function()
    panel.wait_ready = function()
      error("should not wait")
    end
    panel.append = function()
      return true
    end

    oc.append()
  end)

  it("does nothing (and warns) without a running panel", function()
    panel.is_open = function()
      return false
    end
    panel.has_job = function()
      return false
    end
    local notified
    local real_notify = vim.notify
    vim.notify = function(msg)
      notified = msg
    end
    local added = false
    panel.append = function()
      added = true
      return true
    end

    local ok = oc.append()

    vim.notify = real_notify
    assert.is_false(ok)
    assert.is_false(added)
    assert.is_truthy(notified and notified:find("no running opencode panel", 1, true))
  end)

  it("does nothing when the context is empty", function()
    context.render = function()
      return ""
    end
    local added = false
    panel.append = function()
      added = true
      return true
    end

    assert.is_false(oc.append())
    assert.is_false(added)
  end)
end)
