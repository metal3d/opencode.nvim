--- Minimal floating input popup (no completion).
---
--- A single-line floating window anchored under the cursor, used by `ask()` to
--- collect a question about the current context. It intentionally has no
--- completion source.
local M = {}

--- Open the input popup.
---@param default string Text to prefill.
---@param on_submit fun(text: string) Called with the entered text on submit.
function M.input(default, on_submit)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  -- Keep completion plugins out of the popup.
  vim.b[buf].completion = false
  vim.b[buf].blink_cmp_disabled = true
  vim.b[buf].cmp_disabled = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })

  local width = math.max(40, math.min(90, vim.o.columns - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = " Ask OpenCode ",
    title_pos = "left",
    footer = " <CR> send  <Esc> cancel ",
    footer_pos = "right",
  })
  vim.wo[win].wrap = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].number = false
  vim.wo[win].cursorline = true
  vim.api.nvim_win_set_cursor(win, { 1, #default })
  vim.cmd("startinsert!")

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    close()
    if text:gsub("%s", "") ~= "" then
      on_submit(text)
    end
  end

  local opts = { buffer = buf }
  vim.keymap.set({ "i", "n" }, "<CR>", submit, vim.tbl_extend("force", opts, { desc = "OpenCode: send" }))
  vim.keymap.set({ "i", "n" }, "<C-c>", close, vim.tbl_extend("force", opts, { desc = "OpenCode: cancel" }))
  vim.keymap.set({ "i", "n" }, "<Esc>", close, vim.tbl_extend("force", opts, { desc = "OpenCode: cancel" }))
end

return M
