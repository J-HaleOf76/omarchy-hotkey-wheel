-- Runs bindings.lua against a stand-in for Hyprland's Lua API and checks the
-- wheel's binds over whole gestures: made once at load, only switched on and
-- off, never removed (removing one removes the user's binds on that key too).
-- Usage: lua tests/bindings_test.lua path/to/bindings.lua
local script = assert(arg[1], "pass the path to bindings.lua")
local base = os.tmpname()
os.remove(base)
assert(os.execute("mkdir -p '" .. base .. "/omarchy/extensions'"))
local real_getenv = os.getenv
os.getenv = function(name) if name == "XDG_CONFIG_HOME" then return base end return real_getenv(name) end
local clock = 1000
os.time = function() return clock end

local W -- the world of one load
local id = "io.github.erikrjohansson.hotkey-wheel "

local function handle(list, item)
  item.enabled = true
  function item:set_enabled(on) self.enabled = on end
  function item:is_enabled() return self.enabled end
  function item.unbind() error("a wheel bind was removed: that removes the user's binds on the key too") end
  item.remove = item.unbind
  table.insert(list, item)
  return item
end

local function load(settings, layers)
  local file = assert(io.open(base .. "/omarchy/extensions/hotkey-wheel.json", "w"))
  file:write(settings)
  file:close()
  W = { binds = {}, timers = {}, events = {}, on = {} }
  hl = {
    layer_rule = function() end,
    bind = function(keys, fn, opts) return handle(W.binds, { keys = keys, fn = fn, opts = opts or {} }) end,
    unbind = function() error("hl.unbind removes every bind on the key") end,
    timer = function(fn, opts) return handle(W.timers, { fn = fn, opts = opts }) end,
    on = function(name, fn) W.on[name] = W.on[name] or {}; table.insert(W.on[name], fn) end,
    dispatch = function(d) table.insert(W.events, d.event) end,
    dsp = { event = function(message) return { event = message } end },
    get_cursor_pos = function() return { x = 10, y = 20 } end,
    get_monitors = function() return { { name = "M" } } end,
    get_layers = function(filter)
      local out = {}
      for _, layer in ipairs(layers or {}) do
        if layer.namespace == filter.namespace then table.insert(out, layer) end
      end
      return out
    end,
  }
  dofile(script)
  W.count = #W.binds
end

local function find(keys, described)
  for _, b in ipairs(W.binds) do
    if b.keys == keys and (described == nil or (b.opts.description ~= nil) == described) then return b end
  end
end
local function fire(name, namespace) for _, fn in ipairs(W.on[name] or {}) do fn({ namespace = namespace }) end end
local function last() return W.events[#W.events] or "" end
-- The last event starts with the wheel's id and then `rest` (plain text).
local function sent(rest) return last():sub(1, #id + #rest) == id .. rest end
local function check(ok, message) if not ok then error(message, 2) end end
local function protection() -- the undescribed binds, by key
  local out = {}
  for _, b in ipairs(W.binds) do if not b.opts.description then out[b.keys] = b end end
  return out
end

-- Middle-click trigger: what is made at load.
load('{"version":1,"trigger":"middle"}')
local p = protection()
check(find("mouse:274", true) and p.ESCAPE and p["mouse:273"] and p["mouse:272"] and p["mouse:275"] and p["mouse:276"]
      and not p["mouse:274"], "binds made at load")
for _, b in pairs(p) do check(not b.enabled, "protection starts off: " .. b.keys) end
check(#W.timers == 1 and not W.timers[1].enabled, "hold timer starts off")
local hold, release = find("mouse:274", true), nil
for _, b in ipairs(W.binds) do if b.opts.release then release = b end end

-- A hold: on while open, off after; nothing new is bound.
hold.fn()
check(sent("hold ") and last():sub(-10) == " 10.0 20.0", "hold event: " .. last())
fire("layer.opened", "omarchy-hotkey-wheel")
check(p.ESCAPE.enabled and p["mouse:273"].enabled and p["mouse:272"].enabled and p["mouse:275"].enabled, "on during a hold")
check(W.timers[1].enabled, "hold timer on")
release.fn()
check(sent("release "), "release event")
check(not p["mouse:272"].enabled, "other buttons free once released")
fire("layer.closed", "omarchy-hotkey-wheel")
for _, b in pairs(p) do check(not b.enabled, "off after close: " .. b.keys) end
check(not W.timers[1].enabled, "hold timer off")
for _ = 1, 5 do hold.fn(); fire("layer.opened", "omarchy-hotkey-wheel"); release.fn(); fire("layer.closed", "omarchy-hotkey-wheel") end
check(#W.binds == W.count, "repeated gestures add no binds")

-- Other layers (the picker) change nothing.
hold.fn()
fire("layer.opened", "omarchy-hotkey-wheel-picker")
check(not p.ESCAPE.enabled, "picker layer ignored")
fire("layer.closed", "omarchy-hotkey-wheel")

-- Escape cancels: the gesture is forgotten first, so the release runs nothing.
hold.fn()
fire("layer.opened", "omarchy-hotkey-wheel")
p.ESCAPE.fn()
check(last() == id .. "cancel" and not p["mouse:272"].enabled, "Escape cancels")
local before = #W.events
release.fn()
check(#W.events == before, "release after cancel sends nothing")
fire("layer.closed", "omarchy-hotkey-wheel")

-- The wheel closed under a hold (shell restart): the release runs nothing.
hold.fn()
fire("layer.opened", "omarchy-hotkey-wheel")
fire("layer.closed", "omarchy-hotkey-wheel")
before = #W.events
release.fn()
check(#W.events == before, "closed wheel forgets its hold")

-- An older wheel closing late doesn't end a newer hold.
hold.fn()
fire("layer.opened", "omarchy-hotkey-wheel")
release.fn()
hold.fn()
fire("layer.closed", "omarchy-hotkey-wheel")
release.fn()
check(sent("release "), "newer hold survives an older close")

-- A hold whose release never comes is cancelled after a minute, never run.
hold.fn()
fire("layer.opened", "omarchy-hotkey-wheel")
clock = clock + 30
W.timers[1].fn()
check(not sent("cancel"), "a 30 s hold stays")
clock = clock + 31
W.timers[1].fn()
check(last() == id .. "cancel", "a lost hold is cancelled")
before = #W.events
release.fn()
check(#W.events == before, "and its release runs nothing")
fire("layer.closed", "omarchy-hotkey-wheel")

-- Click mode (opened without a hold): cancel binds only.
fire("layer.opened", "omarchy-hotkey-wheel")
check(p.ESCAPE.enabled and not p["mouse:272"].enabled and not W.timers[1].enabled, "click mode: cancel only")
p["mouse:273"].fn()
check(last() == id .. "cancel", "right-click cancels click mode")
fire("layer.closed", "omarchy-hotkey-wheel")

-- Back trigger: the other three buttons are covered.
load('{"version":1,"trigger":"back"}')
p = protection()
check(p["mouse:272"] and p["mouse:274"] and p["mouse:276"] and not p["mouse:275"], "back trigger protection")

-- Off: no trigger and no button binds; click mode still cancels.
load('{"version":1,"enabled":false}')
p = protection()
check(not find("mouse:274", true) and p.ESCAPE and not p["mouse:272"], "off binds no buttons")

-- Reloaded with the wheel open: it is closed, not left without its binds.
load('{"version":1}', { { namespace = "omarchy-hotkey-wheel", mapped = true } })
check(last() == id .. "cancel", "reload closes an open wheel")
load('{"version":1}', { { namespace = "omarchy-hotkey-wheel", mapped = false } })
check(#W.events == 0, "an unmapped wheel layer is left alone")

-- Omarchy's keybinding list (SUPER + K) runs the config with a stand-in hl
-- whose every unknown call returns an endless table: loading must finish and
-- list no wheel bind but the described hold and release.
local listed = {}
local noop
noop = setmetatable({}, { __index = function() return noop end, __call = function() return noop end })
hl = setmetatable({
  dsp = noop,
  bind = function(keys, _, opts)
    if opts and opts.description and opts.description ~= "" then table.insert(listed, opts.description) end
    return noop
  end,
  get_config = function() return nil end,
}, { __index = function() return noop end })
load = nil
local file = assert(io.open(base .. "/omarchy/extensions/hotkey-wheel.json", "w"))
file:write('{"version":1}')
file:close()
dofile(script)
check(#listed == 2 and listed[1] == "Hotkey Wheel (hold)" and listed[2] == "Hotkey Wheel (release)",
      "SUPER + K lists only the hold and release: " .. table.concat(listed, ", "))

os.execute("rm -rf '" .. base .. "'")
print("bindings.lua: PASS")
