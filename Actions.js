.pragma library

// Commands are intentionally shared with Omarchy's keybindings, rather than
// injecting keystrokes into whichever window happens to have focus.
var presets = [
    { label: "Terminal", icon: "", command: "omarchy launch terminal" },
    { label: "Browser", icon: "󰖟", command: "omarchy launch browser" },
    { label: "Files", icon: "󰉋", command: "xdg-open \"$HOME\"" },
    { label: "Screenshot", icon: "󰄀", command: "omarchy capture screenshot" },
    { label: "Clipboard", icon: "󰅍", command: "omarchy-shell shell toggle omarchy.clipboard" },
    { label: "Night light", icon: "󰖔", command: "omarchy toggle nightlight" },
    { label: "Play / pause", icon: "󰐎", command: "omarchy-shell media playPause" },
    { label: "Omarchy", icon: "󰣇", command: "omarchy menu toggle root" },
    { label: "Emojis", icon: "󰞅", command: "omarchy-shell shell toggle omarchy.emojis" },
    { label: "Mute", icon: "󰝟", command: "omarchy audio output volume mute-toggle" },
    { label: "Notifications", icon: "󰂚", command: "omarchy-shell notifications showHistory" },
    { label: "Theme", icon: "󰏘", command: "omarchy theme switcher" },
    { label: "Color picker", icon: "󰈊", command: "pkill hyprpicker || hyprpicker -a" },
    { label: "Screen recording", icon: "󰻃", command: "omarchy-capture-screenrecording --stop-recording || omarchy-menu toggle trigger.capture.screenrecord" },
    { label: "Apps", icon: "󰀻", command: "omarchy-menu toggle apps" },
    { label: "System menu", icon: "󰐥", command: "omarchy-menu toggle system" },
    { label: "Lock", icon: "󰌾", command: "omarchy-system-lock" },
    { label: "Next track", icon: "󰒭", command: "omarchy-shell media next" },
    { label: "Previous track", icon: "󰒮", command: "omarchy-shell media previous" },
    { label: "Volume up", icon: "󰝝", command: "omarchy-audio-output-volume raise" },
    { label: "Volume down", icon: "󰝞", command: "omarchy-audio-output-volume lower" },
    { label: "Mute microphone", icon: "󰍭", command: "omarchy-audio-input-mute" },
    { label: "Audio", icon: "󰕾", command: "omarchy-shell shell toggle omarchy.audio" },
    { label: "Bluetooth", icon: "󰂯", command: "omarchy-shell shell toggle omarchy.bluetooth" },
    { label: "Network", icon: "󰖩", command: "omarchy-shell shell toggle omarchy.network" },
    { label: "Calculator", icon: "󰃬", command: "omacalc" },
    { label: "Activity", icon: "󰍛", command: "omarchy-launch-tui 'btop'" },
    { label: "Reminders", icon: "󰀠", command: "omarchy-reminder show" }
]

// Slot counts the wheel offers, and what can open it. Each trigger names the
// Hyprland press key and the button whose release ends the gesture; the
// hotkey-wheel helper and bindings.lua use the same names.
var slotCounts = [4, 6, 8, 10, 12]
var maxSlots = 12
var triggers = [
    { value: "middle", label: "Middle-click", short: "Middle" },
    { value: "super-middle", label: "Super + middle-click", short: "Super + middle" },
    { value: "back", label: "Back side button", short: "Back" },
    { value: "forward", label: "Forward side button", short: "Forward" }
]

function triggerLabel(value) {
    for (var i = 0; i < triggers.length; ++i) if (triggers[i].value === value) return triggers[i].label
    return triggers[0].label
}

// Settings: { version: 1, enabled, slots, trigger, labels, actions }.
// `enabled` false leaves the trigger to the apps (Hyprland binds nothing).
// `actions` holds at least `slots` entries; extra ones are slots hidden by a
// smaller count, kept so raising the count brings them back. `labels` shows
// slot names under the icons.
function defaults() {
    return { version: 1, enabled: true, slots: 8, trigger: "middle", labels: true, actions: JSON.parse(JSON.stringify(presets.slice(0, 8))) }
}

