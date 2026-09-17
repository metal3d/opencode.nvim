local oc = require("opencode")
local client = require("opencode.client")
local config = require("opencode.config")
local events = require("opencode.event")

local state = oc.state

--- Put every piece of connection/config state back to a clean slate.
local function reset()
  state.connected = false
  state.connecting = false
  state.pending = {}
  client.set_server(nil)
  client.tui = false
  vim.g.opencode_opts = nil
  config.opts = nil
  config.user = nil
end

describe("opencode.connect", function()
  local real

  before_each(function()
    real = {
      api = client.api,
      detect_tui = client.detect_tui,
      subscribe = events.subscribe,
      unsubscribe = events.unsubscribe,
    }
    reset()
  end)

  after_each(function()
    client.api = real.api
    client.detect_tui = real.detect_tui
    events.subscribe = real.subscribe
    events.unsubscribe = real.unsubscribe
    events.filter = nil
    reset()
  end)

  --- Install a client.api stub that captures the callback instead of answering,
  --- so the test can control when the connection resolves.
  ---@return fun(result: table) reply Call to answer the pending probe.
  local function hold_api()
    local captured
    client.api = function(_, _, _, cb)
      captured = cb
    end
    client.detect_tui = function(cb)
      cb(true)
    end
    events.subscribe = function() end
    config.setup({ server = { url = "http://test", password = "p" } })
    return function(res)
      captured(res)
    end
  end

  it("returns immediately when already connected", function()
    client.set_server({ url = "http://test", password = "p" })
    state.connected = true
    local called = false
    oc.connect(function(err)
      called = true
      assert.is_nil(err)
    end)
    assert.is_true(called)
  end)

  it("queues concurrent callbacks and resolves them all", function()
    local reply = hold_api()

    local r1, r2
    oc.connect(function(err)
      r1 = err
    end)
    assert.is_true(state.connecting)
    assert.are.equal(0, #state.pending)

    oc.connect(function(err)
      r2 = err
    end)
    assert.are.equal(1, #state.pending)

    reply({ data = {} })

    assert.is_nil(r1)
    assert.is_nil(r2)
    assert.is_false(state.connecting)
    assert.is_true(state.connected)
    assert.is_true(client.connected())
    assert.are.equal(0, #state.pending)
  end)

  it("clears the server and notifies every waiter when validation fails", function()
    local reply = hold_api()
    local unsubscribed = false
    events.unsubscribe = function()
      unsubscribed = true
    end

    local r1, r2
    oc.connect(function(err)
      r1 = err
    end)
    oc.connect(function(err)
      r2 = err
    end)

    reply({ err = "boom" })

    assert.are.equal("boom", r1)
    assert.are.equal("boom", r2)
    assert.is_false(state.connecting)
    assert.is_false(state.connected)
    assert.is_false(client.connected()) -- no stale, half-validated server
    assert.is_true(unsubscribed) -- stop the event stream/retries
  end)

  it("can retry after a failure", function()
    local reply = hold_api()
    local first
    oc.connect(function(err)
      first = err
    end)
    reply({ err = "down" })
    assert.are.equal("down", first)

    local second
    oc.connect(function(err)
      second = err
    end)
    assert.is_true(state.connecting)
    reply({ data = {} })
    assert.is_nil(second)
    assert.is_true(client.connected())
  end)
end)
