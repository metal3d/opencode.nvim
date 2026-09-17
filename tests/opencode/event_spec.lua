local events = require("opencode.event")

describe("event.ingest", function()
  local received

  before_each(function()
    received = {}
    events.buffer = ""
    events.on_event = function(ev)
      received[#received + 1] = ev
    end
  end)

  after_each(function()
    events.on_event = nil
    events.buffer = ""
    events.filter = nil
  end)

  it("dispatches a complete event", function()
    events.ingest('data: {"type":"a","value":1}\n\n')
    vim.wait(500, function()
      return #received == 1
    end)
    assert.are.equal(1, #received)
    assert.are.equal("a", received[1].type)
    assert.are.equal(1, received[1].value)
  end)

  it("reassembles an event split across chunks", function()
    events.ingest('data: {"type":"b"')
    assert.are.equal(0, #received)
    events.ingest("}\n\n")
    vim.wait(500, function()
      return #received == 1
    end)
    assert.are.equal("b", received[1].type)
  end)

  it("dispatches multiple events from one chunk", function()
    events.ingest('data: {"type":"c"}\n\ndata: {"type":"d"}\n\n')
    vim.wait(500, function()
      return #received == 2
    end)
    assert.are.equal(2, #received)
    assert.are.equal("c", received[1].type)
    assert.are.equal("d", received[2].type)
  end)

  it("ignores heartbeat comments", function()
    events.ingest(": heartbeat\n\n")
    vim.wait(100)
    assert.are.equal(0, #received)
  end)

  it("ignores malformed JSON", function()
    events.ingest("data: not json\n\n")
    vim.wait(100)
    assert.are.equal(0, #received)
  end)

  it("ignores events without a type", function()
    events.ingest('data: {"value":1}\n\n')
    vim.wait(100)
    assert.are.equal(0, #received)
  end)

  it("skips events rejected by the filter", function()
    events.filter = function(ev)
      return ev.type ~= "skip"
    end
    events.ingest('data: {"type":"keep"}\n\ndata: {"type":"skip"}\n\n')
    vim.wait(500, function()
      return #received >= 1
    end)
    vim.wait(100)
    assert.are.equal(1, #received)
    assert.are.equal("keep", received[1].type)
  end)
end)
