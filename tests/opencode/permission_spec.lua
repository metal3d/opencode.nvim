local client = require("opencode.client")
local session = require("opencode.session")
local permission = require("opencode.permission")

describe("permission.prompt_pending", function()
  local real

  before_each(function()
    real = {
      api = client.api,
      select = vim.ui.select,
      reply = permission.reply,
      notify = vim.notify,
    }
    session.set_target("ses_test")
  end)

  after_each(function()
    client.api = real.api
    vim.ui.select = real.select
    permission.reply = real.reply
    vim.notify = real.notify
    session.set_target(nil)
  end)

  --- Make permission.list resolve with the given requests.
  local function given_requests(requests)
    client.api = function(_, _, _, cb)
      cb({ data = { data = requests } })
    end
  end

  --- Capture vim.ui.select prompts instead of showing them.
  local function capture_prompts()
    local prompts = {}
    vim.ui.select = function(items, opts, cb)
      prompts[#prompts + 1] = { items = items, opts = opts, cb = cb }
    end
    return prompts
  end

  it("surfaces requests one at a time and replies in order", function()
    given_requests({
      { id = "per_1", action = "edit", resources = { "a.lua" } },
      { id = "per_2", action = "bash", resources = { "ls" } },
    })
    local prompts = capture_prompts()
    local replies = {}
    permission.reply = function(id, decision, cb)
      replies[#replies + 1] = { id = id, decision = decision }
      cb({})
    end

    permission.prompt_pending()

    assert.are.equal(1, #prompts) -- only the first request is asked
    assert.are.same({ "once", "always", "reject" }, prompts[1].items)

    prompts[1].cb("once")
    assert.are.equal(1, #replies)
    assert.are.equal("per_1", replies[1].id)
    assert.are.equal("once", replies[1].decision)
    assert.are.equal(2, #prompts) -- the second is asked only now

    prompts[2].cb("reject")
    assert.are.equal(2, #replies)
    assert.are.equal("per_2", replies[2].id)
    assert.are.equal(2, #prompts) -- no more pending
  end)

  it("stops the run when the user cancels", function()
    given_requests({
      { id = "per_1", action = "edit", resources = {} },
      { id = "per_2", action = "bash", resources = {} },
    })
    local prompts = capture_prompts()
    local replies = 0
    permission.reply = function(_, _, cb)
      replies = replies + 1
      cb({})
    end

    permission.prompt_pending()
    assert.are.equal(1, #prompts)

    prompts[1].cb(nil) -- Escape
    assert.are.equal(0, replies)
    assert.are.equal(1, #prompts) -- the second is never asked
  end)

  it("reports when nothing is pending", function()
    given_requests({})
    local notified
    vim.notify = function(msg)
      notified = msg
    end
    permission.prompt_pending()
    assert.is_truthy(notified and notified:find("no pending", 1, true))
  end)
end)
