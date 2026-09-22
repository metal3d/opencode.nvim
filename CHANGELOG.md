# Changelog

All notable changes to this project (a clean-room OpenCode v2 integration) are
documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning is [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial from-scratch implementation driven entirely by the OpenCode v2 HTTP
  API (REST + SSE), with no legacy `/tui/*` endpoints.
- Side panel running the real `opencode` application in a terminal (vertical
  split, left or right), kept alive between toggles.
- Prompts are injected into the running TUI so they land in the tab you are
  looking at, with a fallback to the v2 API.
- Editor context placeholders: `@this`, `@selection`, `@buffer`, `@file`,
  `@diagnostics`.
- Built-in prompts and actions: review, fix, explain, session switch, session
  diff, permissions, compact, interrupt.
- Live SSE pipeline dispatching `OpencodeEvent:<type>` User autocmds.
- Permissions handling via the API (`once` / `always` / `reject`).
- Session diff review buffer.
- Auto-discovery of the OpenCode background service via `service.json`.
- `:checkhealth opencode`.
- Zero Lua dependencies (only `opencode` CLI + `curl`).
- Plenary-based test suite (`make test`) and a GitHub Actions workflow running
  it against Neovim 0.11, stable and nightly.
- Recommended `<leader>oc*` keymaps, opt-in through `opts.keys = "recommended"`.
- which-key integration: the recommended set names its `<leader>oc` prefix so the
  popup shows `+opencode` (which-key v3), and is a no-op when which-key is
  absent.
- A README section documenting the relationship with
  `nickjvandyke/opencode.nvim`: same idea, different integration model (snacks
  ecosystem vs no dependencies), and why the two cannot be merged.
- `append()` / `<leader>ocA` / `:OpencodeAdd`: type the rendered context at the
  running TUI prompt's cursor **without submitting it**, so you can finish the
  sentence before sending. This is the prefill gesture the old plugin got wrong
  by firing the prompt instead.
- `commit()` / `<leader>ocg` / `:OpencodeCommit`: ask OpenCode to propose a
  commit plan for the working tree and wait for confirmation before committing.
- Panel usability: focusing the panel enters Terminal mode automatically
  (`panel.insert`), and `<C-w>` is mapped **buffer-locally** to the window
  prefix so `<C-w><arrow>` navigates windows from Terminal mode without leaving
  it. The mappings apply to the panel only (configurable via
  `panel.terminal_keys`), never to other terminals or plugins.

### Changed

- Configuration now follows the lazy.nvim convention:
  `require("opencode").setup(opts)` accepts the `opts` table, merged over the
  defaults. The legacy `vim.g.opencode_opts` is still honoured at lower
  precedence, so existing configs keep working.
- `.stylua.toml` now matches the code style (`indent_type = "Spaces"`,
  `call_parentheses = "Always"`), so `stylua --check .` is clean; CI enforces it.
- `ask()`'s popup is now prefilled with the context reference (`path:L42: `)
  instead of hiding it until submit. You see exactly what will be sent, so you
  can keep it for a contextual question, clear it for an open one, or edit it.
  The text is not re-rendered on submit, so the popup is the source of truth.

### Fixed

- `@placeholder` expansion no longer corrupts values containing `%` (e.g.
  diagnostic messages like `100% done`) and no longer lets `@buffer` shadow
  `@buffers`.
- The SSE pipeline decoded each `data:` payload from the wrong offset, so no
  `OpencodeEvent:*` was ever dispatched.
- `util.find_up` joined path components without a separator, so it never found
  anything above the starting directory.
- Concurrent `connect()` calls are now queued instead of being silently dropped,
  so an action issued while a connection is in flight is no longer lost.
- A failed connection validation no longer leaves a stale, half-validated server
  installed; the server is cleared on error.
- `curl` requests get `--connect-timeout` / `--max-time`, and a whole connection
  attempt is bounded by a watchdog, so a dead server can no longer lock out
  every later attempt.
- `session()`, `diff()` and `permissions()` now ensure a connection first, so
  they no longer fail with "No OpenCode server connected" when used before
  `toggle()`.
- Pending permission requests are surfaced one at a time instead of stacking
  `vim.ui.select` prompts, which left only the last one answerable.
- The panel launches `opencode` from an argv list (`jobstart` with `term = true`)
  instead of a shell command line, so a session id is never reinterpreted as
  shell syntax. A missing CLI is now reported instead of raising an error.
- The panel terminal no longer leaks into the editor window: `jobstart` with
  `term = true` calls `termopen()`, which converts the *current* buffer into a
  terminal. Because a split shows the same buffer in both windows, the TUI took
  over the editor split (adding line numbers) and could clobber an open file.
  The terminal now gets its own dedicated buffer.
- `COLORTERM` is now forwarded to the panel's pseudo-terminal. Neovim does not
  propagate it to a `termopen()` pty, but OpenCode's OpenTUI renderer relies on
  it to select 24-bit colour and otherwise falls back to a degraded palette.
- The SSE stream never delivered any event: `vim.system`'s stdout callback is
  `(err, data)`, but the first argument (always nil) was read as the chunk. The
  event pipeline is now live end to end.
- The SSE subscription now reconnects with exponential backoff when the stream
  drops, and is stopped cleanly when the connection is lost.
- The session list is filtered server-side by directory in `ensure()`, and the
  session picker follows the API cursor, so sessions beyond the newest 50 are no
  longer missed (which previously caused a duplicate session to be created).
- JSON `null` object fields are decoded as `nil` (e.g. `cursor.next`), so
  pagination terminates instead of choking on `vim.NIL`.
- `wait_ready`'s `ready` flag is now honoured: when a freshly spawned TUI does
  not settle, the prompt falls back to the API instead of being injected blindly
  after the timeout. Readiness now also requires a few stable frames.
- The target session is tied to the directory it was resolved for: changing
  directory (`:cd`) re-resolves it, while a session chosen explicitly through the
  picker is kept. A `404` from the server clears a dead target.
- SSE events are filtered by directory, so a Neovim instance no longer reacts to
  activity from another project sharing the same OpenCode service.
- API responses now expose the HTTP status (used for the 404 invalidation).
- `context.format` now matches files reached through a different symlink than
  the working directory (still relative instead of absolute), and no longer
  errors on a missing file when there is no buffer to fall back on.
- The input popup can be cancelled with `<Esc>` from insert mode too.
- The diff preview no longer renders its summary as `+N -N` (which the `diff`
  filetype highlighted as a fake addition); it reads `additions: N, deletions:
  N`.
- `statusline()` now reports the real state: empty when disconnected, and
  `connecting` until a session for the current directory is targeted.

### Removed

- Unused API surface: `panel.type`, `panel.enter`, `panel.toggle` and
  `session.command`.