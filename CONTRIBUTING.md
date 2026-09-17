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
# Type-check the plugin (requires lua-language-server and a Neovim runtime path)
lua-language-server --configpath .luarc.ci.json --check=.

# Check formatting (requires stylua)
stylua --check .

# Format in place
stylua .
```

CI runs `stylua --check .` on every push and pull request (see
`.github/workflows/lint.yml`).

### Tests

The suite uses [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) as a
test-only dependency and runs headless. Point `PLENARY` at a local clone:

```bash
make test PLENARY=~/.local/share/nvim/lazy/plenary.nvim

# A single spec file
make test-file FILE=tests/opencode/context_spec.lua PLENARY=~/.local/share/nvim/lazy/plenary.nvim
```

Specs live in `tests/opencode/*_spec.lua` and are run by
`.github/workflows/test.yml` against Neovim 0.11, stable and nightly. Tests must
not touch the network or a real OpenCode server: stub `client.api` (see
`tests/opencode/session_spec.lua`) and drive `event.ingest` directly
(`tests/opencode/event_spec.lua`).

## Project layout

See the "Layout" section of [README.md](./README.md). Public behaviour lives in
`lua/opencode/init.lua`; the panel is `panel.lua` and prompt context is
`context.lua`.

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