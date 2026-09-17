local client = require("opencode.client")
local session = require("opencode.session")
local diff = require("opencode.diff")

describe("diff.preview", function()
  local real_api

  before_each(function()
    real_api = client.api
    session.set_target("ses_test")
    client.api = function(_, _, _, cb)
      cb({
        data = {
          data = {
            {
              file = "a.lua",
              status = "modified",
              additions = 2,
              deletions = 1,
              patch = "@@ -1 +1 @@\n-old\n+new\n",
            },
          },
        },
      })
    end
  end)

  after_each(function()
    client.api = real_api
    session.set_target(nil)
    vim.cmd("silent! %bwipeout!")
  end)

  it("renders a readable summary instead of fake diff markers", function()
    diff.preview()
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert.is_truthy(text:find("additions: 2, deletions: 1", 1, true))
    assert.is_falsy(text:find("+2 -1", 1, true))
    assert.are.equal("diff", vim.bo.filetype)
  end)
end)
