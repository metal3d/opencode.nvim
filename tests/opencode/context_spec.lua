local ctx = require("opencode.context")

local tmp

--- Write a file under the per-test temp directory, open it and return its path.
local function new_file(name, lines)
  local path = tmp .. "/" .. name
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines or { "line" }, path)
  vim.cmd("edit! " .. vim.fn.fnameescape(path))
  return path
end

--- Plain substring test (avoids Lua pattern escaping for values containing `%`).
local function contains(haystack, needle)
  return haystack:find(needle, 1, true) ~= nil
end

describe("context", function()
  before_each(function()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    vim.fn.chdir(tmp)
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(tmp, "rf")
  end)

  describe("render", function()
    it("preserves percent signs in expanded values", function()
      new_file("diag.lua", { "local a = 1" })
      vim.diagnostic.set(vim.api.nvim_create_namespace("spec"), 0, {
        { lnum = 0, col = 0, end_lnum = 0, end_col = 5, message = "100% done, use %d", source = "spec" },
      })
      local out = ctx.render("Fix @diagnostics")
      assert.is_truthy(contains(out, "100% done"))
      assert.is_truthy(contains(out, "use %d"))
    end)

    it("does not shadow @buffers with @buffer", function()
      new_file("a.lua", { "a" })
      new_file("b.lua", { "b" })
      local out = ctx.render("@buffers")
      assert.is_truthy(contains(out, "a.lua"))
      assert.is_truthy(contains(out, "b.lua"))
      assert.is_falsy(contains(out, "a.luas"))
    end)

    it("leaves unknown placeholders intact", function()
      assert.are.equal("keep @nope", ctx.render("keep @nope"))
    end)

    it("does not match a placeholder inside a word", function()
      new_file("c.lua", { "x" })
      assert.are.equal("word @thisx here", ctx.render("word @thisx here"))
    end)

    it("keeps a literal @ before a placeholder", function()
      new_file("d.lua", { "x" })
      assert.are.equal("@d.lua:L1:C1", ctx.render("@@this"))
    end)

    it("drops a placeholder that resolves to nothing", function()
      vim.cmd("enew!")
      assert.are.equal("", ctx.render("@buffer"))
    end)

    it("references the cursor line for @this", function()
      new_file("h.lua", { "one", "two", "three" })
      vim.api.nvim_win_set_cursor(0, { 2, 1 })
      assert.are.equal("h.lua:L2:C2", ctx.render("@this"))
    end)

    it("references the visual marks for @selection", function()
      new_file("i.lua", { "one", "two", "three" })
      vim.api.nvim_buf_set_mark(0, "<", 1, 0, {})
      vim.api.nvim_buf_set_mark(0, ">", 3, 0, {})
      assert.are.equal("i.lua:L1:C1-L3:C1", ctx.render("@selection"))
    end)
  end)

  describe("format", function()
    it("builds a relative path with a line/column range", function()
      local path = new_file("sub/f.lua", { "x" })
      local ref = ctx.format({ path = path, from = { 3, 2 }, to = { 5, 7 } })
      assert.are.equal("sub/f.lua:L3:C2-L5:C7", ref)
    end)

    it("swaps an inverted range", function()
      local path = new_file("g.lua", { "x" })
      local ref = ctx.format({ path = path, from = { 9, 1 }, to = { 4, 1 } })
      assert.are.equal("g.lua:L4:C1-L9:C1", ref)
    end)

    it("omits the column when only lines are given", function()
      local path = new_file("lines.lua", { "x" })
      assert.are.equal("lines.lua:L2-L4", ctx.format({ path = path, from = { 2 }, to = { 4 } }))
    end)

    it("falls back to inline text when the backing file is gone", function()
      local path = tmp .. "/vanished.lua"
      vim.fn.writefile({ "line one", "line two" }, path)
      vim.cmd("edit! " .. vim.fn.fnameescape(path))
      vim.fn.delete(path)
      assert.are.equal("line one\nline two", ctx.format({ buf = 0 }))
    end)

    it("returns an absolute path outside the working directory", function()
      local outside = vim.fn.tempname() .. ".lua"
      vim.fn.writefile({ "x" }, outside)
      assert.are.equal(outside .. ":L1", ctx.format({ path = outside, from = { 1 } }))
      vim.fn.delete(outside)
    end)

    it("matches a file reached through a different symlink than the cwd", function()
      local real = tmp .. "/real"
      vim.fn.mkdir(real, "p")
      vim.fn.writefile({ "x" }, real .. "/f.lua")
      local link = tmp .. "/link"
      vim.uv.fs_symlink(real, link)

      vim.fn.chdir(real)
      vim.cmd("edit! " .. vim.fn.fnameescape(link .. "/f.lua"))
      assert.are.equal("f.lua", ctx.format({ buf = 0 }))
    end)

    it("returns nil for a missing file when there is no buffer to fall back on", function()
      assert.is_nil(ctx.format({ path = tmp .. "/nope.lua", from = { 1 } }))
    end)
  end)
end)
