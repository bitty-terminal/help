-- In-process host stub for `bitty-terminal.help` tests.
--
-- Mirrors the Core `bitty.keymaps.list`, `bitty.keymaps.suggest`,
-- `bitty.commands.register` / `list`, `bitty.ui.mount` / `update` / `unmount`,
-- `bitty.ui.present.show` / `hide`, and `bitty.events.subscribe` contracts.

local M = {}

function M.new(opts)
  opts = opts or {}

  local state = {
    commands = {},
    command_catalog = opts.command_catalog or {},
    suggestions = {},
    subscriptions = {},
    keymaps = opts.keymaps or {},
    keymaps_error = opts.keymaps_error,
    keymaps_calls = {},
    mounts = {},
    next_handle = 1,
    presented_handle = nil,
    present_show_calls = 0,
    present_hide_calls = 0,
    present_error = opts.present_error,
  }

  local host = {}

  host.commands = {
    register = function(def)
      assert(type(def) == "table", "command definition must be a table")
      assert(type(def.id) == "string" and def.id ~= "", "command id required")
      assert(type(def.run) == "function", "command run function required")
      state.commands[def.id] = def
      return #state.commands + 1
    end,
    list = function()
      local out = {}
      for i = 1, #state.command_catalog do
        out[#out + 1] = state.command_catalog[i]
      end
      for id, def in pairs(state.commands) do
        out[#out + 1] = {
          plugin = "bitty-terminal.help",
          id = id,
          qualified = "bitty-terminal.help:" .. id,
          title = def.title or id,
        }
      end
      return out
    end,
  }

  host.keymaps = {
    suggest = function(def)
      assert(type(def) == "table", "suggestion must be a table")
      state.suggestions[#state.suggestions + 1] = {
        chord = def.chord,
        command = def.command,
        when = def.when or "global",
      }
      return #state.suggestions
    end,
    list = function(req)
      req = req or {}
      state.keymaps_calls[#state.keymaps_calls + 1] = {
        offset = req.offset or 0,
        limit = req.limit or 256,
      }
      if state.keymaps_error ~= nil then
        error(state.keymaps_error, 0)
      end
      local offset = req.offset or 0
      local limit = req.limit or 256
      local total = math.min(#state.keymaps, 1024)
      local entries = {}
      local last = math.min(total, offset + limit)
      for i = offset + 1, last do
        entries[#entries + 1] = state.keymaps[i]
      end
      local truncated = (offset + #entries) < #state.keymaps
      return {
        entries = entries,
        total = total,
        offset = offset,
        truncated = truncated,
      }
    end,
  }

  host.ui = {
    text = function(spec)
      return {
        kind = "Text",
        text = spec.text,
        tone = spec.tone,
      }
    end,
    list = function(spec)
      return {
        kind = "List",
        children = spec.children,
      }
    end,
    mount = function(slot, scene)
      assert(slot == "overlay", "help must mount only in the overlay slot")
      local handle = state.next_handle
      state.next_handle = state.next_handle + 1
      state.mounts[handle] = {
        slot = slot,
        scene = scene,
        updates = 0,
      }
      return handle
    end,
    update = function(handle, scene)
      local mounted = state.mounts[handle]
      if mounted == nil then
        return false
      end
      mounted.scene = scene
      mounted.updates = mounted.updates + 1
      return true
    end,
    unmount = function(handle)
      state.mounts[handle] = nil
      if state.presented_handle == handle then
        state.presented_handle = nil
      end
      return true
    end,
    present = {
      show = function(handle)
        if state.present_error ~= nil then
          error(state.present_error, 0)
        end
        assert(state.mounts[handle] ~= nil, "present.show requires a mounted handle")
        state.presented_handle = handle
        state.present_show_calls = state.present_show_calls + 1
        return true
      end,
      hide = function(handle)
        state.present_hide_calls = state.present_hide_calls + 1
        if state.presented_handle == handle then
          state.presented_handle = nil
        end
        return true
      end,
    },
  }

  host.events = {
    subscribe = function(topic, fn)
      state.subscriptions[topic] = state.subscriptions[topic] or {}
      table.insert(state.subscriptions[topic], fn)
      return #state.subscriptions[topic]
    end,
  }

  function state.emit(topic, payload)
    local handlers = state.subscriptions[topic] or {}
    for i = 1, #handlers do
      handlers[i]({
        topic = topic,
        payload = payload,
      })
    end
  end

  function state.current_scene()
    local handle = state.presented_handle
    if handle == nil then
      for k in pairs(state.mounts) do
        handle = k
        break
      end
    end
    return handle and state.mounts[handle] and state.mounts[handle].scene or nil
  end

  function state.scene_texts()
    local scene = state.current_scene()
    if scene == nil or type(scene.children) ~= "table" then
      return {}
    end
    local lines = {}
    for i = 1, #scene.children do
      lines[#lines + 1] = scene.children[i].text
    end
    return lines
  end

  return host, state
end

return M
