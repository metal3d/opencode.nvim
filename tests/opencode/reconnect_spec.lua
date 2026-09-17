local client = require("opencode.client")
local events = require("opencode.event")

describe("event.subscribe", function()
  local real_stream
  local streams

  before_each(function()
    real_stream = client.stream
    streams = {}
    client.stream = function(path, opts)
      streams[#streams + 1] = { path = path, opts = opts }
      return {}
    end
    events.unsubscribe()
    events.buffer = ""
    events.retry_initial_ms = 10
    events.retry_max_ms = 1000
  end)

  after_each(function()
    events.unsubscribe()
    client.stream = real_stream
    events.retry_initial_ms = 1000
    events.retry_max_ms = 30000
    events.retry_ms = 1000
    events.buffer = ""
    events.on_event = nil
  end)

  local function wait_streams(n)
    vim.wait(1500, function()
      return #streams >= n
    end)
  end

  it("subscribes once and is idempotent while wanted", function()
    events.subscribe()
    events.subscribe()
    assert.are.equal(1, #streams)
    assert.is_true(events.subscribed)
    assert.is_true(events.streaming)
  end)

  it("reconnects after the stream drops", function()
    events.subscribe()
    assert.are.equal(1, #streams)

    streams[1].opts.on_done(false)
    assert.is_false(events.streaming)

    wait_streams(2)
    assert.are.equal(2, #streams)
    assert.is_true(events.streaming)
  end)

  it("drops a partial event when reconnecting", function()
    events.subscribe()
    events.ingest("data: partial") -- no blank line: stays buffered
    assert.are.equal("data: partial", events.buffer)

    streams[1].opts.on_done(false)
    wait_streams(2)
    assert.are.equal("", events.buffer)
  end)

  it("stops reconnecting after unsubscribe()", function()
    events.subscribe()
    events.unsubscribe()
    streams[1].opts.on_done(false)

    vim.wait(200, function()
      return #streams > 1
    end)
    assert.are.equal(1, #streams)
    assert.is_false(events.subscribed)
  end)

  it("backs off exponentially and resets when data arrives", function()
    events.subscribe()
    events.retry_initial_ms = 10

    streams[1].opts.on_done(false)
    assert.are.equal(20, events.retry_ms) -- doubled from the initial delay

    wait_streams(2)
    streams[2].opts.on_data('data: {"type":"a"}\n\n')
    assert.are.equal(10, events.retry_ms) -- healthy stream resets the backoff
  end)
end)
