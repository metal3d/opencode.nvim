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
> instead — it supports v2 on its `main` branch.
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
`opts`: lazy.nvim calls `require("opencode").setup(opts)` for you. Drop this in
`~/.config/nvim/lua/plugins/opencode.lua` — files under `lua/plugins/` are Lua
modules, so they must *return* the spec:

```lua
return {
  "metal3d/opencode.nvim",
  event = "VeryLazy",
  ---@type opencode.Opts
  opts = {
    -- opt into the recommended <leader>oc* keymaps (see Keymaps)
    keys = "recommended",
  },
}
```

If you embed the spec inline in an existing list (for example inside the
`plugins` table of your lazy.nvim setup), just drop the leading `return` —
lazy.nvim accepts the plain `{ ... }` table there.

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
    audit = "Audit @this for bugs, edge cases and security issues.",
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
- **The usual `<C-w>` prefix works**, so `<C-w><arrow>`, `<C-w>w`, `<C-w>h/j/k/l`,
  `<C-w>s`… take you to other windows and buffers exactly like in any other
  buffer. `<C-w>` is remapped buffer-locally, so it only affects the panel's
  terminal — never other terminals or plugins. A raw `<C-w>` still reaches
  OpenCode with `<C-\><C-w>`.
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

OpenCode exposes **no API for the TUI's active tab**, and several tabs — each
with its own session — can be open on the same project. The API can only target
a session id: `/api/session/active` lists sessions that are *processing*, not the
one you are looking at. So the plugin **types prompts into the running TUI** and
submits them there, so they always land in the **active OpenCode tab**.

If no local TUI terminal is available, it falls back to the v2 API targeting the
session the plugin owns (`session.mode`).

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

The two projects share a lot — context expansion, `ask`/`prompt`, events,
permissions, the v2 HTTP API, and a terminal running the real OpenCode. They
differ in **how a prompt is delivered**, and that one choice shapes the rest.

`nickjvandyke/opencode.nvim` sends prompts through the HTTP API, which targets a
session. This one types them into the running TUI, so they land in the **active
OpenCode tab** — the one you are looking at. That matters when several tabs
(hence several sessions) are open for the same project: the API has no notion of
the focused tab, while the TUI does. It is also what makes `append()` possible,
pre-filling a prompt without submitting it, which the v2 API cannot do since it
processes whatever it receives.

#### At a glance

Neither project is a subset of the other; they simply make different bets.

| | [`nickjvandyke/opencode.nvim`](https://github.com/nickjvandyke/opencode.nvim) | this plugin |
| --- | --- | --- |
| Integration model | real OpenCode TUI, driven over the HTTP API | real OpenCode TUI, driven by typing into it |
| Prompt delivery | HTTP API, targeting a session | typed into the running TUI, targeting the active OpenCode tab |
| Pre-fill without sending | not offered | `append()` |
| Side terminal | delegated to your own `server.start` (default `term://opencode`; snacks.terminal, etc. are examples) | built in: position, size, open mode, auto Terminal mode, full `<C-w>` window prefix |
| Server | any local or remote server via `server.url` (string or function) | discovered local service, or an explicit `server.url`; connecting to other servers is planned |
| Contexts | `@this` `@buffer` `@buffers` `@diagnostics` `@marks` `@quickfix` `@visible` | `@this` `@selection` `@buffer` `@buffers` `@file` `@diagnostics` |
| Named prompts | diagnostics, document, explain, fix, implement, optimize, review, test | review, audit, fix, explain, document, test, commit |
| Diagnostics | `@diagnostics` context + `fix` prompt | `@diagnostics` context + `fix` prompt |
| OpenCode commands | runs registered commands | action palette |
| Edit review | side-by-side `diffpatch`, accept/reject whole or per hunk | read-only session diff preview |
| Ask input | `vim.ui.input`, optional snacks enhancements | built-in floating popup |
| Menus | `vim.ui.select`, optional snacks.picker | `vim.ui.select` |
| Events | `OpencodeEvent:*` autocmds | same, filtered to the current directory |
| Required Lua dependencies | none (snacks optional) | none |
| OpenCode version | v2 on `main`; latest release targets v1 | v2 |

Neither approach is better; they make different trade-offs around targeting and
control. This one is the author's own reading of how that integration should
feel — not a claim that Nick's got it wrong.

### Why not merge the two?

Because the two codebases make incompatible bets about how a prompt reaches
OpenCode. `nickjvandyke/opencode.nvim` delivers it through the HTTP API, which
targets a session; this one types it into the running TUI, which targets the
**active OpenCode tab** and keeps the pre-fill (`append`) behaviour the API
cannot provide. Reconciling both would mean rewriting one of the two, which is
exactly what writing a separate plugin is.

This is not a replacement and not a fork. If anything, the cleanest outcome
would have been for both ideas to live in one place — it just isn't possible
without discarding one of the two foundations, and that is nobody's fault. Each
project keeps its own path.

> **Using OpenCode V1?**
> [nickjvandyke/opencode.nvim](https://github.com/nickjvandyke/opencode.nvim) is
> the one you want. This plugin targets the OpenCode v2 API and will not work on
> V1. Nick's plugin supports v2 on its `main` branch too.

## License

[MIT](./LICENSE) © metal3d 2026.

See [CONTRIBUTING.md](./CONTRIBUTING.md) and [CHANGELOG.md](./CHANGELOG.md).