function validate(data) {
    if (!data || data.version !== 1 || !Array.isArray(data.actions))
        throw new Error("Use version 1 with an actions list.")
    // Files from before the slot setting have exactly eight actions and no count.
    var slots = data.slots === undefined ? data.actions.length : data.slots
    if (slotCounts.indexOf(slots) === -1)
        throw new Error("Slots must be one of " + slotCounts.join(", ") + ".")
    if (data.actions.length < slots || data.actions.length > maxSlots)
        throw new Error("Use between " + slots + " and " + maxSlots + " actions for " + slots + " slots.")
    var trigger = data.trigger === undefined ? "middle" : data.trigger
    if (!triggers.some(function(t) { return t.value === trigger }))
        throw new Error("Unknown trigger \"" + trigger + "\".")
    var labels = data.labels === undefined ? true : data.labels
    if (typeof labels !== "boolean")
        throw new Error("Labels must be true or false.")
    var enabled = data.enabled === undefined ? true : data.enabled
    if (typeof enabled !== "boolean")
        throw new Error("Enabled must be true or false.")
    return { version: 1, enabled: enabled, slots: slots, trigger: trigger, labels: labels,
             actions: data.actions.map(validateAction) }
}

// The slots the wheel shows (none before settings first arrive).
function visible(settings) { return settings && settings.actions ? settings.actions.slice(0, settings.slots) : [] }

// A copy showing `count` slots. New slots reuse hidden ones first, then
// presets the wheel does not have yet.
function resize(settings, count) {
    var next = JSON.parse(JSON.stringify(settings))
    next.slots = count
    var used = next.actions.map(function(a) { return a.command })
    for (var i = 0; next.actions.length < count && i < presets.length; ++i)
        if (used.indexOf(presets[i].command) === -1) next.actions.push(JSON.parse(JSON.stringify(presets[i])))
    while (next.actions.length < count) next.actions.push({ label: "Empty", icon: "󰐕", command: "" })
    return next
}

function validateAction(action, index) {
    if (!action || typeof action.label !== "string" || !action.label.trim()
            || action.label.length > 64 || typeof action.icon !== "string"
            || action.icon.length > 16 || typeof action.command !== "string"
            || action.command.length > 4096 || action.command.indexOf("\u0000") !== -1)
        throw new Error("Slot " + (index + 1) + " needs a label (max 64 characters), an icon (max 16), and a command string.")
    var description = action.description === undefined ? "" : action.description
    if (typeof description !== "string" || description.length > descriptionLimit)
        throw new Error("Slot " + (index + 1) + ": the description must be text of at most " + descriptionLimit + " characters.")
    if (action.scriptHash !== undefined && !validHash(action.scriptHash))
        throw new Error("Slot " + (index + 1) + ": scriptHash must be a SHA-256 in hex.")
    var out = { label: action.label.trim(), icon: action.icon, command: action.command.trim() }
    if (description.trim()) out.description = description.trim()
    if (action.scriptHash) out.scriptHash = action.scriptHash
    return out
}

// An action saved from a reviewed script pins it: scriptHash is the SHA-256 of
// the script file as the user read it. The wheel then runs it through the
// helper, which checks the file first and, if it changed, runs nothing and
// says so (see runCommand and `hotkey-wheel checked`).
function validHash(hash) { return typeof hash === "string" && /^[0-9a-f]{64}$/.test(hash) }

// What the wheel hands to Hyprland for a slot.
// A pin whose script can't be found in the command fails closed: the helper
// gets no script, refuses, and says so.
function runCommand(action, helper, home) {
    if (!action.scriptHash) return action.command
    var script = scriptPath(action.command, home)
    return [helper, "checked", action.scriptHash, script, action.label, action.command].map(shellQuote).join(" ")
}

