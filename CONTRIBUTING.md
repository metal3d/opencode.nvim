# Contributing

Thanks for taking an interest in opencode.nvim.

## Principles

- **Original work only.** This project is a clean-room rewrite that talks to
  OpenCode's public v2 API. Do not copy implementation code from any other
  OpenCode plugin or Neovim plugin.
- **Zero dependencies.** New functionality should fit within Neovim itself,
  `opencode` and `curl`.
- **English everywhere.** Comments, docs and user-facing messages in English.

## Development

```bash
# Type-check (requires lua-language-server and a Neovim runtime path)
lua-language-server --configpath .luarc.ci.json --check=.

# Check formatting (requires stylua)
stylua --check .

# Format in place
stylua .
```

## Project layout

See the "Layout" section of [README.md](./README.md). Public behaviour lives in
`lua/opencode/init.lua`; the panel and renderer are `panel.lua` and `render.lua`.

## Conventions

- Follow the existing module structure and naming.
- Keep `require` side-effect free — modules must load without doing work.
- Async work goes through `vim.system` (fast-event context) and must escape
  that context with `vim.schedule` before touching the Neovim API.
- Add or update `:checkhealth opencode` coverage when behaviour changes.

## Changes

Open a pull request targeting `main`. Keep changes focused and add a
`CHANGELOG.md` entry. Sign commits if you can.

## Reporting issues

Include:

- `:checkhealth opencode` output
- `opencode service status` / `opencode api get /api/info` output
- The Neovim and OpenCode versions you are running