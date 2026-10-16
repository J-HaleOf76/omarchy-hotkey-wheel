import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Actions.js" as Actions
import "Bus.js" as Bus

// Bar drawer: the wheel with its current slots. Clicking a slot opens the
// action picker; dragging one onto another swaps them. Slot changes and the
// slot count collect in a draft until Save writes the settings file. The
// trigger and the on/off switch are system setup, so they apply at once, like
// Omarchy's panel toggles.
Panel {
    id: root
    moduleName: "io.github.erikrjohansson.hotkey-wheel"
    manageIpc: false
    property var anchorItem: null
    property var hostWidget: null
    // What the settings file holds, and the edited copy. Both are settings
    // objects (see Actions.validate); the draft's trigger and on/off mirror the saved ones.
    property var saved: Actions.defaults()
    property var draft: Actions.defaults()
    readonly property var draftSlots: Actions.visible(draft)
    property int cursor: -1
    // Saved custom commands, and the draft's slots picked from the Custom tab
    // (index → action), which join the list once saved.
    property var library: []
    property var customPicks: ({})
    // The settings being written, so edits made during a save stay unsaved,
    // and whether Hyprland must reload once they are (a new trigger).
    property var saving: null
    property bool applyAfterSave: false
    property string configError: ""
    // A settings or custom-actions file that exists but didn't load is never
    // written over, so a typo from a hand edit can't cost the user their slots.
    property bool settingsBroken: false
    property bool libraryBroken: false
    readonly property string brokenMessage: "Your wheel settings didn't load, so they aren't written over. Fix or remove "
                                            + configPath + ", then open the drawer again."
    // Mouse setup, from the hotkey-wheel helper: "setup", "not-setup", or ""
    // while unknown. `conflicts` maps a trigger to other bindings already on it.
    property string setupState: ""
    property var conflicts: ({})
    property bool helperBusy: false
    property string setupError: ""
    readonly property bool dirty: draft.slots !== saved.slots || draft.labels !== saved.labels
                                  || !Actions.same(draft.actions, saved.actions)
    readonly property bool pickerOpen: picker.opened
    readonly property string home: Quickshell.env("HOME")
    readonly property string helperPath: Qt.resolvedUrl("hotkey-wheel").toString().replace(/^file:\/\//, "")
    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config")
                                         + "/omarchy/extensions/hotkey-wheel.json"
    readonly property string libraryPath: configPath.replace(/\.json$/, "-custom.json")

    Component.onCompleted: Bus.addDrawer(root)
    Component.onDestruction: Bus.removeDrawer(root)

    // Re-read on every open: the watcher can miss changes after an atomic
    // save replaces the file.
    function reload() { settingsFile.reload(); libraryFile.reload() }

    function open() {
        reload()
        refreshState()
        root.controller.show()
    }
    onOpenedChanged: if (!opened) { picker.close(); cursor = -1 }

    function edit(index) {
        if (index < 0 || index >= draft.slots) return
        cursor = index
        picker.show(index, draft.actions[index])
    }

    function assign(index, action) {
        var copy = JSON.parse(JSON.stringify(draft))
        // Stored the way Save writes it (trimmed), so a saved draft compares clean.
        copy.actions[index] = Actions.pick(action)
        draft = copy
        configError = ""
        var picks = Object.assign({}, customPicks)
        if (action.custom) picks[index] = copy.actions[index]
        else delete picks[index]
        customPicks = picks
    }

    function swap(from, to) {
        if (from === to || from < 0 || to < 0 || from >= draft.slots || to >= draft.slots) return
        var copy = JSON.parse(JSON.stringify(draft))
        var moved = copy.actions[from]
        copy.actions[from] = copy.actions[to]
        copy.actions[to] = moved
        draft = copy
        var picks = Object.assign({}, customPicks)
        delete picks[from]
        delete picks[to]
        if (customPicks[from]) picks[to] = customPicks[from]
        if (customPicks[to]) picks[from] = customPicks[to]
        customPicks = picks
        cursor = to
    }

    function setLabels(on) {
        var copy = JSON.parse(JSON.stringify(draft))
        copy.labels = on
        draft = copy
    }

    function setSlots(count) {
        draft = Actions.resize(draft, count)
        if (cursor >= count) cursor = -1
    }

    // Save it: the slot is written at once; the rest of the draft stays a draft.
    // Returns "" or why it was not saved (nothing changes then).
    function saveSlot(index, action) {
        if (saving) return "Still saving the wheel; try again in a moment."
        if (settingsBroken) return brokenMessage
        if (index >= saved.slots)
            return "Slot " + (index + 1) + " isn't on the saved wheel yet. Save the new slot count in the drawer first."
        var next
        try {
            next = JSON.parse(JSON.stringify(saved))
            next.actions[index] = Actions.pick(action)
            next = Actions.validate(next)
        } catch (e) { return e.message }
        assign(index, action)
        write(next, false)
        return ""
    }

    function reset() {
        if (saving) return
        var fresh = Actions.defaults()
        fresh.trigger = saved.trigger
        fresh.enabled = saved.enabled
        draft = fresh
        customPicks = {}
    }

    function moveCursor(step) {
        var count = draft.slots
        cursor = cursor < 0 ? (step > 0 ? 0 : count - 1) : (cursor + step + count) % count
    }

    function discard() {
        if (saving) return
        draft = JSON.parse(JSON.stringify(saved))
        configError = ""
        customPicks = {}
    }

    function save() {
        if (saving) return
        var next
        try { next = Actions.validate({ version: 1, enabled: saved.enabled, slots: draft.slots, trigger: saved.trigger,
                                         labels: draft.labels, actions: draft.actions }) }
        catch (e) { configError = e.message; return }
        write(next, false)
    }

    // The trigger applies at once: it is written with the saved slots (the
    // draft stays a draft) and Hyprland reloads to bind it.
    function setTrigger(name) {
        if (saving || name === saved.trigger) return
        var next = JSON.parse(JSON.stringify(saved))
        next.trigger = name
        write(next, setupState === "setup")
    }

    // Off leaves the trigger to the apps; on binds it again. Applies at once.
    function setEnabled(on) {
        if (saving || on === saved.enabled) return
        var next = JSON.parse(JSON.stringify(saved))
        next.enabled = on
        write(next, setupState === "setup")
    }

    function write(next, applyTrigger) {
        if (settingsBroken) { configError = brokenMessage; return }
        // FileView skips a write whose text is unchanged and then never
        // reports saved, so an unchanged wheel is finished here.
        if (Actions.same(next, saved)) { finishSave(next); return }
        saving = next
        applyAfterSave = applyTrigger
        makeDirectory.running = true
    }

    function finishSave(written) {
        saving = null
        saved = written
        configError = ""
        // The draft takes the written trigger and, when it matches what was
        // written, its exact form.
        var next = JSON.parse(JSON.stringify(draft))
        next.trigger = written.trigger
        next.enabled = written.enabled
        draft = next.slots === written.slots && next.labels === written.labels && Actions.same(next.actions, written.actions)
            ? JSON.parse(JSON.stringify(written)) : next
        if (applyAfterSave) runHelper("apply")
        applyAfterSave = false
        rememberSaved(written)
        // Drawers on other monitors save from what they last read.
        Bus.drawers.forEach(function(d) { if (d !== root) d.reload() })
    }

    // Custom picks that made it into the saved wheel join the custom actions.
    function rememberSaved(written) {
        var added = [], left = {}
        for (var key in customPicks) {
            if (Actions.same(customPicks[key], written.actions[key])) added.push(customPicks[key])
            else left[key] = customPicks[key]
        }
        customPicks = left
        if (added.length === 0) return
        if (libraryBroken) { configError = libraryBrokenMessage(); return }
        library = Actions.remember(library, added)
        writeLibrary()
    }

    // A renamed custom action (same command) is renamed in the list and on
    // every slot that holds it exactly as it was: saved slots at once, like
    // Save it, and the draft's too. Returns "" or why nothing was renamed.
    function rename(before, after) {
        if (saving) return "Still saving the wheel; try again in a moment."
        if (settingsBroken || libraryBroken) return libraryBroken ? libraryBrokenMessage() : brokenMessage
        var was = Actions.pick(before), now = Actions.pick(after)
        if (was.command !== now.command) return "Renaming keeps the command."
        var swapIn = function(list) {
            var hit = false
            for (var i = 0; i < list.length; ++i)
                if (Actions.same(list[i], was)) { list[i] = JSON.parse(JSON.stringify(now)); hit = true }
            return hit
        }
        var next = JSON.parse(JSON.stringify(saved))
        var slotsHit = swapIn(next.actions)
        try { if (slotsHit) next = Actions.validate(next) } catch (e) { return e.message }
        library = library.map(function(a) { return a.command === now.command ? now : a })
        writeLibrary()
        var copy = JSON.parse(JSON.stringify(draft))
        if (swapIn(copy.actions)) draft = copy
        var picks = Object.assign({}, customPicks)
        for (var key in picks) if (Actions.same(picks[key], was)) picks[key] = JSON.parse(JSON.stringify(now))
        customPicks = picks
        if (slotsHit) write(next, false)
        return ""
    }

    function forget(command) {
        if (libraryBroken) { configError = libraryBrokenMessage(); return }
        library = Actions.forget(library, command)
        writeLibrary()
    }

    function libraryBrokenMessage() {
        return "Your custom actions didn't load, so they aren't written over. Fix or remove " + libraryPath + "."
    }

    function writeLibrary() {
        if (libraryBroken) { configError = libraryBrokenMessage(); return }
        libraryFile.setText(JSON.stringify({ version: 1, commands: library }, null, 2) + "\n")
    }

    function refreshState() {
        if (!stateCheck.running) stateCheck.running = true
    }

    function runHelper(command) {
        if (helperBusy) return
        helperBusy = true
        setupError = ""
        helperRun.command = [helperPath, command]
        helperRun.running = true
    }

    // Hand keyboard focus back once the picker's exclusive layer is gone.
    function refocus() {
        if (!root.opened) return
        panel.focusPrimed = false
        panel.beginFocusPrime()
        keyCatcher.forceActiveFocus()
    }

    FileView {
        id: settingsFile
        path: root.configPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var incoming = Actions.validate(JSON.parse(text()))
                var merged = Actions.merge(root.draft, root.saved, incoming)
                root.saved = incoming
                root.draft = Actions.resize(merged, merged.slots)
                root.settingsBroken = false
                root.configError = ""
            } catch (e) {
                root.settingsBroken = true
                root.configError = "Settings not loaded: " + e.message
            }
        }
        onLoadFailed: function(error) {
            root.settingsBroken = error !== FileViewError.FileNotFound
            if (root.settingsBroken) root.configError = "Could not read wheel settings."
        }
        onSaved: {
            root.finishSave(root.saving)
            Quickshell.execDetached(["omarchy-shell", "io.github.erikrjohansson.hotkey-wheel", "reload"])
        }
        onSaveFailed: {
            root.saving = null
            root.applyAfterSave = false
            root.configError = "Could not save wheel settings."
            // Back to what the file holds, so trying again really writes.
            reload()
        }
    }

    FileView {
        id: libraryFile
        path: root.libraryPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.library = Actions.validateLibrary(JSON.parse(text()))
                root.libraryBroken = false
            } catch (e) {
                root.library = []
                root.libraryBroken = true
            }
        }
        onLoadFailed: function(error) { root.libraryBroken = error !== FileViewError.FileNotFound }
        onSaveFailed: {
            root.configError = "Could not save your custom actions."
            // The list goes back to what the file holds.
            reload()
        }
    }

    Process {
        id: makeDirectory
        command: ["mkdir", "-p", root.configPath.slice(0, root.configPath.lastIndexOf("/"))]
        onExited: function(code) {
            if (code !== 0) { root.saving = null; root.configError = "Could not create settings directory."; return }
            settingsFile.setText(JSON.stringify(root.saving, null, 2) + "\n")
        }
    }

    Process {
        id: stateCheck
        command: [root.helperPath, "state"]
        stdout: StdioCollector { id: stateOutput; waitForEnd: true }
        onExited: function(code) {
            if (code !== 0) return
            var lines = stateOutput.text.split("\n")
            var found = {}
            for (var i = 1; i < lines.length; ++i) {
                var f = lines[i].split("\t")
                if (f[0] !== "conflict" || f.length < 3) continue
                found[f[1]] = (found[f[1]] || []).concat([f.slice(2).join("\t")])
            }
            root.setupState = lines[0] === "setup" ? "setup" : "not-setup"
            root.conflicts = found
        }
    }

    Process {
        id: helperRun
        stderr: StdioCollector { id: helperErrors; waitForEnd: true }
        onExited: function(code) {
            root.helperBusy = false
            if (code !== 0) root.setupError = helperErrors.text.trim() || "Setup failed."
            root.refreshState()
        }
    }

    ActionPicker {
        id: picker
        screen: panel.screen
        library: root.library
        drawer: root
        onPicked: function(index, action) { root.assign(index, action) }
        onForget: function(command) { root.forget(command) }
        onClosed: Qt.callLater(root.refocus)
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(440))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: picker.opened
            onCloseRequested: root.close()
            onMoveRequested: function(dx, dy) { root.moveCursor(dx || dy) }
            onTabRequested: function(direction) { root.moveCursor(direction) }
            onActivateRequested: root.edit(root.cursor)
            onTextKey: function(text) {
                // Ctrl+S arrives as its control character.
                if (text === "\u0013") { if (root.dirty) root.save(); return }
                // 1–9 pick the first nine slots and 0 the tenth.
                var slot = text === "0" ? 10 : Number(text)
                if (slot >= 1 && slot <= 10) root.edit(slot - 1)
            }

            DrawerContent {
                id: content
                width: parent.width
                drawer: root
            }
        }
    }
}
