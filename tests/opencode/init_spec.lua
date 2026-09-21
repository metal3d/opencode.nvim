local oc = require("opencode")
local config = require("opencode.config")

--- Delete a mapping from both normal and visual modes, ignoring "no such mapping".
local function del(lhs)
  for _, mode in ipairs({ "n", "x" }) do
    pcall(vim.keymap.del, mode, lhs)
  end
end

describe("opencode.setup", function()
  local plug = "<Plug>(opencode-test-action)"
  local leader_maps = { ",occ", ",oct", ",oca", ",ocr", ",ocf", ",oce", ",ocu", ",ocs", ",ocd", ",ocg" }

  after_each(function()
    del(plug)
    for _, lhs in ipairs(leader_maps) do
      del(lhs)
    end
    vim.g.mapleader = nil
    vim.g.opencode_opts = nil
    config.opts = nil
    config.user = nil
    package.loaded["which-key"] = nil
  end)

  it("resolves options through config.get()", function()
    oc.setup({ panel = { size = 55 } })
    assert.are.equal(55, config.get().panel.size)
  end)

  it("binds the keys from opts", function()
    oc.setup({ keys = { [plug] = "review" } })
    assert.is_true(vim.fn.maparg(plug, "n") ~= "")
  end)

  it("accepts a callable key action", function()
    oc.setup({ keys = { [plug] = function() end } })
    assert.is_true(vim.fn.maparg(plug, "x") ~= "")
  end)

  it("installs the recommended <leader>oc* keymaps", function()
    vim.g.mapleader = ","
    oc.setup({ keys = "recommended" })
    assert.is_true(vim.fn.maparg(",occ", "n") ~= "") -- action palette
    assert.is_true(vim.fn.maparg(",oct", "n") ~= "")
    assert.is_true(vim.fn.maparg(",oca", "x") ~= "")
    assert.is_true(vim.fn.maparg(",ocr", "x") ~= "")
    assert.is_true(vim.fn.maparg(",ocd", "n") ~= "")
    assert.is_true(vim.fn.maparg(",ocg", "n") ~= "") -- propose a commit
  end)

  it("names the <leader>oc prefix as a which-key group", function()
    vim.g.mapleader = ","
    local specs = {}
    package.loaded["which-key"] = {
      add = function(spec)
        specs[#specs + 1] = spec
      end,
    }
    oc.setup({ keys = "recommended" })
    assert.are.equal("<leader>oc", specs[1][1][1])
    assert.are.equal("opencode", specs[1][1].group)
  end)

  it("leaves which-key untouched when it is not installed", function()
    vim.g.mapleader = ","
    package.loaded["which-key"] = nil
    assert.has_no.errors(function()
      oc.setup({ keys = "recommended" })
    end)
  end)
end)

describe("opencode.commit", function()
  it("ships a default commit prompt", function()
    assert.is_truthy(config.defaults.prompts.commit)
  end)

  it("routes the commit action to commit()", function()
    local real = oc.commit
    local called = false
    oc.commit = function()
      called = true
    end
    oc.command("commit")
    oc.commit = real
    assert.is_true(called)
  end)
end)

describe("opencode.statusline", function()
  local session = require("opencode.session")
  local client = require("opencode.client")
  local state = oc.state

  after_each(function()
    state.connected = false
    client.set_server(nil)
    session.set_target(nil)
  end)

  it("is empty when disconnected", function()
    state.connected = false
    assert.are.equal("", oc.statusline())
  end)

  it("reports connecting while no target matches the cwd", function()
    state.connected = true
    client.set_server({ url = "http://x", password = "p" })
    session.set_target(nil)
    assert.are.equal("opencode:connecting", oc.statusline())
  end)

  it("is 'opencode' once connected and targeted", function()
    state.connected = true
    client.set_server({ url = "http://x", password = "p" })
    session.set_target("ses_x", vim.fn.getcwd())
    assert.are.equal("opencode", oc.statusline())
  end)
end)
