# Help

Help and which-key shortcut overlay for the Bitty terminal.

## Overview

Help renders a floating, non-modal shortcut reference panel built from the
terminal's live keymap and command registries. Every time the panel opens, it
queries `bitty.keymaps.list` (bitty#2405), joins `command:<owner:id>` bindings
against `bitty.commands.list()` for human-readable command titles, formats
bounded `<chord>  <label>` rows, mounts a declarative `List` scene in the
`overlay` slot, and presents it through `bitty.ui.present.show` (bitty#2406).

The panel is informational and non-focusable (`NonModal` on the `Popup` tier):

- It never acquires keyboard or pointer capture (`ui.overlay.focus` is not
  requested).
- Pressing `Esc` dismisses the overlay in Core without consuming the key press
  (`0x1b` still reaches the active terminal session unless a Core confirmation
  gate owns the press) and emits `overlay.dismissed` so the plugin clears its
  visibility state.
- Repeating the toggle chord hides the panel through `bitty.ui.present.hide`.
- No row cache survives across opens: reloading configuration or enabling
  plugins immediately reflects on the next show.
- When `runtime.keymaps.read` is denied or the live keymap table is empty, the
  panel never fabricates hardcoded shortcuts; it either surfaces a bounded
  unavailable/empty state or returns the typed host error.

## Install

Prerequisites: Bitty `>=0.0.31` and Plugin API `^1.0`. The `0.0.31` floor is
the first release train shipping `bitty.keymaps.list` (`runtime.keymaps.read`),
`bitty.ui.present.show` / `hide` (`ui.present`), and live plugin-suggested
keybindings (`bitty.keymaps.suggest`).

From the official registry or directly from this repository:

```sh
bitty plugin install https://github.com/bitty-terminal/help.git
bitty plugin enable bitty-terminal.help
bitty plugin list   # confirm state and granted capabilities
```

From a local checkout:

```sh
bitty plugin install ./help --yes
bitty plugin enable bitty-terminal.help
```

## Commands

| Command                           | What it does                                                                  | Arguments |
| --------------------------------- | ----------------------------------------------------------------------------- | --------- |
| `bitty-terminal.help:toggle_help` | Regenerate rows from the live keymap registry and show the panel, or hide it. | None      |

The retired Core `show_help` alias is not registered as a separate command;
configurations that previously used `toggle_help` or `show_help` map to
`command:bitty-terminal.help:toggle_help`.

## Configuration

This plugin declares no settings.

## Keybindings

During activation, Help suggests the four historical help chords for
`bitty-terminal.help:toggle_help` via `bitty.keymaps.suggest`:

| Suggested chord | Command                           | Context  |
| --------------- | --------------------------------- | -------- |
| `` alt+` ``     | `bitty-terminal.help:toggle_help` | `global` |
| `alt+?`         | `bitty-terminal.help:toggle_help` | `global` |
| `alt+shift+?`   | `bitty-terminal.help:toggle_help` | `global` |
| `alt+shift+/`   | `bitty-terminal.help:toggle_help` | `global` |

The host's suggestion directory applies the configured `mod_key` (`alt` or
`super`) at lookup time and always yields to explicit user bindings. You can
also bind `command:bitty-terminal.help:toggle_help` explicitly in your config:

```lua
return {
  keymaps = {
    { chord = "alt+?", action = "command:bitty-terminal.help:toggle_help", context = "global" },
  },
}
```

## Troubleshooting

**The shortcut does nothing.** Verify `bitty --version` is `>=0.0.31` and check
`bitty plugin list` to confirm `bitty-terminal.help` is enabled with all four
capabilities granted (`runtime.keymaps.read`, `ui.rich`, `ui.overlay`,
`ui.present`). If a user binding already claims the chord, the user binding
wins by design.

**The panel does not appear on a tiny split or window.** Core's presentation
overlay layout requires a minimum inner viewport size to paint legibly; resize
the view or window and toggle again.

**The panel shows an unavailable or empty notice.** If `runtime.keymaps.read`
was not granted or the host keymap source is unavailable, the plugin refuses to
fabricate a fallback list. Re-install with `--yes` to grant the declared
capabilities.

## Capabilities

Four least-privilege grants, deny by default:

| Capability             | Why                                                                       |
| ---------------------- | ------------------------------------------------------------------------- |
| `runtime.keymaps.read` | Read bounded pages from `bitty.keymaps.list`.                             |
| `ui.rich`              | Construct declarative `List` and `Text` scene nodes.                      |
| `ui.overlay`           | Mount and update the scene in the `overlay` slot.                         |
| `ui.present`           | Show and hide the mounted `overlay` block on the non-modal `Popup` layer. |

Not requested: `ui.overlay.focus`, `terminal.*`, `clipboard.*`, `fs.*`,
`process.*`, `network.*`, `env.*`, `platform.*`, or `debug.*`.

## Development

```sh
just install   # materialize pinned dev dependencies (network, once)
just check     # lint + fmt-check + manifest + docs + lua + test
```

## Security

Report vulnerabilities through the umbrella project's security policy rather
than a public issue. This plugin contains no credentials, no install-time
execution, and no ambient authority. All registry strings are sanitized and
bounded before scene construction.
