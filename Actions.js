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
    // Older versions pinned scripts with a scriptHash; it is dropped.
    var out = { label: action.label.trim(), icon: action.icon, command: action.command.trim() }
    if (description.trim()) out.description = description.trim()
    return out
}

// What an action does when picked, in plain words: optional, shown in the
// picker's details window.
var descriptionLimit = 600

// Where the agent prompt asks for scripts, in the home folder.
var scriptsFolder = "/.config/omarchy/extensions/hotkey-wheel-scripts"

// An action as the picker and drawer keep it: only what validateAction keeps.
function pick(action) {
    var out = { label: String(action.label).trim(), icon: String(action.icon), command: String(action.command).trim() }
    if (action.description && String(action.description).trim()) out.description = String(action.description).trim()
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

// Control, zero-width and bidi-override characters can make a script look
// different from what it runs, so the details window warns about them.
// Covers C0/C1 controls and Unicode's default-ignorable and bidi formatting
// characters, including tag characters (U+E0000 block, as surrogate pairs).
var hiddenChars = new RegExp("[\\u0000-\\u001f\\u007f-\\u009f\\u00ad\\u034f\\u061c\\u115f\\u1160\\u17b4\\u17b5"
    + "\\u180b-\\u180f\\u200b-\\u200f\\u2028-\\u202e\\u2060-\\u206f\\u3164\\ufe00-\\ufe0f\\ufeff\\uffa0\\ufff0-\\ufff8]"
    + "|\\udb40[\\udc00-\\udc7f]|\\udb40[\\udd00-\\uddef]")

// Text a person reads (a script) with hidden characters besides tabs and line breaks.
function hasHiddenChars(text) { return hiddenChars.test(String(text || "").replace(/[\t\r\n]/g, " ")) }

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
    var m = /^'([^']*)'(?=[\s;&|]|$)/.exec(text) || /^"((?:\$HOME\/|\$\{HOME\}\/)?[^"$`\\]*)"(?=[\s;&|]|$)/.exec(text)
        || /^([^\s'"\\;&|<>()`*?\[\]{}!#]+)(?=[\s;&|]|$)/.exec(text)
    if (!m || !home) return ""
    var path = m[1]
    var quote = m[0].charAt(0)
    // As the shell sees it: nothing expands in single quotes, ~ only unquoted.
    if (quote !== "'") {
        if (quote !== '"' && path.indexOf("~/") === 0) path = home + path.slice(1)
        else if (path.indexOf("$HOME/") === 0) path = home + path.slice(5)
        else if (quote === '"' && path.indexOf("${HOME}/") === 0) path = home + path.slice(7)
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
    // Other possible scripts, which the details window doesn't show.
    var shown = scriptPath(command, home)
    var words = String(command || "").split(/[\s;&|()<>"'`]+/)
    for (var w = 0; w < words.length; ++w) {
        var word = words[w].replace(/^~\//, home + "/").replace(/^\$\{?HOME\}?\//, home + "/")
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

// --- Agent prompt -----------------------------------------------------------

// A self-contained request to paste into any agent: it starts with no other
// context. Its answer is pasted into the Create new action form by hand.
function agentPrompt(request, scriptsDir) {
    var wish = String(request || "").trim() || "(ask me what I'd like)"
    return [
        "I'd like a new action for my Hotkey Wheel. It's an Omarchy shell plugin: I hold a mouse button, point at one of its slots and release, and it runs that slot's shell command through Hyprland, like a keybinding's exec.",
        "",
        "What I want it to do: " + wish,
        "",
        "Please:",
        "1. Work out a shell command that does this on my machine (Omarchy on Arch Linux, Hyprland with a Lua config, Wayland). Prefer commands that are already installed, such as omarchy-* scripts, and check that they exist. Ask me before installing anything.",
        "2. If it takes more than one line, write a new executable script in " + scriptsDir + "/ and use its full path as the command. Give it a new file name and leave files already there alone. Keep it a plain-text script under 128 KB, so the wheel can show all of it. Don't ask for administrator rights and don't download code to run; if it needs either, tell me instead of suggesting it.",
        "3. Don't run the command or the script yourself: I'll try it from the wheel. Checking that programs exist (command -v, --help, man pages) is fine.",
        "4. Don't edit the wheel's settings or custom-actions files yourself. End your answer with these four lines together in one code block, for me to copy into the wheel's Create new action form:",
        "   Name: a short name (max 64 characters)",
        "   Icon: one Nerd Font glyph, or nothing to let the wheel pick one",
        "   What it does: one to three plain sentences on what happens when I pick it, and anything it leaves running or changes for good",
        "   Command: the command, on one line"
    ].join("\n")
}

// The agent's answer (see agentPrompt): its Name, Icon, What it does and
// Command lines, for the Create new action form, copied as the code block
// they come in or with the answer around them. Tolerates markdown (bullets,
// bold keys, `code`, a fenced block under a key) and prose around the lines; when a key appears more than once (the prompt was copied
// too), the last one wins. Throws with what to tell the user.
var answerKeys = { "name": "label", "icon": "icon", "what it does": "description", "command": "command" }

function parseAnswer(text) {
    var found = {}, key = "", fence = false
    var lines = String(text || "").replace(/\r\n?/g, "\n").split("\n")
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim()
        if (/^(```|~~~)/.test(line)) {
            fence = !fence
            // Prose after a closed block isn't part of the value.
            if (!fence) key = ""
            continue
        }
        var match = /^(?:[-*•]\s+|\d+[.)]\s+)?(?:\*\*|__)?(name|icon|what it does|command)(?:\*\*|__)?\s*:\s*(?:\*\*|__)?\s*(.*)$/i.exec(line)
        if (match) {
            key = answerKeys[match[1].toLowerCase()]
            found[key] = match[2] ? [unwrap(match[2])] : []
        }
        // A blank line ends a value, unless the value is still to come.
        else if (!line) { if (!fence && key && found[key].length) key = "" }
        else if (key) found[key].push(fence ? line : unwrap(line))
    }
    if (!found.command || !found.label)
        throw new Error("Couldn't find the Name and Command lines in the clipboard. Copy the agent's code block (Name to Command) and try again.")
    if (found.command.length !== 1)
        throw new Error(found.command.length ? "The command is more than one line. Ask the agent for one line, or a script."
                                             : "The answer has no command.")
    var icon = (found.icon || []).join(" ")
    var action = {
        label: found.label.join(" "),
        // Words ("nothing", "none", "auto") mean the wheel picks one.
        icon: /[A-Za-z]{2,}/.test(icon) ? "" : icon,
        description: (found.description || []).join(" "),
        command: found.command[0]
    }
    if (!action.label || !action.command) throw new Error("The answer's name or command is empty.")
    if (action.label.length > 64 || action.icon.length > 16 || action.description.length > descriptionLimit || action.command.length > 4096)
        throw new Error("The answer is longer than the form takes. Ask the agent for a shorter name, description or command.")
    if (hasHiddenChars(action.label + action.icon + action.description + action.command))
        throw new Error("The answer has hidden characters, so it may not run what it shows. Ask the agent again.")
    return action
}

// `code` or **bold** around a whole value.
function unwrap(value) {
    var match = /^`([^`]+)`$/.exec(value) || /^\*\*(.+)\*\*$/.exec(value)
    return match ? match[1].trim() : value
}
