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
- **Prompt through the v2 API** — the API is the point of truth: review / fix /
  explain always send to the session owned for the current directory, with or
  without a running panel.
- **Prefill the prompt from the editor** — `<leader>ocA` types the current
  context into the running TUI prompt *without submitting it*, so you can finish
  the sentence before sending. This is the only gesture that touches the pty.
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
  },
  prompts = {
    review = "Review @this for correctness and readability.",
    fix = "Fix @diagnostics",
    explain = "Explain @this and its context.",
    document = "Add comments documenting @this.",
    test = "Add tests for @this.",
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

**Custom set** — `keys` maps a left-hand side to a Lua function or a built-in
action id (invoked as `require("opencode").command(id)`):

```lua
keys = {
  ["<leader>on"] = function() require("opencode").prompt("@this") end,
  ["<leader>os"] = "session",
}
```

Valid action ids: `toggle`, `ask`, `review`, `audit`, `fix`, `explain`,
`session`, `diff`, `permissions`, `compact`, `interrupt`.

## Usage

| `:Opencode` command | Description                            |
| ------------------- | -------------------------------------- |
| `:OpencodeToggle`   | Open / close the side panel            |
| `:OpencodeAsk`      | Open a prompt popup                    |
| `:OpencodeAdd`      | Add the current context to the prompt (no submit) |
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
- `ask()` — open a floating input popup; the current context reference is
  captured and prepended to your question when it is sent.
- `append([placeholders])` — type the rendered context at the running TUI
  prompt's cursor **without submitting it**, so you can finish the sentence
  before sending. Requires a live panel (the v2 API cannot fill a prompt without
  processing it). Defaults to `@this`; warns and does nothing without one.
- `prompt(text)` — send a prompt over the v2 API, expanding context placeholders.
- `review()` / `fix()` / `explain()` — run a named prompt (also over the API).
- `send()` — send the current line over the v2 API.
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

### Where prompts go

OpenCode's v2 API is the **point of truth**: every prompt (review, fix, explain,
`ask`, `send`, `prompt`) is sent over HTTP to the session the plugin owns for the
current directory (`session.mode`). This is the safe path — it works whether or
not the panel is open, and it never depends on terminal parsing.

OpenCode exposes **no API for the TUI's active tab**, and the legacy `/tui/*`
control endpoints are absent from OpenCode v2.0.x. So the plugin no longer tries
to guess the active tab: what you see in the panel is whatever session that panel
is attached to.

The single exception is `append()` (`<leader>ocA`, `:OpencodeAdd`): the API
cannot prefill a prompt without processing it, so that one gesture writes to the
running TUI's pty — and deliberately never submits.

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

## License

[MIT](./LICENSE) © metal3d 2026.

See [CONTRIBUTING.md](./CONTRIBUTING.md) and [CHANGELOG.md](./CHANGELOG.md).
