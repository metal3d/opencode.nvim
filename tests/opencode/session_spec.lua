local client = require("opencode.client")
local config = require("opencode.config")
local session = require("opencode.session")

--- Replace `client.api` with a stub that pops canned responses in order and
--- records the calls. Responses are delivered synchronously (the real client
--- defers through `vim.schedule`, which tests do not need).
---@return table[] calls
local function stub_api(responses)
  local calls = {}
  client.api = function(method, path, body, cb)
    calls[#calls + 1] = { method = method, path = path, body = body }
    cb(table.remove(responses, 1) or {})
  end
  return calls
end

describe("session.ensure", function()
  local real_api

  before_each(function()
    real_api = client.api
    session.set_target(nil)
    vim.g.opencode_opts = nil
    config.opts = nil
  end)

  after_each(function()
    client.api = real_api
    session.set_target(nil)
    vim.g.opencode_opts = nil
    config.opts = nil
  end)

  it("adopts the most recently viewed session for the directory", function()
    stub_api({
      {
        data = {
          data = {
            { id = "ses_old", location = { directory = "/work" }, time = { viewed = 10 } },
            { id = "ses_new", location = { directory = "/work" }, time = { viewed = 20 } },
            { id = "ses_other", location = { directory = "/elsewhere" }, time = { viewed = 99 } },
          },
        },
      },
    })
    local got
    session.ensure("/work", function(res)
      got = res
    end)
    assert.are.equal("ses_new", got.session)
  end)

  it("creates a session when none matches the directory", function()
    local calls = stub_api({
      { data = { data = {} } },
      { data = { id = "ses_created" } },
    })
    local got
    session.ensure("/work", function(res)
      got = res
    end)
    assert.are.equal("ses_created", got.session)
    assert.are.equal(2, #calls)
    -- The list is filtered server-side by directory, so an older session for the
    -- project is found even if it is not in the global first page.
    assert.is_truthy(calls[1].path:find("directory=" .. vim.uri_encode("/work"), 1, true))
    assert.are.equal("POST", calls[2].method)
    assert.are.equal("/api/session", calls[2].path)
    assert.are.same({ location = { directory = "/work" } }, calls[2].body)
  end)

  it("always creates in 'new' mode", function()
    vim.g.opencode_opts = { session = { mode = "new" } }
    config.opts = nil
    local calls = stub_api({ { data = { id = "ses_fresh" } } })
    local got
    session.ensure("/work", function(res)
      got = res
    end)
    assert.are.equal("ses_fresh", got.session)
    assert.are.equal(1, #calls)
    assert.are.equal("POST", calls[1].method)
  end)

  it("keeps an explicitly set target", function()
    session.set_target("ses_manual")
    local calls = stub_api({})
    local got
    session.ensure("/work", function(res)
      got = res
    end)
    assert.are.equal("ses_manual", got.session)
    assert.are.equal(0, #calls)
  end)

  it("re-resolves when the working directory changes", function()
    stub_api({
      { data = { data = { { id = "ses_a", location = { directory = "/a" }, time = { viewed = 1 } } } } },
    })
    local first
    session.ensure("/a", function(res)
      first = res.session
    end)
    assert.are.equal("ses_a", first)

    -- Same directory: the cached target is reused without any API call.
    local cached_calls = stub_api({})
    local again
    session.ensure("/a", function(res)
      again = res.session
    end)
    assert.are.equal("ses_a", again)
    assert.are.equal(0, #cached_calls)

    -- Different directory: the stale target is dropped and re-resolved.
    local calls = stub_api({
      { data = { data = { { id = "ses_b", location = { directory = "/b" }, time = { viewed = 1 } } } } },
    })
    local other
    session.ensure("/b", function(res)
      other = res.session
    end)
    assert.are.equal("ses_b", other)
    assert.are.equal(1, #calls)
    assert.is_truthy(calls[1].path:find("directory=" .. vim.uri_encode("/b"), 1, true))
  end)

  it("keeps an explicitly chosen target across directories", function()
    session.set_target("ses_manual", "/a")
    local calls = stub_api({})
    local got
    session.ensure("/b", function(res)
      got = res
    end)
    assert.are.equal("ses_manual", got.session)
    assert.are.equal(0, #calls)
  end)

  it("propagates listing errors", function()
    stub_api({ { err = "boom" } })
    local got
    session.ensure("/work", function(res)
      got = res
    end)
    assert.are.equal("boom", got.err)
  end)
end)

describe("session.create", function()
  local real_api

  before_each(function()
    real_api = client.api
    session.set_target(nil)
  end)

  after_each(function()
    client.api = real_api
    session.set_target(nil)
  end)

  it("accepts an id wrapped in a data envelope", function()
    stub_api({ { data = { data = { id = "ses_wrapped" } } } })
    local got
    session.create("/work", function(res)
      got = res
    end)
    assert.is_nil(got.err)
    assert.are.equal("ses_wrapped", session.get_target())
  end)

  it("reports a response without an id", function()
    stub_api({ { data = {} } })
    local got
    session.create("/work", function(res)
      got = res
    end)
    assert.are.equal("create session response missing id", got.err)
  end)
end)

describe("session.prompt", function()
  it("errors when no session is targeted", function()
    session.set_target(nil)
    local got
    session.prompt("hello", {}, function(res)
      got = res
    end)
    assert.are.equal("no active session", got.err)
  end)
end)

describe("session.list", function()
  local real_api

  before_each(function()
    real_api = client.api
  end)

  after_each(function()
    client.api = real_api
  end)

  it("passes the directory filter and limit to the API", function()
    local calls = stub_api({ { data = { data = {} } } })
    session.list(function() end, { directory = "/home/me/proj", limit = 50 })
    assert.are.equal(1, #calls)
    assert.is_truthy(calls[1].path:find("directory=" .. vim.uri_encode("/home/me/proj"), 1, true))
    assert.is_truthy(calls[1].path:find("limit=50", 1, true))
  end)

  it("returns the pagination cursor", function()
    stub_api({ { data = { data = { { id = "ses_1" } }, cursor = { next = "abc" } } } })
    local got
    session.list(function(res)
      got = res
    end)
    assert.are.equal("abc", got.cursor and got.cursor.next)
  end)
end)

describe("session.list_all", function()
  local real_api

  before_each(function()
    real_api = client.api
  end)

  after_each(function()
    client.api = real_api
  end)

  it("follows cursor.next until the pages are exhausted", function()
    local pages = {
      { data = { data = { { id = "ses_1" }, { id = "ses_2" } }, cursor = { next = "c2" } } },
      { data = { data = { { id = "ses_3" } }, cursor = { next = nil } } },
    }
    local paths = {}
    client.api = function(_, path, _, cb)
      paths[#paths + 1] = path
      cb(table.remove(pages, 1))
    end

    local got
    session.list_all(function(res)
      got = res
    end)

    assert.are.equal(3, #got.data)
    assert.are.equal("ses_3", got.data[3].id)
    assert.are.equal(2, #paths)
    assert.is_truthy(paths[2]:find("cursor=" .. vim.uri_encode("c2"), 1, true))
  end)
end)

describe("session.matches", function()
  after_each(function()
    session.set_target(nil)
  end)

  it("aligns the target with its directory unless it is explicit", function()
    session.set_target(nil)
    assert.is_false(session.matches("/x"))

    session.set_target("ses_auto", "/a")
    session.explicit = false -- as if resolved by ensure()
    assert.is_true(session.matches("/a"))
    assert.is_false(session.matches("/b"))

    session.set_target("ses_manual", "/a")
    assert.is_true(session.matches("/b")) -- explicit targets are kept
  end)
end)

describe("session target invalidation", function()
  local real_api

  before_each(function()
    real_api = client.api
    session.set_target(nil)
  end)

  after_each(function()
    client.api = real_api
    session.set_target(nil)
  end)

  it("clears the target when the server replies 404", function()
    client.api = function(_, _, _, cb)
      cb({ err = "gone", status = 404 })
    end
    session.set_target("ses_dead")
    local got
    session.prompt("hi", {}, function(res)
      got = res
    end)
    assert.are.equal("gone", got.err)
    assert.is_nil(session.get_target())
  end)

  it("keeps the target on other errors", function()
    client.api = function(_, _, _, cb)
      cb({ err = "boom", status = 500 })
    end
    session.set_target("ses_alive")
    session.prompt("hi", {}, function() end)
    assert.are.equal("ses_alive", session.get_target())
  end)
end)
