-- Hotkey Wheel: loaded from ~/.config/hypr/bindings.lua (the drawer's Set up
-- adds the line). Holding the trigger opens the wheel. The trigger and the
-- drawer's On switch are stored in the settings; when off, nothing is bound.
local wheel_id = "io.github.erikrjohansson.hotkey-wheel"

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
    end
  end, { release = true, ignore_mods = true, non_consuming = true, description = "Hotkey Wheel (release)" })
end

-- Hold mode leaves keyboard focus alone to preserve the compositor's held
-- mouse state, and the held button keeps pointer focus on the app below, so
-- Escape and right-click cancel through binds that exist only while our layer
-- does. Cancelling forgets the gesture first, so a release right behind it
-- cannot run the slot. During a hold the other buttons would click into the
-- app below unseen, so they do nothing until the layer closes.
local layer_bindings = {}
local other_buttons = { "mouse:272", "mouse:274", "mouse:275", "mouse:276" }
hl.on("layer.opened", function(layer)
  if layer.namespace == "omarchy-hotkey-wheel" and #layer_bindings == 0 then
    local function cancel()
      gesture = ""
      send("cancel")
    end
    layer_bindings = {
      hl.bind("ESCAPE", cancel, { ignore_mods = true, description = "Cancel Hotkey Wheel" }),
      hl.bind("mouse:273", cancel, { ignore_mods = true, description = "Cancel Hotkey Wheel (right-click)" }),
    }
    if gesture ~= "" then
      for _, button in ipairs(other_buttons) do
        if button ~= trigger.button then
          table.insert(layer_bindings, hl.bind(button, function() end,
            { ignore_mods = true, description = "Hotkey Wheel (other buttons off while held)" }))
        end
      end
    end
  end
end)
hl.on("layer.closed", function(layer)
  if layer.namespace == "omarchy-hotkey-wheel" then
    for _, binding in ipairs(layer_bindings) do binding:unbind() end
    layer_bindings = {}
  end
end)
