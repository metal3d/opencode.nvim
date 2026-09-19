local oc = require("opencode")
local input = require("opencode.input")
local context = require("opencode.context")

describe("opencode.ask", function()
  local real

  before_each(function()
    real = {
      input = input.input,
      render = context.render,
      prompt = oc.prompt,
    }
    oc.prompt = function() end
  end)

  after_each(function()
    input.input = real.input
    context.render = real.render
    oc.prompt = real.prompt
  end)

  it("prefills the popup with the context reference", function()
    context.render = function()
      return "lua/foo.lua:L42:C5"
    end
    local prefilled
    input.input = function(default)
      prefilled = default
    end

    oc.ask()

    assert.are.equal("lua/foo.lua:L42:C5: ", prefilled)
  end)

  it("sends exactly what the popup returned", function()
    context.render = function()
      return "lua/foo.lua:L42:C5"
    end
    input.input = function(prefix, on_submit)
      on_submit(prefix .. "why does this fail?")
    end
    local sent
    oc.prompt = function(text)
      sent = text
    end

    oc.ask()

    assert.are.equal("lua/foo.lua:L42:C5: why does this fail?", sent)
  end)

  it("leaves the popup empty when there is no reference", function()
    context.render = function()
      return ""
    end
    local prefilled
    input.input = function(default, on_submit)
      prefilled = default
      on_submit("an open question")
    end
    local sent
    oc.prompt = function(text)
      sent = text
    end

    oc.ask()

    assert.are.equal("", prefilled)
    assert.are.equal("an open question", sent)
  end)

  it("captures the context before the popup opens", function()
    local captured_before_popup
    context.render = function()
      captured_before_popup = true
      return "ref"
    end
    input.input = function()
      -- If `render` ran here instead, a visual selection would be lost.
      assert.is_true(captured_before_popup)
    end

    oc.ask()

    assert.is_true(captured_before_popup)
  end)
end)
