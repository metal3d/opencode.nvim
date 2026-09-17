--- Minimal Neovim init used by the test suite (local runs and CI).
---
--- It intentionally loads nothing but this plugin and plenary.nvim, so tests
--- are isolated from the user's configuration. Plenary is located from
--- `$PLENARY_PATH` (set by the Makefile and CI), falling back to a conventional
--- local clone.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local plenary = vim.env.PLENARY_PATH or "/tmp/plenary"

vim.opt.runtimepath:prepend(plenary)
vim.opt.runtimepath:prepend(root)

-- Keep buffers loaded when switching files, and never write swap files.
vim.opt.hidden = true
vim.opt.swapfile = false
