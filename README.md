# opencode.nvim

A Neovim plugin that opens the **real [OpenCode](https://opencode.ai/) application**
in a side terminal and drives it over OpenCode's **v2 HTTP API** (REST + SSE).

One keymap opens the actual `opencode` TUI in a split — left or right — while the
plugin's prompts, reviews and diagnostics go straight into the same session over
the API. No embedded TUI reimplementation, no legacy `/tui/*` endpoints, no Lua
dependencies.

> **Note on provenance.** This project is a from-scratch rewrite that targets
> the public OpenCode v2 API only. The implementation is original work; it does
> not derive from any other Neovim/OpenCode plugin. OpenCode itself is © its
> authors.

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
vim.g.opencode_opts = {}
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "metal3d/opencode.nvim",
  event = "VeryLazy",
  config = function()
    ---@type opencode.Opts
    vim.g.opencode_opts = {}

    vim.keymap.set({ "n", "x" }, "<leader>oca", function()
      require("opencode").ask()
    end, { desc = "Ask OpenCode about @this" })
    vim.keymap.set({ "n", "x" }, "<leader>oct", function()
      require("opencode").toggle()
    end, { desc = "Toggle OpenCode panel" })
    vim.keymap.set({ "n", "x" }, "<leader>ocr", function()
      require("opencode").review()
    end, { desc = "Review @this" })
    vim.keymap.set({ "n", "x" }, "<leader>ocf", function()
      require("opencode").fix()
    end, { desc = "Fix @diagnostics" })
  end,
}
```

Run `:checkhealth opencode` after setup.

## Configuration

Configuration lives in the global `vim.g.opencode_opts` table and is merged
over the defaults in `lua/opencode/config.lua`.

```lua
vim.g.opencode_opts = {
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
  },
  prompts = {
    review = "Review @this for correctness and readability.",
    fix = "Fix @diagnostics",
    explain = "Explain @this and its context.",
    document = "Add comments documenting @this.",
    test = "Add tests for @this.",
  },
  keys = {},         -- {( lhs, action-fn | action-id )} applied by setup()
  session = {
    mode = "recent", -- "recent" adopts the latest session; "new" creates one
  },
  events = {
    reload = true,   -- set vim.o.autoread so edited buffers reload
  },
}
```

## Usage

| `:Opencode` command | Description                            |
| ------------------- | -------------------------------------- |
| `:OpencodeToggle`   | Open / close the side panel            |
| `:OpencodeAsk [text]` | Focus the prompt line               |
| `:OpencodeReview`   | Send "Review @this"                    |
| `:OpencodeFix`      | Send "Fix @diagnostics"                |
| `:OpencodeExplain`  | Send "Explain @this"                   |
| `:OpencodeCommand`  | Open the action palette                |
| `:OpencodeSession`  | Switch the active session              |
| `:OpencodePermissions` | Surface pending permissions        |
| `:OpencodeDiff`     | View the session diff                  |
| `:checkhealth opencode` | Run the health check              |

### API (`require("opencode")`)

- `toggle()` — toggle the OpenCode terminal on the side.
- `ask()` — open a floating input popup (prefilled with the current context
  reference) and send your question.
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
- `setup()` — apply user keymaps from `opts.keys`.

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
plugin/opencode.lua      startup wiring: highlight groups, commands, reload
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
```

## License

[MIT](./LICENSE) © metal3d 2026.

See [CONTRIBUTING.md](./CONTRIBUTING.md) and [CHANGELOG.md](./CHANGELOG.md).
