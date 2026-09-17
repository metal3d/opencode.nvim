local client = require("opencode.client")

describe("client.stream", function()
  local real_system
  local real_server

  before_each(function()
    real_system = vim.system
    real_server = client.server
  end)

  after_each(function()
    vim.system = real_system
    client.set_server(real_server)
  end)

  it("forwards stdout data to on_data", function()
    client.set_server({ url = "http://test", password = "p" })
    local captured
    vim.system = function(_, opts, _)
      captured = opts
      return {}
    end

    local chunks = {}
    client.stream("/api/event", {
      on_data = function(chunk)
        chunks[#chunks + 1] = chunk
      end,
    })

    -- `vim.system` calls the stdout callback as `(err, data)`.
    captured.stdout(nil, "hello")
    captured.stdout(nil, "world")
    captured.stdout(nil, nil) -- end of stream

    assert.are.same({ "hello", "world" }, chunks)
  end)

  it("decodes JSON null object fields as nil", function()
    client.set_server({ url = "http://test", password = "p" })
    vim.system = function(_, _, on_exit)
      vim.schedule(function()
        on_exit({ code = 0, stdout = '{"cursor":{"next":null,"previous":null}}' })
      end)
      return {}
    end

    local got
    client.api("GET", "/x", nil, function(res)
      got = res
    end)
    vim.wait(1000, function()
      return got ~= nil
    end)

    assert.is_nil(got.data.cursor.next)
    assert.is_nil(got.data.cursor.previous)
  end)
end)
