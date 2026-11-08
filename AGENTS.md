# Help repository guidance

## Repository and authority

- This is the independent `help` repository. Its canonical remote is
  <https://github.com/bitty-terminal/help>.
- The Bitty umbrella directory and
  [bitty-plugins](https://github.com/bitty-terminal/bitty-plugins) are grouping
  only; neither owns this repository's Git or CarryCtx state.
- Enter this repository before running Git, CarryCtx, validation, or toolchain
  commands.
- [bitty-terminal-docs](https://github.com/bitty-terminal/bitty-terminal-docs),
  [bitty-plugins-docs](https://github.com/bitty-terminal/bitty-plugins-docs),
  and [bitty-docs](https://github.com/bitty-terminal/bitty-docs) are the
  canonical sources for plugin architecture, API, security, packaging,
  compatibility, and public-behavior contracts. This repository must not
  invent capabilities, lifecycle semantics, or release policy.

## Plugin identity and scope

- Plugin id: `bitty-terminal.help` (manifest `plugin.id`), repository `help`,
  Lua module `lua/help/`.
- Purpose: the first-party help and which-key shortcut overlay over the
  bounded, read-only `bitty.keymaps.list()` API (bitty#2405), presented
  through the non-modal presentation overlay session `bitty.ui.present.*`
  (bitty#2406) and wired to the four historical chords via
  `bitty.keymaps.suggest()` (bitty#2407).
- Authority boundary: only `runtime.keymaps.read`, `ui.rich`, `ui.overlay`, and
  `ui.present`. No `ui.overlay.focus`, no `terminal.*`, `clipboard.*`, `fs.*`,
  `process.*`, `network.*`, `env.*`, `platform.*`, or `debug.*` authority, and
  no install-time execution.

## CarryCtx and delivery

- Use this repository's CarryCtx state for tasks, dependencies, scopes,
  sessions, progress, decisions, checkpoints, handoffs, and review.
- Branches use `ctx-XXXX/<type>-<short-slug>` after the first commit; before
  that, shared-checkout initialization is allowed for disjoint scopes with the
  full local gate.
- Do not commit, push, release, publish packages, create repositories, or
  mutate remote state without authorization.

## No hardcoded values

- Never hardcode host- or environment-specific values: absolute paths,
  usernames, hostnames, repository URLs beyond the canonical identity above,
  credentials, ports, or machine layout.
- Named constants own policy bounds (row caps, byte bounds, page limits).

## Toolchain policy

- JavaScript runs on `bun` (pinned in `package.json`).
- Run gates through the justfile: `just check`, `just lint`, `just fmt`,
  `just manifest`, `just docs`, `just lua`, `just test`.
- Version pins live in `package.json` + `bun.lock` for installed dev
  dependencies.
- CI success is a hard acceptance gate. Validate workflow changes with
  `actionlint` before push.

## Security and supply chain

- The manifest and keymap/command registries are untrusted data. Bound and
  sanitize before rendering; never fabricate shortcut rows when the host read
  is denied or empty.
- Keep the requested capability set minimal and declared in
  `bitty-plugin.toml`; the manifest is the single source of authority.
- No secrets, tokens, or local configuration in the repository, fixtures,
  logs, or CI output.