// Agents write their scripts in this folder, so a suggestion may only use a
// file there as the script the details window shows and pins: the command's
// first word, or the word after an interpreter. Any other mention of the
// folder (another script, `bash -- file`, `sh < file`, a full interpreter
// path) is returned, and the suggestion can't be tried or saved.
var scriptsFolder = "/.config/omarchy/extensions/hotkey-wheel-scripts"

function uncheckedFile(command, home) {
    var text = String(command || "").trim()
    var shown = scriptPath(text, home)
    var rest = text
    if (shown) {
        var lead = interpreters.exec(text)
        var after = lead ? text.slice(lead[0].length) : text
        var word = /^('[^']*'|"[^"]*"|\S+)/.exec(after)
        rest = after.slice(word ? word[0].length : 0)
    }
    var folders = [home + scriptsFolder, "~" + scriptsFolder, "$HOME" + scriptsFolder, "${HOME}" + scriptsFolder, "hotkey-wheel-scripts/"]
    for (var i = 0; i < folders.length; ++i) {
        var at = rest.indexOf(folders[i])
        if (at !== -1) return ((/\S+$/.exec(rest.slice(0, at)) || [""])[0] + rest.slice(at).split(/[\s;&|<>()"']/)[0]).replace(/^["'<]+/, "")
    }
    return ""
}

// What an action does when picked, in plain words: optional, shown in the
// picker's details window. Agents must send one with a suggestion.
var descriptionLimit = 600

// An action as the picker and drawer keep it: only what validateAction keeps.
function pick(action) {
    var out = { label: String(action.label).trim(), icon: String(action.icon), command: String(action.command).trim() }
    if (action.description && String(action.description).trim()) out.description = String(action.description).trim()
    if (validHash(action.scriptHash)) out.scriptHash = action.scriptHash
    return out
}

// Custom actions, newest first: { version: 1, commands: [action, ...] }
// in their own file. Commands put on a slot from the Custom tab are added
// when the wheel is saved. Entries that don't check out are dropped, not fatal.
var libraryLimit = 50

function validateLibrary(data) {
    var list = data && data.version === 1 && Array.isArray(data.commands) ? data.commands : []
    var out = []
    for (var i = 0; i < list.length && out.length < libraryLimit; ++i) {
        var action
        try { action = validateAction(list[i], i) } catch (e) { continue }
        if (action.command && !out.some(function(a) { return a.command === action.command })) out.push(action)
    }
    return out
}

// `added` go first; a command already in the list moves up with its new label and icon.
function remember(list, added) {
    return validateLibrary({ version: 1, commands: added.concat(list) })
}

function forget(list, command) { return list.filter(function(a) { return a.command !== command }) }

// Control, zero-width and bidi-override characters can make a command look
// different from what it runs, so suggestions from outside may not use them.
// Covers C0/C1 controls and Unicode's default-ignorable and bidi formatting
// characters, including tag characters (U+E0000 block, as surrogate pairs).
var hiddenChars = new RegExp("[\\u0000-\\u001f\\u007f-\\u009f\\u00ad\\u034f\\u061c\\u115f\\u1160\\u17b4\\u17b5"
    + "\\u180b-\\u180f\\u200b-\\u200f\\u2028-\\u202e\\u2060-\\u206f\\u3164\\ufe00-\\ufe0f\\ufeff\\uffa0\\ufff0-\\ufff8]"
    + "|\\udb40[\\udc00-\\udc7f]|\\udb40[\\udd00-\\uddef]")

// Text a person reads (a script) with hidden characters besides tabs and line breaks.
function hasHiddenChars(text) { return hiddenChars.test(String(text || "").replace(/[\t\r\n]/g, " ")) }

// Stricter than validateAction: for suggestions the user has to read before saving.
function validateProposal(action, index) {
    var checked = validateAction(action, index)
    // The description may have line breaks; nothing else hidden.
    if (hiddenChars.test(checked.label + " " + checked.command + " " + (checked.description || "").replace(/\r?\n/g, " ")))
        throw new Error("Slot " + (index + 1) + ": control, invisible or bidi characters are not allowed.")
    if (!checked.command) throw new Error("the command is empty.")
    if (!checked.description) throw new Error("say what it does when picked (the description is empty).")
    if (checked.command.length > 1000)
        throw new Error("the command is longer than 1000 characters; put it in a script and run that.")
    return checked
}

// The script a command runs, when its first word (or the word after an
// interpreter such as bash or python3) is a plain path in the home folder, so
// the details window can show it. The word may be quoted as a whole; anything
// else shell-like (escapes, variables other than a leading $HOME, globs,
// operators) means no script rather than a guess.
var interpreters = /^(?:bash|sh|zsh|dash|fish|python3?|perl|ruby|node|lua)\s+/

function scriptPath(command, home) {
    var text = String(command || "").trim()
    var lead = interpreters.exec(text)
    if (lead) text = text.slice(lead[0].length)
    var m = /^'([^']*)'(?=[\s;&|]|$)/.exec(text) || /^"([^"$`\\]*)"(?=[\s;&|]|$)/.exec(text)
        || /^([^\s'"\\;&|<>()`*?\[\]{}!#]+)(?=[\s;&|]|$)/.exec(text)
    if (!m || !home) return ""
    var path = m[1]
    var quote = m[0].charAt(0)
    // As the shell sees it: nothing expands in single quotes, ~ only unquoted.
    if (quote !== "'") {
        if (quote !== '"' && path.indexOf("~/") === 0) path = home + path.slice(1)
        else if (quote !== '"' && path.indexOf("$HOME/") === 0) path = home + path.slice(5)
        if (/^~|\$/.test(path)) return ""
    }
    return path.indexOf(home + "/") === 0 && path.indexOf("/../") === -1 ? path : ""
}

function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

// A draft after the settings file changed under it (another monitor's drawer
// or a hand edit): what the user has not touched since `old` follows
// `incoming`; edits are kept. Slots keep their places: an edited slot past the
// file's end stays where it is, and untouched ones after it are dropped.
function merge(draft, old, incoming) {
    var merged = JSON.parse(JSON.stringify(draft))
    merged.trigger = incoming.trigger
    merged.enabled = incoming.enabled
    if (merged.slots === old.slots) merged.slots = incoming.slots
    if (merged.labels === old.labels) merged.labels = incoming.labels
    var count = merged.actions.length
    for (var i = 0; i < count; ++i)
        if (i < incoming.actions.length && same(merged.actions[i], old.actions[i])) merged.actions[i] = incoming.actions[i]
    for (var j = count; j < incoming.actions.length && old.actions[j] === undefined; ++j)
        merged.actions.push(incoming.actions[j])
    while (merged.actions.length > incoming.actions.length
           && same(merged.actions[merged.actions.length - 1], old.actions[merged.actions.length - 1]))
        merged.actions.pop()
    return merged
}

// Things worth a second look before running a command or its script, in
// plain words. Hints, not a guarantee: the command and script are the truth.
// Hints, not a check: plain pattern matches that miss plenty.
var warningChecks = [
    [/\b(curl|wget)\b[^\n|]*\|\s*(\S*\/)?(sudo\s+)?(\S*\/)?(ba|z|da|fi)?sh\b|\b(ba|z|da)?sh\s+(-c\s+)?["']?\$\(\s*(curl|wget)\b|<\(\s*(curl|wget)\b/,
     "Downloads code from the internet and runs it."],
    [/(^|[\s;&|(])(\S*\/)?(sudo|pkexec|doas|run0)\s/, "Asks for administrator rights."],
    [/(^|[\s;&|(])(\S*\/)?rm\s+(-\S+\s+)*(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)\b/, "Deletes files or folders."],
    [/(^|[\s;&|(])eval\s|base64\s+(-\S+\s+)*(-[a-zA-Z]*d[a-zA-Z]*|--decode)\b/, "Runs code it builds or decodes, which you can't read here."]
]

function warnings(command, scriptText, home) {
    var out = []
    var texts = [String(command || ""), String(scriptText || "")]
    for (var i = 0; i < warningChecks.length; ++i)
        for (var t = 0; t < texts.length; ++t)
            if (warningChecks[i][0].test(texts[t])) {
                out.push((t === 0 ? "The command: " : "The script: ") + warningChecks[i][1])
                break
            }
    // Other possible scripts, which this window doesn't show or pin.
    var shown = scriptPath(command, home)
    var words = String(command || "").split(/[\s;&|()<>"'`]+/)
    for (var w = 0; w < words.length; ++w) {
        var word = words[w].replace(/^~\//, home + "/").replace(/^\$HOME\//, home + "/")
        if (/\.(sh|bash|zsh|py|pl|rb|js|lua)$/.test(word) && word !== shown) {
            out.push("The command mentions " + words[w] + ", another possible script that isn't shown or checked here.")
            break
        }
    }
    if (/(^|[\s;&|(])(source|\.)\s+\S|(^|[\s"'=])(~\/|\$HOME\b|\$\{HOME\})\S*\.(sh|bash|py|pl|rb|js|lua)\b/.test(String(scriptText || "")))
        out.push("The script uses other files, which aren't shown or checked here.")
    return out
}

function selection(x, y, centerX, centerY, deadZone, count) {
    var dx = x - centerX, dy = y - centerY
    if (dx * dx + dy * dy < deadZone * deadZone || count < 1) return -1
    var angle = Math.atan2(dy, dx) + Math.PI / 2
    var step = Math.PI * 2 / count
    return Math.floor((angle + step / 2 + Math.PI * 2) / step) % count
}

function center(value, extent, length) {
    return Math.max(extent, Math.min(length - extent, value))
}

function luaString(value) {
    var quoted = '"'
    for (var i = 0; i < value.length; ++i) {
        var code = value.charCodeAt(i)
        quoted += (code < 32 || code === 34 || code === 92)
            ? "\\" + ("000" + code).slice(-3) : value[i]
    }
    return quoted + '"'
}

function shellQuote(value) { return "'" + String(value).replace(/'/g, "'\\''") + "'" }

// --- Picker catalogue -------------------------------------------------------

// Themed glyphs, so picked apps and binds match the monochrome wheel. The first
// matching pattern wins; anything unknown gets a generic glyph.
var glyphs = [
    [/terminal|alacritty|ghostty|kitty|foot\b|tmux|herdr/, ""],
    [/firefox/, "󰈹"], [/webcam|camera/, "󰖠"], [/chrom|brave|vivaldi|browser|zen\b|\bweb\b/, "󰖟"],
    [/spotify|music|cliamp|player|play\b|pause/, "󰎆"],
    [/discord|vesktop/, "󰙯"], [/signal|telegram|whatsapp|chat|slack|message/, "󰍡"],
    [/\bcode\b|\bzed\b|vim\b|editor/, "󰨞"], [/obsidian|note|typora|writer|document/, "󰠮"],
    [/nautilus|files|file manager|folder/, "󰉋"], [/steam|game|lutris/, "󰊴"],
    [/gimp|inkscape|krita|pinta|image|photo|imv/, "󰋩"], [/video|mpv|vlc|kdenlive|obs|record/, "󰕧"],
    [/mail|thunderbird/, "󰇮"], [/calendar/, "󰃭"], [/calculator|omacalc/, "󰃬"],
    [/password|1password|bitwarden|keepass/, "󰌋"], [/docker|lazydocker/, "󰡨"],
    [/btop|htop|activity|system monitor/, "󰍛"], [/setting|config|preference/, "󰒓"],
    [/screenshot|capture/, "󰄀"], [/color picker|hyprpicker/, "󰈊"], [/clipboard/, "󰅍"],
    [/emoji/, "󰞅"], [/\block/, "󰌾"], [/night ?light/, "󰖔"], [/theme/, "󰏘"],
    [/notification/, "󰂚"], [/mute|microphone/, "󰝟"], [/volume up|raise/, "󰝝"],
    [/volume down|lower/, "󰝞"], [/volume|audio|sound/, "󰕾"], [/next track/, "󰒭"],
    [/previous track/, "󰒮"], [/brightness/, "󰃠"], [/bluetooth/, "󰂯"], [/wifi|network/, "󰖩"],
    [/fullscreen|full screen|full width/, "󰊓"], [/close/, "󰅖"], [/float/, "󰖲"],
    [/workspace/, "󰕰"], [/focus|swap|move window|split|group|window/, "󰖯"],
    [/keybind|keyboard/, "󰌌"], [/system menu|power|shutdown|reboot/, "󰐥"], [/menu|launch app|apps/, "󰀻"]
]
var fallbackGlyph = "󰣆"

// The name decides first; the command or id only breaks ties for unknown names.
function glyphFor(name, extra) {
    var texts = [name, extra]
    for (var t = 0; t < texts.length; ++t) {
        var value = String(texts[t] || "").toLowerCase()
        for (var i = 0; value && i < glyphs.length; ++i)
            if (glyphs[i][0].test(value)) return glyphs[i][1]
    }
    return fallbackGlyph
}

// Desktop entries from Quickshell's DesktopEntries, minus the ids Omarchy's
// launcher hides (launcher.hides, one id per line). Launching through
// gtk-launch under uwsm matches Omarchy's own app menu.
function appItems(entries, hidesText) {
    var hidden = {}
    String(hidesText || "").split("\n").forEach(function(line) {
        var id = line.trim().replace(/\.desktop$/, "")
        if (id) hidden[id] = true
    })
    var out = []
    for (var i = 0; i < entries.length; ++i) {
        var entry = entries[i]
        if (!entry || entry.noDisplay || !entry.id || !entry.name || hidden[entry.id]) continue
        out.push({
            label: String(entry.name).slice(0, 64),
            detail: String(entry.genericName || entry.comment || ""),
            keywords: [entry.id].concat(entry.keywords || []).join(" "),
            icon: glyphFor(entry.name + " " + (entry.genericName || ""), entry.id),
            command: "uwsm-app -- gtk-launch " + shellQuote(entry.id + ".desktop")
        })
    }
    return out.sort(function(a, b) { return a.label.localeCompare(b.label) })
}

function presetItems() {
    return presets.map(function(p) {
        return { label: p.label, detail: "", keywords: p.command, icon: p.icon, command: p.command }
    })
}

// The command that replays a bind the way omarchy-menu-keybindings does.
function bindingCommand(dispatcher, arg) {
    if (!dispatcher) return ""
    if (!arg) return ["exec", "lua", "sendshortcut"].indexOf(dispatcher) === -1
        ? "hyprctl dispatch " + shellQuote(dispatcher) : ""
    if (dispatcher === "exec") return arg
    if (dispatcher === "lua") return "hyprctl dispatch " + shellQuote(arg)
    if (dispatcher === "sendshortcut") {
        var parts = arg.split(",").map(function(s) { return s.trim() })
        var key = function(state) {
            return "hyprctl dispatch " + shellQuote("hl.dsp.send_key_state({ mods = " + luaString(parts[0])
                + ", key = " + luaString(parts[1] || "") + ", state = \"" + state + "\", window = "
                + luaString(parts[2] || "activewindow") + " })")
        }
        return key("down") + " && sleep 0.05 && " + key("up")
    }
    return "hyprctl dispatch " + shellQuote(dispatcher) + " " + shellQuote(arg)
}

// Records are "COMBO → Description<TAB>dispatcher<TAB>arg", one per line.
// Binds without a replayable dispatcher, pointer drags, and the wheel's own
// binds are left out.
function bindingItems(text) {
    var out = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; ++i) {
        var fields = lines[i].split("\t")
        if (fields.length < 3) continue
        var display = fields[0].split("→")
        if (display.length < 2) continue
        var combo = display[0].trim().replace(/\s+/g, " ")
        var label = display.slice(1).join("→").trim()
        var command = bindingCommand(fields[1], fields.slice(2).join("\t"))
        if (!command || !label || /MOUSE BUTTON|mouse_/.test(combo) || /Hotkey Wheel/.test(label)) continue
        out.push({ label: label.slice(0, 64), detail: combo, keywords: command,
                   icon: glyphFor(label, command), command: command })
    }
    return out
}

// Prefix matches on the label first, then any word or detail/keyword match.
function filter(items, query) {
    var q = String(query || "").trim().toLowerCase()
    if (!q) return items
    var first = [], rest = []
    for (var i = 0; i < items.length; ++i) {
        var item = items[i]
        var label = item.label.toLowerCase()
        if (label.indexOf(q) === 0) first.push(item)
        else if (label.indexOf(q) !== -1
                 || (item.detail + " " + item.keywords).toLowerCase().indexOf(q) !== -1) rest.push(item)
    }
    return first.concat(rest)
}

// --- Agents -----------------------------------------------------------------

// Coding agents the picker can open in a terminal, found on PATH.
var agents = [
    { id: "claude", label: "Claude Code" },
    { id: "codex", label: "Codex" }
]

// A self-contained request: the agent starts with no other context. It ends
// with the propose IPC, so the suggestion lands in the picker for the user to
// read and try. The agent must not run it first.
function agentPrompt(slotNumber, current, request, scriptsDir) {
    var now = current && current.command ? current.label + " → " + current.command : "nothing (empty slot)"
    var wish = String(request || "").trim() || "(ask me what I'd like)"
    return [
        "I'd like to change slot " + slotNumber + " of my Hotkey Wheel. It's an Omarchy shell plugin: I hold a mouse button, point at one of its slots and release, and it runs that slot's shell command through Hyprland, like a keybinding's exec.",
        "",
        "What I want slot " + slotNumber + " to do: " + wish,
        "It currently runs: " + now,
        "",
        "Please:",
        "1. Work out a shell command that does this on my machine (Omarchy on Arch Linux, Hyprland with a Lua config, Wayland). Prefer commands that are already installed, such as omarchy-* scripts, and check that they exist. Ask me before installing anything.",
        "2. If it takes more than one line, write a new executable script in " + scriptsDir + "/ and use its full path as the command. Give it a new file name; never change or overwrite a file that is already there, because my saved slots may run it and the change would apply without my review. Keep it a plain-text script under 128 KB so I can read all of it. Don't use sudo and don't download code to run; if it needs either, tell me instead of suggesting it.",
        "3. Don't run the command or the script yourself, not even to test it: I haven't approved it yet, and the wheel lets me try it before I use it. Checking that programs exist (command -v, --help, man pages) is fine.",
        "4. Send it to the wheel with this command. Don't edit the wheel's settings or custom-actions files yourself:",
        "   omarchy-shell io.github.erikrjohansson.hotkey-wheel propose " + slotNumber + " \"<label>\" \"<icon>\" \"<command>\" \"<what it does>\"",
        "   The label is a short name (max 64 characters). The icon is one Nerd Font glyph, or \"\" to let the wheel pick one. \"What it does\" is one to three plain sentences for me (max " + descriptionLimit + " characters): what happens when I pick this slot, and anything it leaves running or changes for good. The reply says whether it was accepted.",
        "5. Tell me the same in a sentence or two. The suggestion opens in a window on the wheel with your description, the command and any script in full, where I can try it and choose whether to save it. Nothing runs or changes until I do.",
        "",
        "To see the current slots: omarchy-shell io.github.erikrjohansson.hotkey-wheel slots"
    ].join("\n")
}
