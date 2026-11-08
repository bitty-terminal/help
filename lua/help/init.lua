-- Entry point for Bitty Help (bitty-terminal.help).
--
-- The host evaluates this file once per plugin activation and owns every
-- resource created here for the lifetime of that generation. Registration
-- calls (`bitty.commands.register`, `bitty.keymaps.suggest`,
-- `bitty.events.subscribe`) are valid only while this file executes.
--
-- Surface:
-- - `bitty.keymaps.list({ offset, limit })` (`runtime.keymaps.read`,
--   bitty#2405): bounded, read-only pages of the live resolved keymap table
--   (up to 256 rows per call, 1024 total, 64 KiB response).
-- - `bitty.commands.list()` (ungated): active command catalog used to join
--   `command:<owner:id>` bindings with their human-readable titles.
-- - `bitty.ui.mount("overlay", scene)` / `bitty.ui.update(handle, scene)`
--   (`ui.rich`, `ui.overlay`): declarative `List` + `Text` scene bounded to
--   64 rows and 16 KiB (`OverlayRowBudget::PRESENTATION`).
-- - `bitty.ui.present.show(handle)` / `bitty.ui.present.hide(handle)`
--   (`ui.present`, bitty#2406): non-modal `Popup` presentation overlay session
--   with no keyboard or pointer capture.
-- - `overlay.dismissed` event: emitted by Core when `Esc` or view close
--   dismisses the presentation overlay without consuming the key press.

local M = {}

M.PLUGIN_ID = "bitty-terminal.help"
M.COMMAND_ID = "toggle_help"
M.COMMAND_TITLE = "Help: toggle shortcut overlay"
M.QUALIFIED_COMMAND = "bitty-terminal.help:toggle_help"

-- Historical default chords retired from Core and suggested by the plugin
-- (bitty#2407, bitty#2408). The host's SuggestedBindingDirectory applies the
-- configured `mod_key` (`alt` or `super`) at lookup time and always yields to
-- explicit user bindings.
M.SUGGESTED_CHORDS = {
  "alt+`",
  "alt+?",
  "alt+shift+?",
  "alt+shift+/",
}

M.PANEL_TITLE = "Keyboard shortcuts"
M.PANEL_FOOTER = "Esc closes | repeat toggle closes"
M.EMPTY_MESSAGE = "No keybindings configured"
M.UNAVAILABLE_PREFIX = "unavailable: "

-- Host contract bounds (bitty#2405, bitty#2406).
M.PAGE_LIMIT = 256
M.MAX_REGISTRY_ROWS = 1024
M.MAX_PAGES = 4
M.MAX_SCENE_ROWS = 64
M.MAX_BODY_ROWS = M.MAX_SCENE_ROWS - 2
M.MAX_SCENE_BYTES = 16384
M.MAX_CHORD_BYTES = 48
M.MAX_ACTION_BYTES = 80
M.MAX_TITLE_BYTES = 64
M.MAX_ROW_BYTES = 160
M.MAX_ERROR_BYTES = 96

local state = {
  visible = false,
  handle = nil,
  error = nil,
  row_count = 0,
  total_bindings = 0,
  truncated = false,
}

-- Strip ASCII controls (0x00-0x1F, 0x7F) and UTF-8 C1 controls (U+0080-U+009F,
-- encoded as 0xC2 0x80..0x9F), collapse whitespace runs, and trim ends.
local function clean_string(raw)
  if type(raw) ~= "string" or raw == "" then
    return ""
  end
  local stripped = string.gsub(raw, "[\0-\31\127]", " ")
  stripped = string.gsub(stripped, "\194[\128-\159]", " ")
  stripped = string.gsub(stripped, "%s+", " ")
  stripped = string.gsub(stripped, "^%s+", "")
  stripped = string.gsub(stripped, "%s+$", "")
  return stripped
end

-- Step back from a byte index so truncation never splits a multi-byte UTF-8
-- sequence. Continuation bytes match 10xxxxxx (0x80..0xBF).
local function utf8_safe_prefix(text, limit)
  if #text <= limit then
    return text
  end
  if limit <= 0 then
    return ""
  end
  local cut = limit
  while cut > 0 do
    local b = string.byte(text, cut)
    if b < 128 or b >= 192 then
      break
    end
    cut = cut - 1
  end
  if cut > 0 then
    local lead = string.byte(text, cut)
    local needed = 1
    if lead >= 240 then
      needed = 4
    elseif lead >= 224 then
      needed = 3
    elseif lead >= 192 then
      needed = 2
    end
    if cut + needed - 1 > limit then
      cut = cut - 1
    end
  end
  return string.sub(text, 1, cut)
end

-- Sanitize and bound a string to `max_bytes` (including "..." when truncated).
function M.sanitize_text(value, max_bytes)
  local limit = type(max_bytes) == "number" and max_bytes or M.MAX_ROW_BYTES
  local cleaned = clean_string(value)
  if #cleaned <= limit then
    return cleaned
  end
  if limit <= 3 then
    return utf8_safe_prefix(cleaned, limit)
  end
  return utf8_safe_prefix(cleaned, limit - 3) .. "..."
end

-- Normalize a host failure value or message into `{ code, message }`.
function M.normalize_error(raw, fallback_code, fallback_message)
  local default_code = fallback_code or "E_KEYMAPS_UNAVAILABLE"
  local default_msg = fallback_message or "keymap registry unavailable"
  if type(raw) == "table" then
    local code = type(raw.code) == "string" and raw.code ~= "" and raw.code or default_code
    local msg = type(raw.message) == "string" and raw.message ~= "" and raw.message or default_msg
    return {
      code = M.sanitize_text(code, 48),
      message = M.sanitize_text(msg, M.MAX_ERROR_BYTES),
    }
  end
  if type(raw) == "string" and raw ~= "" then
    local code = string.match(raw, "(E_[A-Z0-9_]+)") or default_code
    return {
      code = M.sanitize_text(code, 48),
      message = M.sanitize_text(raw, M.MAX_ERROR_BYTES),
    }
  end
  return {
    code = M.sanitize_text(default_code, 48),
    message = M.sanitize_text(default_msg, M.MAX_ERROR_BYTES),
  }
end

-- Query `bitty.commands.list()` for human-readable command titles so
-- `command:<owner:id>` keymap rows can display their registered title.
function M.read_command_titles(host)
  local h = host or bitty
  local titles = {}
  if type(h) ~= "table" or type(h.commands) ~= "table" or type(h.commands.list) ~= "function" then
    return titles
  end
  local ok, list = pcall(h.commands.list)
  if not ok or type(list) ~= "table" then
    return titles
  end
  for i = 1, #list do
    local entry = list[i]
    if type(entry) == "table" and type(entry.title) == "string" then
      local title = M.sanitize_text(entry.title, M.MAX_TITLE_BYTES)
      if title ~= "" then
        if type(entry.qualified) == "string" and entry.qualified ~= "" then
          titles[entry.qualified] = title
        end
        if type(entry.plugin) == "string" and entry.plugin ~= "" and type(entry.id) == "string" and entry.id ~= "" then
          local composed = entry.plugin .. ":" .. entry.id
          if titles[composed] == nil then
            titles[composed] = title
          end
        end
        if type(entry.id) == "string" and entry.id ~= "" and titles[entry.id] == nil then
          titles[entry.id] = title
        end
      end
    end
  end
  return titles
end

-- Read all live keymap pages from `bitty.keymaps.list({ offset, limit })`,
-- paging while `truncated == true` up to `MAX_REGISTRY_ROWS` (1024). Never
-- caches across calls.
function M.read_keymaps(host)
  local h = host or bitty
  if type(h) ~= "table" or type(h.keymaps) ~= "table" or type(h.keymaps.list) ~= "function" then
    return nil, M.normalize_error(nil, "E_KEYMAPS_UNAVAILABLE", "keymap read API is not available")
  end

  local entries = {}
  local offset = 0
  local total = 0
  local truncated = false

  for _page_index = 1, M.MAX_PAGES do
    local ok, page = pcall(h.keymaps.list, {
      offset = offset,
      limit = M.PAGE_LIMIT,
    })
    if not ok then
      return nil, M.normalize_error(page, "E_KEYMAPS_UNAVAILABLE", "keymap read failed")
    end
    if type(page) ~= "table" or type(page.entries) ~= "table" then
      return nil, M.normalize_error(page, "E_KEYMAPS_UNAVAILABLE", "malformed keymap page")
    end

    local page_entries = page.entries
    local count = #page_entries
    if type(page.total) == "number" and page.total >= 0 then
      total = math.floor(page.total)
    end

    for i = 1, count do
      if #entries >= M.MAX_REGISTRY_ROWS then
        truncated = true
        break
      end
      local row = page_entries[i]
      if type(row) == "table" and type(row.chord) == "string" and type(row.action) == "string" then
        entries[#entries + 1] = row
      end
    end

    local page_truncated = page.truncated == true
    if not page_truncated or count == 0 or #entries >= M.MAX_REGISTRY_ROWS then
      truncated = page_truncated or (total > #entries)
      break
    end

    local next_offset = offset + count
    if next_offset <= offset or next_offset >= M.MAX_REGISTRY_ROWS then
      truncated = true
      break
    end
    offset = next_offset
  end

  if total < #entries then
    total = #entries
  end

  return {
    entries = entries,
    total = total,
    truncated = truncated or (total > #entries),
  }, nil
end

-- Format one keymap entry into `<chord>  <action>` (plus ` (<title>)` when a
-- distinct command or action title is available).
function M.format_binding_row(entry, titles)
  if type(entry) ~= "table" then
    return nil
  end
  local chord = M.sanitize_text(entry.chord, M.MAX_CHORD_BYTES)
  local action = M.sanitize_text(entry.action, M.MAX_ACTION_BYTES)
  if chord == "" or action == "" then
    return nil
  end

  local lookup = type(titles) == "table" and titles or {}
  local resolved_title = nil

  local command_id = nil
  if type(entry.command) == "string" and entry.command ~= "" then
    command_id = clean_string(entry.command)
  elseif string.sub(action, 1, 8) == "command:" then
    command_id = clean_string(string.sub(action, 9))
  end

  if command_id ~= nil and command_id ~= "" then
    resolved_title = lookup[command_id]
    if resolved_title == nil then
      local _, colon_pos = string.find(command_id, ":", 1, true)
      if colon_pos ~= nil then
        local short_id = string.sub(command_id, colon_pos + 1)
        resolved_title = lookup[short_id]
      end
    end
  end

  if (resolved_title == nil or resolved_title == "") and type(entry.title) == "string" and entry.title ~= "" then
    resolved_title = M.sanitize_text(entry.title, M.MAX_TITLE_BYTES)
  end

  local line = chord .. "  " .. action
  if resolved_title ~= nil and resolved_title ~= "" and resolved_title ~= action then
    line = line .. " (" .. resolved_title .. ")"
  end
  if #line <= M.MAX_ROW_BYTES then
    return line
  end
  return utf8_safe_prefix(line, M.MAX_ROW_BYTES - 3) .. "..."
end

local function make_text_node(host, text, tone)
  local h = host or bitty
  local spec = { text = text, tone = tone }
  if type(h) == "table" and type(h.ui) == "table" and type(h.ui.text) == "function" then
    local ok, node = pcall(h.ui.text, spec)
    if ok and type(node) == "table" then
      return node
    end
  end
  return {
    kind = "Text",
    text = text,
    tone = tone,
  }
end

local function make_list_node(host, children)
  local h = host or bitty
  local spec = { children = children }
  if type(h) == "table" and type(h.ui) == "table" and type(h.ui.list) == "function" then
    local ok, node = pcall(h.ui.list, spec)
    if ok and type(node) == "table" then
      return node
    end
  end
  return {
    kind = "List",
    children = children,
  }
end

-- Build the bounded presentation scene (`<= 64` rows, `<= 16 KiB`) from a live
-- read result or error. Never fabricates shortcut rows when the read is denied
-- or empty.
function M.build_scene(read_result, err, titles, host)
  local body_rows = {}
  local total_bindings = 0
  local has_overflow = false

  if read_result == nil then
    local normalized = M.normalize_error(err, "E_KEYMAPS_UNAVAILABLE", "keymap registry unavailable")
    local detail = normalized.code .. ": " .. normalized.message
    body_rows[1] = {
      text = M.sanitize_text(M.UNAVAILABLE_PREFIX .. detail, M.MAX_ROW_BYTES),
      tone = "muted",
    }
  else
    local raw_entries = type(read_result.entries) == "table" and read_result.entries or {}
    local formatted = {}
    for i = 1, #raw_entries do
      local line = M.format_binding_row(raw_entries[i], titles)
      if line ~= nil then
        formatted[#formatted + 1] = line
      end
    end

    total_bindings = type(read_result.total) == "number" and math.max(math.floor(read_result.total), #formatted)
      or #formatted

    if #formatted == 0 then
      body_rows[1] = {
        text = M.EMPTY_MESSAGE,
        tone = "muted",
      }
    else
      local needs_overflow = (total_bindings > M.MAX_BODY_ROWS)
        or (#formatted > M.MAX_BODY_ROWS)
        or (read_result.truncated == true and total_bindings > #formatted)
      local max_binding_rows = needs_overflow and (M.MAX_BODY_ROWS - 1) or M.MAX_BODY_ROWS

      -- Account for byte budget so the scene never exceeds MAX_SCENE_BYTES.
      local fixed_bytes = #M.PANEL_TITLE + #M.PANEL_FOOTER + 32
      local used_bytes = fixed_bytes
      local kept = 0

      for i = 1, math.min(#formatted, max_binding_rows) do
        local line = formatted[i]
        if used_bytes + #line > M.MAX_SCENE_BYTES then
          needs_overflow = true
          break
        end
        kept = kept + 1
        used_bytes = used_bytes + #line
        body_rows[#body_rows + 1] = {
          text = line,
          tone = "primary",
        }
      end

      if needs_overflow or kept < total_bindings then
        has_overflow = true
        if #body_rows >= M.MAX_BODY_ROWS then
          body_rows[#body_rows] = nil
          kept = math.max(0, kept - 1)
        end
        local remaining = math.max(1, total_bindings - kept)
        body_rows[#body_rows + 1] = {
          text = string.format("+%d more", remaining),
          tone = "muted",
        }
      end
    end
  end

  local children = {}
  children[#children + 1] = make_text_node(host, M.PANEL_TITLE, "accent")
  for i = 1, #body_rows do
    if #children >= M.MAX_SCENE_ROWS - 1 then
      break
    end
    children[#children + 1] = make_text_node(host, body_rows[i].text, body_rows[i].tone)
  end
  children[#children + 1] = make_text_node(host, M.PANEL_FOOTER, "muted")

  return make_list_node(host, children), {
    row_count = #children,
    total_bindings = total_bindings,
    truncated = has_overflow,
  }
end

local function mount_or_update(scene, host)
  local h = host or bitty
  if type(h) ~= "table" or type(h.ui) ~= "table" then
    return nil, M.normalize_error(nil, "E_UI_UNAVAILABLE", "UI bridge is not available")
  end

  if state.handle ~= nil and type(h.ui.update) == "function" then
    local ok, updated = pcall(h.ui.update, state.handle, scene)
    if ok and updated ~= false then
      return state.handle, nil
    end
    state.handle = nil
  end

  if type(h.ui.mount) ~= "function" then
    return nil, M.normalize_error(nil, "E_UI_UNAVAILABLE", "bitty.ui.mount is not available")
  end
  local ok, handle = pcall(h.ui.mount, "overlay", scene)
  if not ok or type(handle) ~= "number" then
    return nil, M.normalize_error(handle, "E_UI_UNAVAILABLE", "failed to mount overlay scene")
  end
  state.handle = handle
  return handle, nil
end

-- Regenerate shortcut rows from the live keymap registry and present the
-- non-modal overlay. No row cache survives across shows.
function M.show(host)
  local h = host or bitty
  local titles = M.read_command_titles(h)
  local read_result, read_err = M.read_keymaps(h)
  state.error = read_err

  local scene, meta = M.build_scene(read_result, read_err, titles, h)
  state.row_count = meta.row_count
  state.total_bindings = meta.total_bindings
  state.truncated = meta.truncated

  local handle, mount_err = mount_or_update(scene, h)
  if handle == nil then
    state.visible = false
    state.error = state.error or mount_err
    return false, state.error
  end

  if type(h.ui.present) ~= "table" or type(h.ui.present.show) ~= "function" then
    state.visible = false
    state.error = state.error
      or M.normalize_error(nil, "E_UI_UNAVAILABLE", "presentation overlay API is not available")
    return false, state.error
  end

  local ok, shown = pcall(h.ui.present.show, handle)
  if not ok or shown == false then
    state.visible = false
    state.error = state.error or M.normalize_error(shown, "E_UI_UNAVAILABLE", "failed to show presentation overlay")
    return false, state.error
  end

  state.visible = true
  if read_err ~= nil then
    return false, read_err
  end
  return true, nil
end

-- Hide the presentation overlay and clear local visibility state.
function M.hide(host)
  local h = host or bitty
  local handle = state.handle
  state.visible = false
  if handle ~= nil and type(h) == "table" and type(h.ui) == "table" and type(h.ui.present) == "table" then
    if type(h.ui.present.hide) == "function" then
      pcall(h.ui.present.hide, handle)
    end
  end
  return true
end

-- Toggle the help overlay: hide when visible, regenerate and show when hidden.
function M.toggle(_args, host)
  if state.visible then
    M.hide(host)
    return false
  end
  local ok = M.show(host)
  return ok == true
end

-- Handle `overlay.dismissed` notifications from Core (`reason = "escape"` or
-- `"view-closed"`). Clears local visibility state without calling `show` or
-- consuming the key press.
function M.on_dismissed(event)
  if not state.visible then
    return
  end
  local payload = type(event) == "table" and event.payload or event
  if type(payload) == "table" then
    if type(payload.owner) == "string" and payload.owner ~= "" and payload.owner ~= M.PLUGIN_ID then
      return
    end
    if type(payload.handle) == "number" and state.handle ~= nil and payload.handle ~= state.handle then
      return
    end
  end
  state.visible = false
end

-- Reset generation state (used by tests and unload teardown).
function M.reset(host)
  local h = host or bitty
  local handle = state.handle
  state.visible = false
  state.handle = nil
  state.error = nil
  state.row_count = 0
  state.total_bindings = 0
  state.truncated = false
  if handle ~= nil and type(h) == "table" and type(h.ui) == "table" then
    if type(h.ui.present) == "table" and type(h.ui.present.hide) == "function" then
      pcall(h.ui.present.hide, handle)
    end
    if type(h.ui.unmount) == "function" then
      pcall(h.ui.unmount, handle)
    end
  end
end

-- Read-only status snapshot for tests and diagnostics.
function M.status()
  return {
    visible = state.visible,
    handle = state.handle,
    error = state.error and state.error.code or nil,
    error_message = state.error and state.error.message or nil,
    row_count = state.row_count,
    total_bindings = state.total_bindings,
    truncated = state.truncated,
  }
end

if bitty == nil or type(bitty) ~= "table" then
  return M
end

if type(bitty.commands) == "table" and type(bitty.commands.register) == "function" then
  bitty.commands.register({
    id = M.COMMAND_ID,
    title = M.COMMAND_TITLE,
    description = "Regenerate shortcut rows from the live keymap registry and toggle the help overlay.",
    args_schema = {
      type = "object",
      properties = {},
      additionalProperties = false,
    },
    result_schema = { type = "boolean" },
    run = function(args)
      return M.toggle(args)
    end,
  })
end

if type(bitty.keymaps) == "table" and type(bitty.keymaps.suggest) == "function" then
  for i = 1, #M.SUGGESTED_CHORDS do
    bitty.keymaps.suggest({
      chord = M.SUGGESTED_CHORDS[i],
      command = M.QUALIFIED_COMMAND,
      when = "global",
    })
  end
end

if type(bitty.events) == "table" and type(bitty.events.subscribe) == "function" then
  bitty.events.subscribe("overlay.dismissed", function(event)
    M.on_dismissed(event)
  end)
end

return M
