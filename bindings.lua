-- Hotkey Wheel: loaded from ~/.config/hypr/bindings.lua (the drawer's Set up
-- adds the line). Holding the trigger opens the wheel. The trigger and the
-- drawer's On switch are stored in the settings; when off, the trigger is
-- left to the apps.
local wheel_id = "io.github.erikrjohansson.hotkey-wheel"
local wheel_layer = "omarchy-hotkey-wheel"

-- Like Omarchy's own menus: no compositor fade, so the wheel is under the
-- cursor the moment it opens and gone the moment a slot runs.
hl.layer_rule({ match = { namespace = "^omarchy-hotkey-wheel(-picker)?$" }, no_anim = true, animation = "none" })

-- Press key and released button per trigger (names match the drawer's).
local triggers = {
  middle = { press = "mouse:274", button = "mouse:274" },
  ["super-middle"] = { press = "SUPER + mouse:274", button = "mouse:274" },
  back = { press = "mouse:275", button = "mouse:275" },
  forward = { press = "mouse:276", button = "mouse:276" },
}
local other_buttons = { "mouse:272", "mouse:274", "mouse:275", "mouse:276" }

local function read_settings()
  local config = os.getenv("XDG_CONFIG_HOME")
  if not config or config == "" then config = os.getenv("HOME") .. "/.config" end
  local ok, text = pcall(function()
    local file = io.open(config .. "/omarchy/extensions/hotkey-wheel.json", "r")
    if not file then return "" end
    local content = file:read("a") or ""
    file:close()
    return content
  end)
  return ok and text or ""
end

local settings = read_settings()
local trigger = triggers[settings:match('"trigger"%s*:%s*"([%w%-]+)"')] or triggers.middle
local enabled = settings:match('"enabled"%s*:%s*false') == nil
local gesture = ""
local sequence = 0
-- The gesture the open wheel belongs to, so a late close of an older wheel
-- can't end a newer hold.
local layer_gesture = nil

-- Tells the wheel through a Hyprland event ("custom>>" on the event socket)
-- rather than a process, so it opens without a launch delay. Events arrive in
-- order, and each carries where the pointer was at that moment.
local function send(message)
  hl.dispatch(hl.dsp.event(wheel_id .. " " .. message))
end
local function at_cursor(message)
  local cursor = hl.get_cursor_pos()
  send(string.format("%s %.1f %.1f", message, cursor.x, cursor.y))
end

-- Hold mode leaves keyboard focus alone to preserve the compositor's held
-- mouse state, and the held button keeps pointer focus on the app below, so
-- Escape and right-click cancel through binds of our own while the wheel is
-- open. During a hold the other buttons would click into the app below
-- unseen, so binds that do nothing take them until the wheel closes.
--
-- These binds are made once and only switched on and off: in Hyprland 0.56
-- removing a bind (unbind) removes every bind on that key, the user's too.
-- They have no description, so Omarchy's keybinding list leaves them out.
local cancel_binds, held_binds = {}, {}

local function protect(binds, on)
  for _, binding in ipairs(binds) do binding:set_enabled(on) end
end

-- Every way a gesture ends without running a slot: forget it first, so a
-- release right behind it can't run the slot, then tell the wheel.
local function cancel()
  gesture = ""
  protect(held_binds, false)
  send("cancel")
end

cancel_binds = {
  hl.bind("ESCAPE", cancel, { ignore_mods = true }),
  hl.bind("mouse:273", cancel, { ignore_mods = true }),
}
protect(cancel_binds, false)

if enabled then
  hl.bind(trigger.press, function()
    sequence = sequence + 1
    gesture = tostring(os.time()) .. "-" .. tostring(sequence)
    at_cursor("hold " .. gesture)
  end, { description = "Hotkey Wheel (hold)" })

  -- Ignores modifiers so pressing Shift mid-gesture cannot strand the wheel, and
  -- passes the release on so the button keeps working in apps otherwise.
  hl.bind(trigger.button, function()
    if gesture ~= "" then
      at_cursor("release " .. gesture)
      gesture = ""
      protect(held_binds, false)
    end
  end, { release = true, ignore_mods = true, non_consuming = true, description = "Hotkey Wheel (release)" })

  for _, button in ipairs(other_buttons) do
    if button ~= trigger.button then
      table.insert(held_binds, hl.bind(button, function() end, { ignore_mods = true }))
    end
  end
  protect(held_binds, false)
end

-- A hold that never ends (its release was lost, say to the lock screen) is
-- cancelled after a minute. It never runs a slot.
local hold_limit = 60
local hold_started = 0
local hold_timer = hl.timer(function()
  if gesture ~= "" and os.time() - hold_started >= hold_limit then cancel() end
end, { timeout = 1000, type = "repeat" })
hold_timer:set_enabled(false)

hl.on("layer.opened", function(layer)
  if layer.namespace ~= wheel_layer then return end
  layer_gesture = gesture
  protect(cancel_binds, true)
  if gesture ~= "" then
    protect(held_binds, true)
    hold_started = os.time()
    hold_timer:set_enabled(true)
  end
end)

hl.on("layer.closed", function(layer)
  if layer.namespace ~= wheel_layer then return end
  protect(cancel_binds, false)
  protect(held_binds, false)
  hold_timer:set_enabled(false)
  -- Closed during a hold (the shell restarted, say): that gesture is over.
  if gesture ~= "" and gesture == layer_gesture then gesture = "" end
  layer_gesture = nil
end)

-- Hyprland reloaded with the wheel open: the binds that would end it are
-- new and off, so the wheel is closed rather than left open. Counted loops,
-- not ipairs: Omarchy's keybinding list (SUPER + K) runs this file with a
-- stand-in `hl` whose every call returns an endless table.
local monitors = hl.get_monitors() or {}
for m = 1, #monitors do
  local layers = hl.get_layers({ monitor = monitors[m].name, namespace = wheel_layer }) or {}
  for l = 1, #layers do
    if layers[l].mapped == true then send("cancel") end
  end
end
