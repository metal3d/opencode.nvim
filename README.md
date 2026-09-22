# opencode.nvim

<p align="center">
  <a href="https://github.com/metal3d/opencode.nvim/actions/workflows/test.yml"><img src="https://github.com/metal3d/opencode.nvim/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
  <a href="https://github.com/metal3d/opencode.nvim/actions/workflows/lint.yml"><img src="https://github.com/metal3d/opencode.nvim/actions/workflows/lint.yml/badge.svg" alt="Lint"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <a href="https://neovim.io"><img src="https://img.shields.io/badge/Neovim-%E2%89%A5%200.11-57A143?logo=neovim&logoColor=white" alt="Neovim ≥ 0.11"></a>
</p>

A Neovim plugin that opens the **real [OpenCode](https://opencode.ai/) application**
in a side terminal and drives it over OpenCode's **v2 HTTP API** (REST + SSE).

One keymap opens the actual `opencode` TUI in a split — left or right — while the
plugin's prompts and reviews land in the running session, so they reach whatever
tab you are looking at. No embedded TUI reimplementation, no legacy `/tui/*`
endpoints, no Lua dependencies.

> **Using OpenCode V1?** This plugin targets the v2 API and will not work on V1.
> Use [nickjvandyke/opencode.nvim](https://github.com/nickjvandyke/opencode.nvim)
> instead.
>
> **OpenCode itself is © its authors.** See the end of this document for how this
> plugin relates to other Neovim integrations.

## Features

- **OpenCode on the side** — a keymap toggles a split (left or right) running
  the real `opencode` app in a Neovim terminal. The instance stays alive between
  toggles.
- **Prompts land in the active tab** — review/fix/explain inject into the running
  TUI terminal, so they target whatever tab you are looking at.
- **Drive via the v2 API** — session discovery, events, permissions and diffs use
  the OpenCode HTTP API.
- **Review / fix / explain** — send `@this` / `@diagnostics` prompts with one
  key.
- **Editor context placeholders** — `@this`, `@selection`, `@buffer`, `@file`,
  `@diagnostics`.
- **Live events** — subscribes to the SSE feed and dispatches
  `OpencodeEvent:<type>` User autocmds.
- **Permissions** — surfaces OpenCode permission requests and sends your
  decision back to the API.
- **Session diff review** — inspect the agent's file changes.
- **Zero dependencies** — only the `opencode` CLI and `curl` are required.

## Requirements

- Neovim ≥ 0.11
- [OpenCode](https://opencode.ai/) v2 CLI
- `curl`

## Installation

With [vim.pack](https://neovim.io/doc/user/pack.html#vim.pack):

```lua
vim.pack.add({
  { src = "https://github.com/metal3d/opencode.nvim" },
})

---@type opencode.Opts
require("opencode").setup({
  -- your options here (see Configuration)
})
```

With [lazy.nvim](https://github.com/folke/lazy.nvim), pass the options through
`opts`: lazy.nvim calls `require("opencode").setup(opts)` for you.

```lua
{
  "metal3d/opencode.nvim",
  event = "VeryLazy",
  ---@type opencode.Opts
  opts = {
    -- opt into the recommended <leader>oc* keymaps (see Keymaps)
    keys = "recommended",
  },
}
```

If a spec also provides a `config` function, lazy.nvim no longer calls
`setup()` automatically — call it yourself inside `config`:

```lua
config = function(_, opts)
  require("opencode").setup(opts)
end,
```

Run `:checkhealth opencode` after setup.

## Configuration

Configure the plugin with `require("opencode").setup(opts)`. Options are merged
over the defaults in `lua/opencode/config.lua`. The legacy global
`vim.g.opencode_opts` is still honoured (defaults < global < `setup(opts)`), so
existing configs keep working.

```lua
require("opencode").setup({
  server = {
    username = nil,  -- basic-auth user (defaults to "opencode")
    url = nil,       -- explicit server URL; nil = auto-discover
    password = nil,  -- read from service.json when nil
    connect = true,  -- subscribe to the server's events
    start = nil,     -- custom boot function; nil = `opencode service start`
  },
  panel = {
    size = 60,       -- panel width in columns
    position = "right", -- "right" | "left"
    open = "session", -- "session" full TUI in the active session;
                      -- "home" default dashboard;
                      -- "mini" minimal interface (least chrome);
                      -- "continue" full TUI, last session
    insert = true,   -- enter Terminal mode when the panel gains focus
    -- Buffer-local Terminal-mode mappings for the panel only. Default maps
    -- <C-w> to the window prefix so <C-w><arrow> works from Terminal mode.
    terminal_keys = { ["<C-w>"] = "<C-\\><C-n><C-w>" },
  },
  prompts = {
    review = "Review @this for correctness and readability.",
    fix = "Fix @diagnostics",
    explain = "Explain @this and its context.",
    document = "Add comments documenting @this.",
    test = "Add tests for @this.",
    commit = "Propose a commit plan for the current changes and wait for my confirmation before committing.",
  },
  -- Opt into the recommended <leader>oc* set with the string "recommended",
  -- or map an lhs to a function / built-in action id:
  --   keys = "recommended",
  --   keys = { ["<leader>ocs"] = "session" },
  keys = {},
  session = {
    mode = "recent", -- "recent" adopts the latest session; "new" creates one
  },
  events = {
    reload = true,   -- set vim.o.autoread so edited buffers reload
  },
})
```

### Keymaps

Two ways to bind keys:

**Recommended set** — `keys = "recommended"` installs a `<leader>oc*` namespace:

| lhs | action |
| --- | --- |
| `<leader>oct` | toggle the panel |
| `<leader>oca` | ask about the context |
| `<leader>ocA` | add the context to the prompt (no submit) |
| `<leader>ocr` | review `@this` |
| `<leader>ocf` | fix `@diagnostics` |
| `<leader>oce` | explain `@this` |
| `<leader>ocu` | audit `@this` |
| `<leader>ocs` | switch session |
| `<leader>occ` | action palette |
| `<leader>ocd` | session diff |
| `<leader>ocg` | propose a commit plan |

When [which-key.nvim](https://github.com/folke/which-key.nvim) is installed,
`keys = "recommended"` also names the shared `<leader>oc` prefix, so the popup
shows `+opencode` for `c` instead of leaving it unlabelled. This is a no-op when
which-key is absent (or older than v3, which introduced `add`).

**Custom set** — `keys` maps a left-hand side to a Lua function or a built-in
action id (invoked as `require("opencode").command(id)`):

```lua
keys = {
  ["<leader>on"] = function() require("opencode").prompt("@this") end,
  ["<leader>os"] = "session",
}
```

Valid action ids: `toggle`, `ask`, `review`, `audit`, `fix`, `explain`, `commit`,
`session`, `diff`, `permissions`, `compact`, `interrupt`.

## Usage

| `:Opencode` command | Description                            |
| ------------------- | -------------------------------------- |
| `:OpencodeToggle`   | Open / close the side panel            |
| `:OpencodeAsk`      | Open a prompt popup prefilled with the context |
| `:OpencodeAdd`      | Add the current context to the prompt (no submit) |
| `:OpencodeReview`   | Send "Review @this"                    |
| `:OpencodeFix`      | Send "Fix @diagnostics"                |
| `:OpencodeExplain`  | Send "Explain @this"                   |
| `:OpencodeCommit`   | Propose a commit plan and wait for confirmation |
| `:OpencodeCommand`  | Open the action palette                |
| `:OpencodeSession`  | Switch the active session              |
| `:OpencodePermissions` | Surface pending permissions        |
| `:OpencodeDiff`     | View the session diff                  |
| `:checkhealth opencode` | Run the health check              |

### Using the panel

The panel is a real Neovim terminal running the `opencode` TUI, so it has its own
Terminal mode:

- **Typing works immediately.** Focusing the panel enters Terminal mode for you
  (`panel.insert`), so there is no `i` to press first.
- **`<C-w><arrow>` navigates windows** like in any other buffer. `<C-w>` is
  mapped buffer-locally to the usual window prefix, so it only affects the
  panel's terminal — never other terminals or plugins. A raw `<C-w>` still
  reaches OpenCode with `<C-\><C-w>`.
- **`<Esc>` stays with OpenCode** (it interrupts the running LLM). Neovim's own
  "leave Terminal mode" is therefore `<C-\><C-n>`; you can bind something easier
  through `panel.terminal_keys`:

  ```lua
  require("opencode").setup({
    panel = { terminal_keys = { ["<C-q>"] = "<C-\\><C-n>" } },
  })
  ```

> On an AZERTY keyboard, the key labelled `<C-\>` often sends `<C-_>`, which
> LazyVim maps to its own floating terminal. That is unrelated to this plugin.

### API (`require("opencode")`)

- `toggle()` — toggle the OpenCode terminal on the side.
- `ask()` — open a floating input popup, prefilled with the current context
  reference. Keep it to ask about the context, clear it for an open question.
  The popup is editable and what you see is what is sent.
- `append([placeholders])` — type the rendered context at the running TUI
  prompt's cursor **without submitting it**, so you can finish the sentence
  before sending. Requires a live panel (the v2 API cannot fill a prompt without
  processing it). Defaults to `@this`; warns and does nothing without one.
- `prompt(text)` — send a prompt, expanding context placeholders.
- `review()` / `fix()` / `explain()` — run a named prompt.
- `send()` — send the current line.
- `command([id])` — action palette, or run an action by id.
- `session()` — list and switch sessions.
- `diff()` / `permissions()` — session diff / pending permissions.
- `compact()` / `interrupt()` — session controls.
- `statusline()` — short status text for statuslines.
- `format(entry)` — format a `{ path, from, to }` location as a reference.
- `operator(text)` — prompt over a motion/selection with dot-repeat support.
- `setup(opts)` — configure the plugin (lazy.nvim calls this automatically when
  a spec uses `opts`).

### Contexts

Placeholders are expanded into **location references** when a prompt is sent.
OpenCode gathers the file content from disk, so save your buffers first.

| Placeholder     | Expands to                                                       |
| --------------- | ---------------------------------------------------------------- |
| `@this`         | Selection if any, else the cursor position                       |
| `@selection`    | The current visual selection                                     |
| `@buffer`       | The current buffer                                               |
| `@buffers`      | Every listed buffer                                              |
| `@file`         | The current file                                                 |
| `@diagnostics`  | Diagnostics in the buffer (or selection) as a reference list     |

A reference looks like `lua/opencode/init.lua:L10:C1-L25` (relative to the
working directory), which OpenCode resolves against the filesystem.

`require("opencode").format({ path = ..., from = { line, col }, to = { line } })`
produces the same references for integrations (pickers, etc.).

### Events

The plugin subscribes to OpenCode's SSE feed and re-emits events as User
autocmds:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent:*",
  callback = function(args)
    local event = args.data.event -- { type, data, ... }
    vim.notify(vim.inspect(event))
  end,
})
```

## How it connects

OpenCode v2 runs a background service whose address and generated password are
written to `service.json` (in `$XDG_STATE_HOME/opencode` or
`~/.local/state/opencode`). The plugin reads that registration and authenticates
every request with HTTP basic auth. If no registration exists, it starts the
service with `opencode service start`.

### Targeting the active tab

OpenCode exposes **no API for the TUI's active tab**, and the legacy `/tui/*`
control endpoints are absent from OpenCode v2.0.x. So instead of sending prompts
through the HTTP API (which targets one specific session), the plugin **injects
them into the running TUI's terminal**. The text is written to the terminal pty
and submitted, so it always lands in the **tab the user is looking at**.

If no local TUI terminal is available, it falls back to `/tui/append-prompt`
(when the server exposes it) and finally to the v2 API targeting the session the
plugin owns (`session.mode`).

### Reloading edits

When OpenCode emits a file event, the plugin reloads the matching buffer: it
listens for `OpencodeEvent:filesystem.changed` / `file.edited` on the SSE feed
and runs `:checktime`. `vim.o.autoread` is also set unless `events.reload` is
disabled.

OpenCode v2.0.x does not emit a file event for every edit (shell tool writes,
for example), so a buffer may occasionally need a manual `:e!`.

Unsaved buffers are never overwritten — save or discard first.

## Layout

```
plugin/opencode.lua      startup wiring: user commands, reload
lua/opencode/            plugin implementation
  init.lua               public API
  config.lua             defaults + option merge
  client.lua             async curl client (vim.system), auth, SSE
  discovery.lua          service.json reading / service start
  session.lua            session targeting, prompt, interrupt, compact
  context.lua            placeholder expansion
  panel.lua              side terminal (real OpenCode app)
  event.lua              SSE pipeline + OpencodeEvent autocmds
  permission.lua         permission request handling
  diff.lua               session diff review
  bindings.lua           recommended keymaps
  health.lua             :checkhealth
  util.lua               dependency-free helpers
tests/                   plenary-based test suite (`make test`)
  minimal_init.lua       isolated init used by the runner
  opencode/*_spec.lua    specs
.github/workflows/       CI (tests on Neovim 0.11 / stable / nightly)
```

## Relationship with `nickjvandyke/opencode.nvim`

This plugin is original work and is **not** a fork of
[nickjvandyke/opencode.nvim](https://github.com/nickjvandyke/opencode.nvim).
Nick van Dyke's project came first, and it is the reason the author of this one
started driving OpenCode from Neovim at all. It is mature, widely used, and it
deserves the success it has. This plugin stands on that work with a lot of
gratitude — they are not rivals, they are two points of view on the same idea.

### Why a separate plugin?

The two projects share a lot: context expansion, `ask`/`prompt`, events,
permissions, and a terminal running the real OpenCode. The difference is **the
integration model**, not the intent.

`nickjvandyke/opencode.nvim` builds on the `snacks.nvim` ecosystem —
`snacks.input` for prompts, `snacks.picker` for menus, `snacks.terminal` for the
server. That is a genuine strength, and it is also an opinionated dependency: it
shapes the whole experience around snacks.

This one takes the opposite bet: **no Lua dependencies**. Prompts use a small
built-in popup, menus go through `vim.ui.select`, and the terminal is spawned
directly with `jobstart`. Behaviour stays explicit and easy to reason about, at
the cost of the polish a shared UI ecosystem provides.

Neither approach is better; they disagree about what a Neovim plugin should
depend on. This one is the author's own reading of how that integration should
feel — not a claim that Nick's got it wrong.

### Why not merge the two?

Because the two codebases rest on incompatible foundations — not on a
disagreement a pull request could settle. `nickjvandyke/opencode.nvim` is
organised around the snacks input/picker/terminal APIs and their conventions;
this one deliberately avoids them and ships its own I/O. Reconciling that would
mean rewriting one of the two, which is exactly what writing a separate plugin
is.

This is not a replacement and not a fork. If anything, the cleanest outcome
would have been for both ideas to live in one place — it just isn't possible
without discarding one of the two foundations, and that is nobody's fault. Each
project keeps its own path.

> **Using OpenCode V1?**
> [nickjvandyke/opencode.nvim](https://github.com/nickjvandyke/opencode.nvim) is
> the one you want. This plugin targets the OpenCode v2 API and will not work on
> V1.

## License

[MIT](./LICENSE) © metal3d 2026.

See [CONTRIBUTING.md](./CONTRIBUTING.md) and [CHANGELOG.md](./CHANGELOG.md).
