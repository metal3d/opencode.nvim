# Changelog

All notable changes to this project (a clean-room OpenCode v2 integration) are
documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning is [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial from-scratch implementation driven entirely by the OpenCode v2 HTTP
  API (REST + SSE), with no legacy `/tui/*` endpoints.
- Native side panel (vertical split, left or right) rendering the active
  session with highlight groups and extmarks.
- Prompt line at the bottom of the panel with history and a base completion
  stub.
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