# Changelog

All notable changes to `bitty-terminal.help` are recorded here. The format
follows Keep a Changelog; versions follow the plugin's own `0.x` line while
the host is pre-1.0.

## [0.0.1] - 2026-11-08

### Added

- First-party `bitty-terminal.help` plugin (bitty#2408, bitty-plugins#122)
  implementing the help and which-key shortcut overlay over
  `bitty.keymaps.list` (bitty#2405), `bitty.commands.list`, and the non-modal
  presentation overlay session `bitty.ui.present.show` / `hide` (bitty#2406).
- `toggle_help` command (`bitty-terminal.help:toggle_help`) and suggestions for
  the four historical help chords (`` alt+` ``, `alt+?`, `alt+shift+?`,
  `alt+shift+/`) via `bitty.keymaps.suggest` (bitty#2407).
- Live regeneration on every show with multi-page `truncated` traversal up to
  the 1024-row registry ceiling, `command:` title joining, bounded 64-row /
  16 KiB presentation scene with `+N more` overflow tail, non-consuming `Esc`
  dismissal synchronization on `overlay.dismissed`, and explicit empty or
  unavailable states without fabricated fallback rows.
