local config = require("opencode.config")

--- Reset every piece of configuration state the module caches.
local function reset()
  vim.g.opencode_opts = nil
  config.opts = nil
  config.user = nil
end

describe("config.get", function()
  after_each(reset)

  it("returns the defaults when nothing is configured", function()
    reset()
    local opts = config.get()
    assert.are.equal("right", opts.panel.position)
    assert.are.equal("session", opts.panel.open)
    assert.are.equal("recent", opts.session.mode)
    assert.is_true(opts.server.connect)
  end)

  it("merges vim.g.opencode_opts over the defaults", function()
    reset()
    vim.g.opencode_opts = { panel = { position = "left", size = 80 } }
    local opts = config.get()
    assert.are.equal("left", opts.panel.position)
    assert.are.equal(80, opts.panel.size)
    -- Untouched defaults survive the merge.
    assert.are.equal("session", opts.panel.open)
  end)

  it("caches the resolved options", function()
    reset()
    assert.is_true(config.get() == config.get())
  end)
end)

describe("config.setup", function()
  after_each(reset)

  it("merges options passed to setup() over the defaults", function()
    reset()
    config.setup({ panel = { position = "left", size = 70 } })
    local opts = config.get()
    assert.are.equal("left", opts.panel.position)
    assert.are.equal(70, opts.panel.size)
    assert.are.equal("session", opts.panel.open)
  end)

  it("lets setup() options win over vim.g.opencode_opts", function()
    reset()
    vim.g.opencode_opts = { panel = { position = "left", size = 40 } }
    config.setup({ panel = { size = 90 } })
    local opts = config.get()
    assert.are.equal(90, opts.panel.size) -- from setup()
    assert.are.equal("left", opts.panel.position) -- from the global
  end)

  it("invalidates the cache so later get() calls see new options", function()
    reset()
    local before = config.get()
    config.setup({ panel = { size = 33 } })
    local after = config.get()
    assert.is_true(before ~= after)
    assert.are.equal(33, after.panel.size)
  end)
end)
