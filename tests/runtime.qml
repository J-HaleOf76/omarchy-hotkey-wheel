import QtQuick
import Quickshell
import Quickshell.Io
import "PLUGIN_PATH" as Plugin
import "ACTIONS_PATH" as Actions
import "BUS_PATH" as Bus

ShellRoot {
    id: root
    // The real bar drawer, never opened here (that would map its windows).
    Plugin.WheelDrawer { id: drawer }
    // The details window: an agent's script, and a pipe it must not wait on.
    property int savedClicks: 0
    property string savedHash: ""
    Plugin.ActionDetails {
        id: details
        suggested: true
        onSaveIt: function(hash) { savedClicks++; savedHash = hash }
    }
    Plugin.ActionDetails { id: pipeDetails; suggested: true }
    // The picker card on its own (no window): it opens on the slot's tab.
    Plugin.PickerCard { id: card; width: 560; height: 620 }
    Plugin.ActionDetails { id: latinDetails; suggested: true }
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
    // Stands in for the bar drawer: the overlay's propose IPC reaches it via Bus.
    QtObject {
        id: fakeDrawer
        property string screenName: ""
        property var received: null
        function propose(index, action) { received = { index: index, action: action } }
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
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
            check(wheel.propose(0, "X", "", "true", "Does a thing.").indexOf("error: slot") === 0, "slot range checked")
            check(wheel.propose(2, "X", "", "  ", "Does a thing.").indexOf("error: the command is empty") === 0, "empty command refused")
            check(wheel.propose(2, "", "", "true", "Does a thing.").indexOf("error: Slot 2") === 0, "label required")
            Bus.removeDrawer(drawer)
            check(wheel.propose(2, "X", "", "true", "Does a thing.").indexOf("not on the bar") !== -1, "no drawer explained")
            Bus.addDrawer(fakeDrawer)
            check(wheel.propose(2, "Webcam blur", "", "toggle-blur", "Does a thing.").indexOf("ok:") === 0, "proposal accepted")
            check(fakeDrawer.received.index === 1 && fakeDrawer.received.action.icon === Actions.glyphFor("webcam")
                  && fakeDrawer.received.action.command === "toggle-blur"
                  && fakeDrawer.received.action.description === "Does a thing.", "proposal reaches the drawer with a glyph")
            check(wheel.propose(2, "X", "", "true", "  ").indexOf("what it does") !== -1, "description required")
            check(wheel.propose(2, "X", "", "true", "Line one.\nLine two.").indexOf("ok:") === 0, "description may wrap")
            check(wheel.propose(2, "X", "", "true", "Safe \u202eevil").indexOf("bidi") !== -1, "bidi in description refused")
            check(wheel.propose(2, "X", "", "true", new Array(602).join("a")).indexOf("600") !== -1, "long description refused")
            check(Actions.pick({ label: " A ", icon: "a", command: " c ", description: " Does. ", custom: true }).description === "Does."
                  && Actions.pick({ label: "A", icon: "a", command: "c", description: "" }).description === undefined, "pick keeps a description")
            var pin = new Array(65).join("a")
            check(Actions.runCommand({ label: "L", command: "echo hi" }, "/h", "/home/u") === "echo hi"
                  && Actions.runCommand({ label: "L", command: "~/s/a.sh x" }, "/h", "/home/u") === "~/s/a.sh x"
                  && Actions.runCommand({ label: "L", command: "~/s/a.sh x", scriptHash: pin }, "/h", "/home/u")
                     === "'/h' 'checked' '" + pin + "' '/home/u/s/a.sh' 'L' '~/s/a.sh x'", "pinned scripts run checked")
            var badPin = false
            try { Actions.validateAction({ label: "L", icon: "l", command: "c", scriptHash: "nope" }, 0) } catch (e) { badPin = true }
            check(badPin && Actions.pick({ label: "L", icon: "l", command: "c", scriptHash: pin }).scriptHash === pin
                  && Actions.pick({ label: "L", icon: "l", command: "c", scriptHash: "x" }).scriptHash === undefined, "pins validated")
            var sf = "/home/u/.config/omarchy/extensions/hotkey-wheel-scripts/"
            check(Actions.uncheckedFile("bash -- " + sf + "payload", "/home/u") !== ""
                  && Actions.uncheckedFile("/usr/bin/bash " + sf + "payload", "/home/u") !== ""
                  && Actions.uncheckedFile("sh < " + sf + "payload", "/home/u") !== ""
                  && Actions.uncheckedFile(sf + "a.sh; sh " + sf + "stage2", "/home/u").indexOf("stage2") !== -1
                  && Actions.uncheckedFile("bash \"$HOME/.config/omarchy/extensions/hotkey-wheel-scripts/x\"", "/home/u") !== ""
                  && Actions.uncheckedFile(sf + "a.sh --flag", "/home/u") === ""
                  && Actions.uncheckedFile("python3 " + sf + "a.py x", "/home/u") === ""
                  && Actions.uncheckedFile("omarchy-toggle-nightlight", "/home/u") === "", "unchecked script files")
            check(Actions.scriptPath("\"~/s/a.sh\"", "/home/u") === "" && Actions.scriptPath("'~/s/a.sh'", "/home/u") === "",
                  "quoted tilde is not home")
            check(Actions.runCommand({ label: "L", command: "echo $(cat x)", scriptHash: pin }, "/h", "/home/u").indexOf("'checked' '" + pin + "' ''") !== -1,
                  "a pin without a script fails closed")
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
            Bus.removeDrawer(fakeDrawer)
            Bus.addDrawer(drawer)
            check(wheel.propose(2, "X", "", "a\u00adb", "Does a thing.").indexOf("invisible") !== -1, "soft hyphen refused")
            check(Actions.validateProposal({ label: "Love", icon: "\u2764\ufe0f", command: "true", description: "Shows love." }, 0).icon === "\u2764\ufe0f",
                  "emoji icons allowed")
            check(Actions.bindingCommand("killactive", "") === "hyprctl dispatch 'killactive'"
                  && Actions.bindingCommand("exec", "") === "", "argumentless dispatchers")
            check(wheel.propose(2, "X", "", "echo \u202eevil", "Does a thing.").indexOf("bidi") !== -1, "bidi override refused")
            check(wheel.propose(2, "X", "", "a\nb", "Does a thing.").indexOf("invisible") !== -1, "newline refused")
            check(wheel.propose(2, "X", "", new Array(1002).join("a"), "Does a thing.").indexOf("1000") !== -1, "long command refused")
            check(Actions.scriptPath("~/s/run.sh --x", "/home/u") === "/home/u/s/run.sh"
                  && Actions.scriptPath("'/home/u/a b.sh' --x", "/home/u") === "/home/u/a b.sh"
                  && Actions.scriptPath("$HOME/s/a.sh", "/home/u") === "/home/u/s/a.sh"
                  && Actions.scriptPath("~/s/run.sh;rm x", "/home/u") === "/home/u/s/run.sh"
                  && Actions.scriptPath("/home/u/../etc/x", "/home/u") === ""
                  && Actions.scriptPath("/usr/bin/foo", "/home/u") === "", "script path")
            var asked = Actions.agentPrompt(3, { label: "Files", command: "xdg-open ~" }, "blur my webcam", "/s")
            check(asked.indexOf("propose 3 ") !== -1 && asked.indexOf("blur my webcam") !== -1
                  && asked.indexOf("Files → xdg-open ~") !== -1 && asked.indexOf("/s/") !== -1, "agent prompt")
            check(asked.indexOf("Don't run the command") !== -1 && asked.indexOf("Test it") === -1, "agents told not to run it")
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
            check(drawer.propose(9, { label: "X", icon: "x", command: "x" }).indexOf("hidden") !== -1, "hidden slot refused")
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
            check(details.scriptState === "ok" && details.scriptContents === "#!/bin/sh\necho reviewed\n" && details.armed,
                  "script read in full")
            check(pipeDetails.scriptState === "hidden" && !pipeDetails.reviewable, "a pipe is not read and can't be saved")
            check(latinDetails.scriptState === "hidden" && !latinDetails.reviewable
                  && latinDetails.scriptNote.indexOf("UTF-8") !== -1, "text that can't be shown faithfully can't be saved")
            // Changed after it was shown: the click is refused and the new one shown.
            scriptA.setText("#!/bin/sh\necho swapped\n")
            detailsSwap.start()
        }
    }
    Timer {
        id: detailsSwap; interval: 300
        onTriggered: {
            details.act("save")
            detailsSwapped.start()
        }
    }
    Timer {
        id: detailsSwapped; interval: 1000
        onTriggered: {
            check(root.savedClicks === 0 && details.notice.indexOf("changed") !== -1
                  && details.scriptContents.indexOf("swapped") !== -1 && details.armed, "changed script refused and shown")
            details.act("save")
            detailsSaved.start()
        }
    }
    Timer {
        id: detailsSaved; interval: 500
        onTriggered: {
            check(root.savedClicks === 1 && Actions.validHash(root.savedHash), "unchanged script saves, pinned")
            // A newer suggestion arriving while a click's read runs takes the click with it.
            // Its read finishing before the new one starts is the worst order.
            var shown = details.scriptContents
            details.act("save")
            details.action = { label: "B", icon: "b", command: Quickshell.env("HOME") + "/scripts/a.sh --other", description: "Other." }
            details.scriptRead(0, "ok " + root.savedHash + "\n" + shown)
            detailsReplaced.start()
        }
    }
    Timer {
        id: detailsReplaced; interval: 1000
        onTriggered: {
            check(root.savedClicks === 1 && details.pendingAct === "" && details.scriptState === "ok",
                  "a click never lands on the suggestion that replaced it")
            console.log("HOTKEY_WHEEL_OK"); Qt.quit()
        }
    }
}
