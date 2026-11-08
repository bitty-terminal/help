-- Behavior parity test suite for `bitty-terminal.help` (bitty#2408, bitty-plugins#122).

local mock_host = require("support.mock_host")

local specs = {}

function specs.registers_toggle_command_and_suggests_four_historical_chords(t)
  local host, state = mock_host.new()
  _G.bitty = host
  local help = require("help.init")

  t.ok(state.commands["toggle_help"] ~= nil, "toggle_help command is registered")
  t.equal(state.commands["toggle_help"].title, help.COMMAND_TITLE, "command title matches")
  t.equal(#state.suggestions, 4, "suggests exactly the four historical chords")
  t.equal(state.suggestions[1].chord, "alt+`", "first suggestion is alt+`")
  t.equal(state.suggestions[2].chord, "alt+?", "second suggestion is alt+?")
  t.equal(state.suggestions[3].chord, "alt+shift+?", "third suggestion is alt+shift+?")
  t.equal(state.suggestions[4].chord, "alt+shift+/", "fourth suggestion is alt+shift+/")
  for i = 1, 4 do
    t.equal(
      state.suggestions[i].command,
      "bitty-terminal.help:toggle_help",
      "suggestion targets bitty-terminal.help:toggle_help"
    )
    t.equal(state.suggestions[i].when, "global", "suggestion context is global")
  end
end

function specs.regenerates_live_rows_on_every_show_and_joins_command_titles(t)
  local host, state = mock_host.new({
    command_catalog = {
      {
        plugin = "bitty-terminal.palette",
        id = "toggle",
        qualified = "bitty-terminal.palette:toggle",
        title = "Palette: toggle",
      },
    },
    keymaps = {
      {
        chord = "ctrl+shift+c",
        action = "copy",
        source = "default",
        context = "global",
        title = "Copy selection",
      },
      {
        chord = "ctrl+shift+p",
        action = "command:bitty-terminal.palette:toggle",
        source = "user",
        context = "global",
        command = "bitty-terminal.palette:toggle",
      },
    },
  })
  _G.bitty = host
  local help = require("help.init")

  local shown = state.commands["toggle_help"].run({})
  t.equal(shown, true, "first toggle shows the help overlay")
  t.equal(help.status().visible, true, "status reports visible = true")
  t.equal(#state.keymaps_calls, 1, "first show reads live keymap registry once")

  local lines = state.scene_texts()
  t.equal(lines[1], "Keyboard shortcuts", "header row is Keyboard shortcuts")
  t.equal(lines[2], "ctrl+shift+c  copy (Copy selection)", "Core action includes title")
  t.equal(
    lines[3],
    "ctrl+shift+p  command:bitty-terminal.palette:toggle (Palette: toggle)",
    "plugin command action joins title from bitty.commands.list"
  )
  t.equal(lines[4], "Esc closes | repeat toggle closes", "footer row is present")

  -- Second toggle hides the panel without reading keymaps.
  local hidden = state.commands["toggle_help"].run({})
  t.equal(hidden, false, "second toggle hides the help overlay")
  t.equal(help.status().visible, false, "status reports visible = false")
  t.equal(state.present_hide_calls, 1, "present.hide called on toggle-off")

  -- Mutate live keymaps before the next show to prove no row cache survives.
  state.keymaps = {
    {
      chord = "alt+n",
      action = "new_tab",
      source = "user",
      context = "global",
      title = "New tab",
    },
  }
  local reshown = state.commands["toggle_help"].run({})
  t.equal(reshown, true, "third toggle re-opens the help overlay")
  t.equal(#state.keymaps_calls, 2, "re-open calls bitty.keymaps.list again (no cache)")
  local refreshed = state.scene_texts()
  t.equal(#refreshed, 3, "refreshed scene has title + 1 row + footer")
  t.equal(refreshed[2], "alt+n  new_tab (New tab)", "refreshed row reflects mutated live registry")
end

function specs.pages_across_truncated_batches_and_caps_scene_at_64_rows_with_overflow_tail(t)
  local keymaps = {}
  for i = 1, 300 do
    keymaps[i] = {
      chord = string.format("alt+f%d", i),
      action = string.format("command:test.plugin:act_%d", i),
      source = "user",
      context = "global",
      command = string.format("test.plugin:act_%d", i),
    }
  end

  local host, state = mock_host.new({ keymaps = keymaps })
  _G.bitty = host
  local help = require("help.init")

  local ok = help.show()
  t.equal(ok, true, "show succeeds for 300 bindings across 2 pages")
  t.equal(#state.keymaps_calls, 2, "paged twice (256 + 44) while truncated == true")
  t.equal(state.keymaps_calls[1].offset, 0, "first page starts at offset 0")
  t.equal(state.keymaps_calls[2].offset, 256, "second page starts at offset 256")

  local lines = state.scene_texts()
  t.equal(#lines, 64, "scene is capped at PRESENTATION_OVERLAY_MAX_ROWS (64)")
  t.equal(lines[1], "Keyboard shortcuts", "first row is title")
  t.equal(lines[63], "+239 more", "63rd row is +N more overflow tail (300 - 61 = 239)")
  t.equal(lines[64], "Esc closes | repeat toggle closes", "64th row is footer")
  t.equal(help.status().truncated, true, "status marks scene as truncated")
end

function specs.overlay_dismissed_clears_visibility_without_reshowing(t)
  local host, state = mock_host.new({
    keymaps = {
      { chord = "alt+?", action = "command:bitty-terminal.help:toggle_help", source = "default", context = "global" },
    },
  })
  _G.bitty = host
  local help = require("help.init")

  help.toggle()
  t.equal(help.status().visible, true, "overlay is visible after toggle")

  -- Foreign owner dismissal is ignored.
  state.emit("overlay.dismissed", {
    owner = "bitty-terminal.other",
    handle = help.status().handle,
    reason = "escape",
  })
  t.equal(help.status().visible, true, "foreign owner dismissal is ignored")

  -- Matching owner dismissal clears visibility without calling present.show.
  local show_calls_before = state.present_show_calls
  state.emit("overlay.dismissed", {
    owner = "bitty-terminal.help",
    handle = help.status().handle,
    reason = "escape",
  })
  t.equal(help.status().visible, false, "escape dismissal clears local visibility state")
  t.equal(state.present_show_calls, show_calls_before, "dismissal never re-shows the overlay")

  -- Next toggle opens cleanly again.
  local reopened = help.toggle()
  t.equal(reopened, true, "toggle after Esc dismissal opens the overlay again")
  t.equal(help.status().visible, true, "overlay is visible again")
end

function specs.denied_or_empty_read_never_fabricates_rows(t)
  -- Case 1: Empty registry.
  local empty_host, empty_state = mock_host.new({ keymaps = {} })
  _G.bitty = empty_host
  local help = require("help.init")

  local ok_empty = help.show()
  t.equal(ok_empty, true, "empty keymap registry still presents bounded empty notice")
  local empty_lines = empty_state.scene_texts()
  t.equal(#empty_lines, 3, "empty scene has title + empty notice + footer")
  t.equal(empty_lines[2], "No keybindings configured", "empty notice row is explicit")

  -- Case 2: Capability denied (`runtime.keymaps.read` refused).
  package.loaded["help.init"] = nil
  local denied_host, denied_state = mock_host.new({
    keymaps_error = {
      code = "E_CAPABILITY_DENIED",
      message = "capability 'runtime.keymaps.read' is not granted",
    },
  })
  _G.bitty = denied_host
  local help_denied = require("help.init")

  local ok_denied, err = help_denied.show()
  t.equal(ok_denied, false, "denied keymap read returns false")
  t.equal(err.code, "E_CAPABILITY_DENIED", "typed denial code is preserved")
  local denied_lines = denied_state.scene_texts()
  t.equal(#denied_lines, 3, "denied scene has title + unavailable notice + footer (zero fabricated bindings)")
  t.matches(denied_lines[2], "^unavailable: E_CAPABILITY_DENIED:", "unavailable row reports the denial")
end

function specs.sanitizes_control_bytes_and_resets_on_unload(t)
  local host, state = mock_host.new({
    keymaps = {
      {
        chord = "alt+c\0\27",
        action = "copy\n\r\t",
        source = "user",
        context = "global",
        title = "Copy\194\155unsafe",
      },
    },
  })
  _G.bitty = host
  local help = require("help.init")

  help.show()
  local lines = state.scene_texts()
  t.equal(lines[2], "alt+c  copy (Copy unsafe)", "ASCII and C1 control bytes are stripped")

  help.reset()
  t.equal(help.status().visible, false, "reset clears visibility")
  t.equal(help.status().handle, nil, "reset clears handle")
  t.equal(state.presented_handle, nil, "reset hides and unmounts the presentation handle")
end

return specs
