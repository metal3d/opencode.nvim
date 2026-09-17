local input = require("opencode.input")

describe("input.input", function()
  local win

  after_each(function()
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    win = nil
    vim.cmd("silent! only!")
  end)

  it("cancels on <Esc> in both normal and insert modes", function()
    input.input("", function() end)
    win = vim.api.nvim_get_current_win()
    assert.is_true(vim.fn.maparg("<Esc>", "n") ~= "")
    assert.is_true(vim.fn.maparg("<Esc>", "i") ~= "")
  end)

  it("submits the entered text on <CR>", function()
    local submitted
    input.input("", function(text)
      submitted = text
    end)
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    assert.are.equal("hello", submitted)
  end)
end)
