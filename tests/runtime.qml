import QtQuick
import Quickshell
import Quickshell.Io
import "PLUGIN_PATH" as Plugin
import "ACTIONS_PATH" as Actions

ShellRoot {
    id: root
    // The real bar drawer, never opened here (that would map its windows).
    Plugin.WheelDrawer { id: drawer }
    // The details window: a custom action's script, and a pipe it must not wait on.
    Plugin.ActionDetails { id: details }
    Plugin.ActionDetails { id: pipeDetails }
    // The picker card on its own (no window): it opens on the slot's tab.
    Plugin.PickerCard { id: card; width: 560; height: 620 }
    Plugin.ActionDetails { id: latinDetails }
    FileView { id: scriptA; path: Quickshell.env("HOME") + "/scripts/a.sh"; atomicWrites: true; printErrors: false }
    Plugin.HotkeyWheel {
        id: wheel
        Component.onCompleted: {
            // Exercise the real layer object without mapping a test overlay.
            for (var i = 0; i < data.length; ++i)
                if ("exclusionMode" in data[i]) data[i].visible = false
        }
    }
    // The fake hyprctl reports this position; release() reads it again.
    FileView { id: cursor; path: Quickshell.env("WHEEL_TEST_CURSOR"); blockWrites: true }
    FileView {
        id: settingsFile
        path: Quickshell.env("XDG_CONFIG_HOME") + "/omarchy/extensions/hotkey-wheel.json"
        blockWrites: true
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
    // A create-form field's text, found by its placeholder (the ids are the card's own).
    function cardText(name) {
        var placeholder = name === "labelField" ? "Name" : "Command (empty disables the slot)"
        var find = function(item) {
            if (item.placeholderText === placeholder) return item
            var kids = (item.children || []).concat(item.contentItem && item.contentItem !== item ? [item.contentItem] : [])
            for (var i = 0; i < kids.length; ++i) { var hit = find(kids[i]); if (hit) return hit }
            return null
        }
        return find(card).text
    }
    Timer {
        interval: 200; running: true
        onTriggered: {
            check(Actions.selection(100, 100, 100, 100, 28, 8) === -1, "centre cancels")
            for (var i = 0; i < 8; ++i) {
                var angle = -Math.PI / 2 + i * Math.PI / 4
                check(Actions.selection(100 + 80 * Math.cos(angle), 100 + 80 * Math.sin(angle), 100, 100, 28, 8) === i, "direction " + i)
            }
            check(Actions.center(0, 100, 800) === 100 && Actions.center(800, 100, 800) === 700, "edge clamp")
            var rejected = false
            try { Actions.validate({version: 1, actions: [{label: "broken"}]}) } catch (e) { rejected = true }
            check(rejected, "malformed settings rejected")
            var binds = Actions.bindingItems([
                "SUPER + W                           \u2192 Close window\tlua\thl.dsp.window.close()",
                "SUPER + RETURN                      \u2192 Terminal\texec\tomarchy-launch-terminal",
                "SUPER + C                           \u2192 Universal copy\t\t",
                "SUPER + LEFT MOUSE BUTTON           \u2192 Move window\tlua\thl.dsp.window.drag()",
                "MIDDLE MOUSE BUTTON                 \u2192 Hotkey Wheel (hold)\tlua\tx()",
                "SHIFT ALT + L                       \u2192 Copy URL\tsendshortcut\tSHIFT ALT,L,"
            ].join("\n"))
            check(binds.length === 3, "unreplayable, drag and wheel binds skipped")
            check(binds[0].command === "hyprctl dispatch 'hl.dsp.window.close()'" && binds[0].detail === "SUPER + W", "lua bind")
            check(binds[1].command === "omarchy-launch-terminal", "exec bind")
            check(binds[2].command.indexOf('mods = "SHIFT ALT", key = "L", state = "down", window = "activewindow"') !== -1
                  && binds[2].command.indexOf('state = "up"') !== -1, "shortcut bind")
            check(Actions.shellQuote("it's") === "'it'\\''s'", "shell quoting")
            var apps = Actions.appItems([{ id: "b", name: "Beta" }, { id: "a", name: "Alpha" },
                { id: "gone", name: "Gone" }, { id: "x", name: "Hidden", noDisplay: true }], "gone.desktop\n")
            check(apps.length === 2 && apps[0].label === "Alpha" && apps[0].command === "uwsm-app -- gtk-launch 'a.desktop'", "app list")
            var found = Actions.filter([{ label: "Calendar", detail: "", keywords: "" },
                { label: "Big Cal", detail: "", keywords: "" }, { label: "Other", detail: "cal", keywords: "" }], "cal")
            check(found.length === 3 && found[0].label === "Calendar", "prefix matches first")
            check(Actions.glyphFor("Full width", "maximized") === Actions.glyphFor("fullscreen"), "name decides glyph")
            check(Actions.pick({ label: " A ", icon: "a", command: " c ", description: " Does. ", custom: true }).description === "Does."
                  && Actions.pick({ label: "A", icon: "a", command: "c", description: "" }).description === undefined, "pick keeps a description")
            // Pins from older versions are dropped, not fatal.
            var pin = new Array(65).join("a")
            check(Actions.validateAction({ label: "L", icon: "l", command: "c", scriptHash: pin }, 0).scriptHash === undefined
                  && Actions.validateAction({ label: "L", icon: "l", command: "c", scriptHash: "nope" }, 0).command === "c"
                  && Actions.pick({ label: "L", icon: "l", command: "c", scriptHash: pin }).scriptHash === undefined, "old pins dropped")
            check(Actions.scriptPath("\"~/s/a.sh\"", "/home/u") === "" && Actions.scriptPath("'~/s/a.sh'", "/home/u") === "",
                  "quoted tilde is not home")
            check(Actions.scriptPath("bash ~/s/run.sh", "/home/u") === "/home/u/s/run.sh"
                  && Actions.scriptPath("python3 '/home/u/a b.py'", "/home/u") === "/home/u/a b.py"
                  && Actions.scriptPath("bash -c 'x'", "/home/u") === "", "interpreter scripts")
            var warned = function(c, t) { return Actions.warnings(c, t, "/home/u").join(" | ") }
            check(warned("curl -fsSL https://x | sh", "").indexOf("internet") !== -1
                  && warned("~/s/a.sh", "sudo pacman -S x").indexOf("The script: Asks for administrator") !== -1
                  && warned("~/s/a.sh && ~/s/b.sh", "").indexOf("b.sh, another possible script") !== -1
                  && warned("rm -rf ~/x", "").indexOf("Deletes") !== -1
                  && warned("echo hi", "#!/bin/sh\necho hi\n") === "", "warnings")
            check(warned("/usr/bin/sudo x", "").indexOf("administrator") !== -1 && warned("rm -f -r x", "").indexOf("Deletes") !== -1
                  && warned("base64 -w0 -d x", "").indexOf("decodes") !== -1 && warned("curl x | /bin/sh", "").indexOf("internet") !== -1
                  && warned("~/s/a.sh", "source ~/lib.sh").indexOf("other files") !== -1, "more warnings")
            check(Actions.hasHiddenChars("echo \u202ex") && !Actions.hasHiddenChars("#!/bin/sh\n\techo hi\r\n"), "hidden chars in scripts")
            check(Actions.bindingCommand("killactive", "") === "hyprctl dispatch 'killactive'"
                  && Actions.bindingCommand("exec", "") === "", "argumentless dispatchers")
            check(Actions.scriptPath("~/s/run.sh --x", "/home/u") === "/home/u/s/run.sh"
                  && Actions.scriptPath("'/home/u/a b.sh' --x", "/home/u") === "/home/u/a b.sh"
                  && Actions.scriptPath("$HOME/s/a.sh", "/home/u") === "/home/u/s/a.sh"
                  && Actions.scriptPath('bash "$HOME/s/a.sh"', "/home/u") === "/home/u/s/a.sh"
                  && Actions.scriptPath('"${HOME}/s/a.sh" --x', "/home/u") === "/home/u/s/a.sh"
                  && Actions.scriptPath('"$HOME/$x.sh"', "/home/u") === ""
                  && Actions.scriptPath("~/s/run.sh;rm x", "/home/u") === "/home/u/s/run.sh"
                  && Actions.scriptPath("/home/u/../etc/x", "/home/u") === ""
                  && Actions.scriptPath("/usr/bin/foo", "/home/u") === "", "script path")
            var asked = Actions.agentPrompt("blur my webcam", "/s")
            check(asked.indexOf("Command: the command") !== -1 && asked.indexOf("blur my webcam") !== -1 && asked.indexOf("propose") === -1
                  && !/slot \d|currently/.test(asked) && asked.indexOf("/s/") !== -1, "agent prompt")
            check(asked.indexOf("Don't run the command") !== -1, "agents told not to run it")
            // The agent's answer, copied whole, with the markdown agents like.
            var answer = Actions.parseAnswer("Here you go:\n\n- **Name:** Webcam blur\n- **Icon:** 󰄀\n"
                + "- **What it does:** Turns the webcam's\nbackground blur on or off.\n- **Command:** `~/s/blur.sh`\n\nIt toggles a file.")
            check(answer.label === "Webcam blur" && answer.icon === "󰄀" && answer.command === "~/s/blur.sh"
                  && answer.description === "Turns the webcam's background blur on or off.", "answer with markdown")
            var fenced = Actions.parseAnswer(asked + "\n\nName: Blur\nIcon: nothing\nWhat it does: Blurs.\nCommand:\n```bash\nblur --on\n```\nDone.")
            check(fenced.label === "Blur" && fenced.icon === "" && fenced.command === "blur --on", "prompt copied too, fenced command, icon word")
            var block = Actions.parseAnswer("```\nName: Night light\nIcon: 󰖔\nWhat it does: Toggles it.\nCommand: omarchy-toggle-nightlight\n```")
            check(block.label === "Night light" && block.description === "Toggles it." && block.command === "omarchy-toggle-nightlight",
                  "the four lines as one code block")
            check(asked.indexOf("one code block") !== -1, "prompt asks for a code block")
            var refusal = function(text) { try { Actions.parseAnswer(text); return "" } catch (e) { return e.message } }
            check(refusal("Sure, I can help.").indexOf("Name and Command") !== -1
                  && refusal("Name: x\nCommand:\n```\na\nb\n```").indexOf("more than one line") !== -1
                  && refusal("Name: x\nCommand: echo \u202ex").indexOf("hidden") !== -1, "answers it refuses")
            check(!wheel.opened && !wheel.pendingCommand, "idle at startup")
            wheel.releaseGesture("early-release")
            wheel.open('{"mode":"hold","token":"early-release"}')
            check(!wheel.opened && !wheel.locating, "release IPC arriving before press is ignored")
            wheel.open('{"mode":"hold"}')
            wheel.release()
            check(!wheel.opened && !wheel.locating, "release before cursor reply cancels")
            late.start()
        }
    }
    Timer {
        id: late; interval: 150
        onTriggered: {
            check(!wheel.opened, "late cursor reply cannot reopen")
            wheel.open('{"mode":"hold"}')
            opened.start()
        }
    }
    Timer {
        id: opened; interval: 150
        onTriggered: {
            check(wheel.opened && wheel.holding, "hold opens")
            wheel.point(wheel.originX, wheel.originY)
            wheel.release()
            centred.start()
        }
    }
    Timer {
        id: centred; interval: 150
        onTriggered: {
            check(!wheel.opened && !wheel.pendingCommand, "centre release runs nothing")
            // The bar drawer writes this file and then calls the reload IPC.
            settingsFile.setText(JSON.stringify({ version: 1, actions: [
                { label: "Test action", icon: "x", command: "printf hotkey-wheel-test" }
            ].concat(wheel.actions.slice(1)) }))
            saved.start()
        }
    }
    Timer {
        id: saved; interval: 200
        onTriggered: {
            wheel.reload()
            applied.start()
        }
    }
    Timer {
        id: applied; interval: 150
        onTriggered: {
            check(wheel.actions[0].label === "Test action", "reload applies saved settings")
            check(!wheel.configError, "save has no error")
            wheel.open('{"mode":"hold"}')
            launch.start()
        }
    }
    Timer {
        id: launch; interval: 150
        onTriggered: {
            check(wheel.opened, "reopened")
            // (The unmapped test panel is small, so this wheel is clamped.)
            wheel.point(wheel.originX + 5, wheel.originY + 5)
            check(wheel.selected === -1, "nothing picked before the pointer moves")
            wheel.point(wheel.centerX, wheel.centerY - wheel.radius * 0.7)
            check(wheel.selected === 0, "drawn top selects first slot")
            wheel.point(wheel.centerX + wheel.innerRadius * 0.5, wheel.centerY)
            check(wheel.selected === -1, "clamped hold: the drawn hub picks nothing")
            // Tracking last saw the origin; the pointer reached the top just
            // before release. The position read on release must win.
            wheel.point(wheel.originX, wheel.originY)
            cursor.setText(JSON.stringify({ x: wheel.targetScreen.x + wheel.centerX,
                                            y: wheel.targetScreen.y + wheel.centerY - wheel.radius * 0.7 }))
            wheel.release()
            wheel.release()
            check(wheel.opened && !wheel.pendingCommand, "release waits for the final position")
            done.start()
        }
    }
    Timer {
        id: done; interval: 200
        onTriggered: {
            check(!wheel.pendingCommand, "dispatch completed")
            // Click mode hit-tests the drawn wheel, wherever it was clamped to.
            wheel.holding = false
            wheel.originX = 3; wheel.originY = 3
            wheel.point(wheel.centerX, wheel.centerY - wheel.radius * 0.7)
            check(wheel.selected === 0, "click mode: drawn top segment is slot 1")
            wheel.point(wheel.centerX + wheel.innerRadius * 0.5, wheel.centerY)
            check(wheel.selected === -1, "click mode: hub selects nothing")
            wheel.point(wheel.centerX, wheel.centerY - wheel.radius * 1.5)
            check(wheel.selected === -1, "click mode: outside the wheel selects nothing")
            // The hold trigger pressed over open click mode leaves it alone.
            var wasOpened = wheel.opened
            wheel.opened = true
            wheel.open('{"mode":"hold","token":"over-click-mode"}')
            check(wheel.opened && !wheel.holding && !wheel.locating && wheel.gestureToken !== "over-click-mode",
                  "hold trigger ignored while click mode is open")
            // Click mode from keys or a dial: scroll steps a notch at a time, and
            // running a slot takes a plain, fresh press (nothing here runs a command).
            wheel.opened = true
            wheel.selected = -1
            wheel.scroll(-60)
            check(wheel.selected === -1, "half a notch moves nothing")
            wheel.scroll(-60)
            check(wheel.selected === 0 && isFinite(wheel.steeredAt.x), "scroll down picks the first slot")
            wheel.scroll(-240)
            check(wheel.selected === 2, "two notches, two slots")
            wheel.scroll(120)
            check(wheel.selected === 1, "scroll up goes back")
            check(wheel.keyPressed(Qt.Key_Down, 0, false) && wheel.selected === 2, "Down steps forward")
            check(!wheel.keyPressed(Qt.Key_Space, Qt.ControlModifier, false) && !wheel.keyPressed(Qt.Key_Return, Qt.AltModifier, false)
                  && !wheel.keyPressed(Qt.Key_3, Qt.MetaModifier, false) && !wheel.keyPressed(Qt.Key_Space, 0, true)
                  && wheel.opened && !wheel.pendingCommand, "Ctrl/Alt/Super + key or a held key runs nothing")
            wheel.holding = true
            check(!wheel.keyPressed(Qt.Key_Down, 0, false) && wheel.selected === 2, "keys don't steer a hold")
            wheel.scroll(-120)
            check(wheel.selected === 2, "scroll doesn't steer a hold")
            wheel.holding = false
            // A slot picked by keys stays through a small nudge of the pointer; a real move takes over.
            check(wheel.keyPressed(Qt.Key_Down, 0, false) && wheel.selected === 3, "Down from slot 3")
            wheel.pointerMoved(wheel.steeredAt.x + 5, wheel.steeredAt.y + 5)
            check(wheel.selected === 3, "a small nudge keeps the keyboard pick")
            wheel.pointerMoved(wheel.centerX, wheel.centerY - wheel.radius * 0.7)
            check(wheel.selected === 0 && !isFinite(wheel.steeredAt.x), "a real move picks by pointer again")
            wheel.scroll(-120)
            wheel.pointerMoved(wheel.steeredAt.x - 4, wheel.steeredAt.y)
            check(wheel.selected === 1, "a small nudge keeps the scroll pick")
            // Space runs the selected slot (slot 1's test command; runtime.py counts the dispatch).
            wheel.scroll(120)
            check(wheel.selected === 0 && wheel.keyPressed(Qt.Key_Space, 0, false) && !wheel.opened
                  && wheel.pendingCommand === "printf hotkey-wheel-test", "Space runs the selection")
            wheel.opened = wasOpened
            // Drawer: picks are trimmed, saved, and the draft ends clean.
            // (Opening re-reads the file; this drawer is never opened.)
            drawer.reload()
            drawerPick.start()
        }
    }
    Timer {
        id: drawerPick; interval: 200
        onTriggered: {
            check(drawer.saved.actions[0].label === "Test action", "drawer reads the saved wheel")
            drawer.assign(1, { label: " Pad ", icon: "p", command: " echo pad  ", custom: true })
            check(drawer.dirty && drawer.draft.actions[1].command === "echo pad", "pick normalised")
            drawer.setLabels(false)
            drawer.save()
            drawerSaved.start()
        }
    }
    Timer {
        id: drawerSaved; interval: 300
        onTriggered: {
            check(drawer.saving === null && !drawer.dirty && drawer.saved.actions[1].label === "Pad"
                  && drawer.saved.labels === false, "drawer save completes clean")
            check(drawer.library.length === 1 && drawer.library[0].command === "echo pad"
                  && Object.keys(drawer.customPicks).length === 0, "saved custom command remembered")
            var mem = Actions.remember([{ label: "Old", icon: "o", command: "a" }, { label: "B", icon: "b", command: "b" }],
                                       [{ label: "New", icon: "n", command: "a" }, { label: "E", icon: "e", command: "" }])
            check(mem.length === 2 && mem[0].label === "New" && mem[1].command === "b", "remember moves up, skips empty")
            check(Actions.forget(mem, "a").length === 1 && Actions.validateLibrary({ version: 1, commands: [{ label: 1 }] }).length === 0,
                  "forget and bad entries")
            // A file cut to eight slots leaves an edit on slot 12 where it was.
            var twelve = []
            for (var s = 0; s < 12; ++s) twelve.push({ label: "S" + s, icon: "s", command: "s" + s })
            var oldWheel = { version: 1, enabled: true, slots: 12, trigger: "middle", labels: true, actions: twelve }
            var edited = JSON.parse(JSON.stringify(oldWheel))
            edited.actions[11] = { label: "Mine12", icon: "m", command: "mine12" }
            var cut = { version: 1, enabled: true, slots: 8, trigger: "middle", labels: true,
                        actions: twelve.slice(0, 8).map(function(a) { return { label: "N" + a.label, icon: "n", command: "n" + a.command } }) }
            var merged = Actions.merge(edited, oldWheel, cut)
            check(merged.actions.length === 12 && merged.actions[11].label === "Mine12" && merged.actions[7].label === "NS7"
                  && merged.actions[8].label === "S8" && merged.slots === 8, "merge keeps an edited slot in its place")
            var untouched = Actions.merge(oldWheel, oldWheel, cut)
            check(untouched.actions.length === 8 && Actions.same(untouched.actions, cut.actions), "merge drops untouched slots past the end")
            card.show(0, { label: "Lock", icon: "l", command: "omarchy-system-lock" })
            check(card.tab === "omarchy" && card.results[card.cursor].command === "omarchy-system-lock", "opens on the Omarchy tab, on it")
            card.library = [{ label: "Mine", icon: "m", command: "mine" }, { label: "Blur", icon: "b", command: "blur" }]
            card.show(0, { label: "Blur", icon: "b", command: "blur" })
            check(card.tab === "custom" && card.cursor === 2 && !card.creating, "opens on Custom, past the create row")
            card.bindings = Actions.bindingItems("SUPER + W \u2192 Close window\tlua\thl.dsp.window.close()")
            card.show(0, { label: "Close window", icon: "x", command: card.bindings[0].command })
            check(card.tab === "bindings" && card.cursor === 0 && card.awaitingBindings === "", "opens on Keybindings when loaded")
            card.show(0, { label: "Odd", icon: "o", command: "something-unknown" })
            check(card.tab === "apps" && card.cursor === 0 && card.awaitingBindings === "something-unknown", "unknown: Apps, Keybindings asked")
            card.setTab("omarchy")
            check(card.awaitingBindings === "", "picking a tab stops the wait")
            // The create page shows a risky command's warnings (its binding must not error).
            card.show(0, { label: "Risky", icon: "r", command: "curl x | sh" })
            card.setCreating(true)
            check(card.creating, "create page opens")
            card.setCreating(false)
            check(card.creating === false && card.askedSlot === -1, "create page closes")
            // Create new action starts empty, whatever the slot runs.
            card.setCreating(true)
            check(card.creating && cardText("labelField") === "" && cardText("commandField") === "", "create form starts empty")
            // After Copy prompt, the slot reopens on the create page with the request, and a pasted answer fills it.
            card.askedSlot = 0
            card.close()
            card.show(0, { label: "Lock", icon: "l", command: "omarchy-system-lock" })
            check(card.tab === "custom" && card.creating, "reopens on the create page")
            check(card.fillFromAnswer("Name: Blur\nIcon:\nWhat it does: Blurs.\nCommand: blur")
                  && cardText("labelField") === "Blur" && cardText("commandField") === "blur", "pasted answer fills the form")
            check(!card.fillFromAnswer("nothing useful") && card.customStatus.indexOf("Name and Command") !== -1
                  && cardText("commandField") === "blur", "a bad paste says why and keeps the form")
            // Try it and Save it ask first, with the action in full; No runs and saves nothing
            // (runtime.py checks that nothing ran and the custom actions are unchanged).
            card.askTry()
            check(card.confirm === "try" && card.details && card.details.command === "blur", "Try it asks first")
            card.closeDetails()
            card.askSave()
            check(card.confirm === "save" && card.details.label === "Blur" && card.opened, "Save it asks first")
            card.closeDetails()
            check(card.confirm === "" && card.details === null && card.opened && card.creating, "No goes back to the form")
            card.askedSlot = -1
            card.setCreating(false)
            card.show(0, { label: "Empty", icon: "e", command: "" })
            check(card.tab === "apps" && card.cursor === 0 && card.awaitingBindings === "", "empty slot opens on Apps")
            // The window sizes the list after it opens: the row is scrolled to then.
            card.show(0, { label: "Calculator", icon: "c", command: "omacalc" })
            card.height = 120
            check(card.revealIndex === card.cursor && card.results[card.cursor].command === "omacalc", "remembers the row to show")
            card.move(1)
            check(card.revealIndex === -1, "moving yourself ends it")
            card.height = 620
            card.close()
            drawer.save()
            check(drawer.saving === null, "saving an unchanged wheel finishes at once")
            // An unsaved edit on slot 1 survives a reload that changed slot 3.
            drawer.assign(0, { label: "Mine", icon: "m", command: "mine" })
            var other = JSON.parse(JSON.stringify(drawer.saved.actions))
            other[2] = { label: "Theirs", icon: "t", command: "theirs" }
            settingsFile.setText(JSON.stringify({ version: 1, actions: other }))
            drawer.reload()
            drawerMerged.start()
        }
    }
    Timer {
        id: drawerMerged; interval: 300
        onTriggered: {
            check(drawer.draft.actions[0].label === "Mine" && drawer.draft.actions[2].label === "Theirs"
                  && drawer.saved.actions[2].label === "Theirs", "reload merges untouched slots only")
            check(drawer.saved.labels === true && drawer.draft.labels === true, "files without labels show names")
            // Dragging slot 1 onto slot 3 swaps them.
            drawer.swap(0, 2)
            check(drawer.draft.actions[2].label === "Mine" && drawer.draft.actions[0].label === "Theirs", "swap moves slots")
            drawer.discard()
            // Fewer slots hide the rest; more brings them back.
            drawer.setSlots(4)
            check(drawer.draftSlots.length === 4 && drawer.draft.actions.length === 8, "4 slots keep the hidden four")
            drawer.setSlots(12)
            check(drawer.draftSlots.length === 12 && drawer.draft.actions[4].label === drawer.saved.actions[4].label,
                  "12 slots bring them back and add presets")
            drawer.setSlots(8)
            drawer.discard()
            // The trigger is written at once, keeping the draft a draft.
            drawer.assign(0, { label: "Draft", icon: "d", command: "draft" })
            drawer.setLabels(false)
            drawer.setTrigger("back")
            drawerTrigger.start()
        }
    }
    Timer {
        id: drawerTrigger; interval: 300
        onTriggered: {
            check(drawer.saved.trigger === "back" && drawer.draft.trigger === "back", "trigger saved")
            check(drawer.saved.actions[0].label !== "Draft" && drawer.saved.labels === true
                  && drawer.draft.labels === false && drawer.dirty, "draft stays unsaved")
            // The On switch is written at once too, keeping trigger and draft.
            drawer.setEnabled(false)
            drawerOff.start()
        }
    }
    Timer {
        id: drawerOff; interval: 300
        onTriggered: {
            check(!drawer.saved.enabled && !drawer.draft.enabled && drawer.saved.trigger === "back", "off saved, trigger kept")
            check(drawer.saved.actions[0].label !== "Draft" && drawer.draft.actions[0].label === "Draft" && drawer.dirty,
                  "turning off keeps the draft a draft")
            drawer.reset()
            check(!drawer.draft.enabled && drawer.draft.trigger === "back", "reset keeps the wheel off and its trigger")
            var v = Actions.validate({ version: 1, actions: Actions.defaults().actions })
            check(v.slots === 8 && v.trigger === "middle" && v.enabled === true, "old files: eight slots, middle-click, on")
            var off = false
            try { Actions.validate({ version: 1, enabled: "no", actions: Actions.defaults().actions }) } catch (e) { off = true }
            check(off, "enabled must be true or false")
            var bad = false
            try { Actions.validate({ version: 1, slots: 5, actions: Actions.defaults().actions }) } catch (e) { bad = true }
            check(bad, "odd slot counts refused")
            bad = false
            try { Actions.validate({ version: 1, labels: "no", actions: Actions.defaults().actions }) } catch (e) { bad = true }
            check(bad && v.labels === true, "labels must be true or false, default on")
            // Hyprland events open at the position they carry, with no cursor query.
            var id = "io.github.erikrjohansson.hotkey-wheel"
            var sx = wheel.targetScreen.x, sy = wheel.targetScreen.y
            wheel.hyprlandEvent("other.plugin hold e-0 " + (sx + 300) + " " + (sy + 300))
            check(!wheel.opened && !wheel.locating, "events for other ids ignored")
            wheel.hyprlandEvent(id + " hold e-1 " + (sx + 300.5) + " " + (sy + 310))
            check(wheel.opened && wheel.holding && !wheel.locating && wheel.originX === 300.5 && wheel.originY === 310,
                  "hold event opens at once where it was pressed")
            wheel.hyprlandEvent(id + " release e-1 " + (sx + 302) + " " + (sy + 311))
            check(!wheel.opened && !wheel.pendingCommand, "release event at the press point runs nothing")
            wheel.open("{}")
            wheel.hyprlandEvent(id + " cancel")
            check(!wheel.opened, "cancel event closes it")
            // Save it writes its own slot at once; other draft edits stay drafts.
            drawer.discard()
            drawer.assign(3, { label: "Draft4", icon: "d", command: "draft4" })
            drawer.saveSlot(1, { label: "Blur", icon: "b", command: "blur", description: " Blurs it. ", custom: true })
            drawerSlotSaved.start()
        }
    }
    Timer {
        id: drawerSlotSaved; interval: 300
        onTriggered: {
            check(drawer.saving === null && drawer.saved.actions[1].description === "Blurs it."
                  && drawer.saved.actions[3].label !== "Draft4" && drawer.draft.actions[3].label === "Draft4"
                  && drawer.draft.actions[1].label === "Blur" && drawer.dirty, "Save it writes only its slot")
            check(drawer.library[0].command === "blur" && drawer.library[0].description === "Blurs it.",
                  "Save it keeps it under custom actions")
            // Renaming keeps the command and follows onto the slot that holds it.
            drawer.rename(drawer.library[0], { label: "Blurry", icon: "", command: "blur", description: "Blurs it more." })
            check(drawer.library[0].label === "Blurry" && drawer.library[0].command === "blur"
                  && drawer.draft.actions[1].label === "Blurry" && drawer.draft.actions[3].label === "Draft4", "rename list and draft")
            drawerRenamed.start()
        }
    }
    Timer {
        id: drawerRenamed; interval: 300
        onTriggered: {
            check(drawer.saving === null && drawer.saved.actions[1].label === "Blurry"
                  && drawer.saved.actions[1].description === "Blurs it more."
                  && drawer.saved.actions[3].label !== "Draft4", "rename saved on the slot, rest stays a draft")
            // Busy or hidden: nothing changes and the reason comes back.
            drawer.saving = drawer.saved
            check(drawer.saveSlot(2, { label: "No", icon: "n", command: "no" }).indexOf("Still saving") === 0
                  && drawer.draft.actions[2].label !== "No", "Save it refused while saving, draft untouched")
            check(drawer.rename(drawer.library[0], { label: "Nope", icon: "n", command: "blur" }).indexOf("Still saving") === 0
                  && drawer.library[0].label === "Blurry", "rename refused while saving, list untouched")
            drawer.saving = null
            check(drawer.saveSlot(9, { label: "No", icon: "n", command: "no" }).indexOf("isn't on the saved wheel") !== -1,
                  "Save it refused for a slot the saved wheel hides")
            var home = Quickshell.env("HOME")
            details.action = { label: "A", icon: "a", command: home + "/scripts/a.sh", description: "Echoes." }
            pipeDetails.action = { label: "P", icon: "p", command: home + "/scripts/pipe.sh", description: "Pipe." }
            latinDetails.action = { label: "L", icon: "l", command: home + "/scripts/latin1.sh", description: "Latin-1." }
            detailsRead.start()
        }
    }
    Timer {
        id: detailsRead; interval: 1000
        onTriggered: {
            check(details.scriptState === "ok" && details.scriptContents === "#!/bin/sh\necho reviewed\n", "script read in full")
            check(pipeDetails.scriptState === "hidden" && pipeDetails.scriptNote.indexOf("plain file") !== -1, "a pipe is not read")
            check(latinDetails.scriptState === "hidden" && latinDetails.scriptNote.indexOf("UTF-8") !== -1,
                  "text that can't be shown faithfully isn't shown")
            // Opened again after the script changed: the new version is shown.
            scriptA.setText("#!/bin/sh\necho swapped\n")
            details.action = { label: "A", icon: "a", command: Quickshell.env("HOME") + "/scripts/a.sh", description: "Echoes." }
            detailsSwapped.start()
        }
    }
    Timer {
        id: detailsSwapped; interval: 1000
        onTriggered: {
            check(details.scriptState === "ok" && details.scriptContents.indexOf("swapped") !== -1, "script read again")
            // A read for the action it showed before is dropped.
            details.action = { label: "B", icon: "b", command: Quickshell.env("HOME") + "/scripts/a.sh --other", description: "Other." }
            details.scriptRead(0, "ok\nstale")
            detailsReplaced.start()
        }
    }
    Timer {
        id: detailsReplaced; interval: 1000
        onTriggered: {
            check(details.scriptState === "ok" && details.scriptContents.indexOf("swapped") !== -1, "a stale read is dropped")
            // Copy prompt hands the prompt to wl-copy on stdin, with the request
            // but not the slot's current command.
            card.show(1, { label: "Secret", icon: "s", command: "echo SLOT-MARKER-3" })
            card.request = "blur CMD-MARKER-7"
            card.copyPrompt()
            promptCopied.start()
        }
    }
    Timer {
        id: promptCopied; interval: 1500
        onTriggered: {
            check(card.customStatus.indexOf("Prompt copied") === 0, "prompt copied: " + card.customStatus)
            // Settings or custom actions that didn't load are never written over.
            drawer.settingsBroken = true
            drawer.setTrigger("middle")
            check(drawer.saving === null && drawer.configError.indexOf("didn't load") !== -1
                  && drawer.saveSlot(0, { label: "X", icon: "x", command: "x" }).indexOf("didn't load") !== -1, "broken settings kept")
            drawer.settingsBroken = false
            drawer.libraryBroken = true
            var kept = JSON.stringify(drawer.library)
            drawer.forget(drawer.library[0].command)
            check(JSON.stringify(drawer.library) === kept, "broken custom actions kept")
            drawer.libraryBroken = false
            console.log("HOTKEY_WHEEL_OK"); Qt.quit()
        }
    }
}
