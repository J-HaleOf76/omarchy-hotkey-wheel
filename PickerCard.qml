import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Actions.js" as Actions

// The picker card: everything a slot can run, in tabs: desktop apps, curated
// Omarchy actions, every Omarchy keybinding, and custom actions (with a page to
// create one, with a prompt to ask any agent for help). ActionPicker hosts it
// in a modal layer, with the details window for a custom action.
BorderSurface {
    id: root
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.panelPadding
    property bool opened: false
    property int slot: 0
    property var current: ({ label: "", icon: "", command: "" })
    property string tab: "apps"
    property string query: ""
    property string hidesText: ""
    property int cursor: 0
    // Desktop entries load asynchronously and change as apps are installed.
    readonly property var apps: Actions.appItems(DesktopEntries.applications.values || [], hidesText)
    property var presets: Actions.presetItems()
    property var bindings: []
    property string bindingsError: ""
    // A slot command found in no other tab, looked for in Keybindings once they load.
    property string awaitingBindings: ""
    // The row the picker opened on. The window gets its size a moment after
    // it opens, so the list scrolls to it again once it has one; moving
    // through the list yourself ends that.
    property int revealIndex: -1
    readonly property var tabs: [
        { value: "apps", label: "Apps", icon: "󰀻" },
        { value: "omarchy", label: "Omarchy", icon: "󰣇" },
        { value: "bindings", label: "Keybindings", icon: "󰌌" },
        { value: "custom", label: "Custom", icon: "󰆍" }
    ]
    // The Custom tab's list starts with a row that opens the create page.
    readonly property var createItem: ({ label: "Create new action", icon: "󰐕", command: null, create: true, keywords: "",
        detail: library.length ? "Your own command, with an agent's help if you like" : "Saved ones show up here" })
    readonly property var results: tab === "custom" ? [createItem].concat(Actions.filter(itemsFor(tab), query))
                                                    : Actions.filter(itemsFor(tab), query)

    signal picked(int index, var action)
    signal closed()
    signal forget(string command)
    // The bar drawer (WheelDrawer): saveSlot and rename return "" or an error.
    property var drawer: null
    // Custom actions (see Actions.validateLibrary).
    property var library: []
    readonly property var libraryItems: library.map(function(a) {
        return { label: a.label, icon: a.icon, command: a.command, description: a.description || "",
                 detail: a.description || root.tidy(a.command), keywords: a.command, saved: true }
    })
    // The Custom tab's create page is showing.
    property bool creating: false
    // The custom action in the details window (ActionPicker shows it).
    property var details: null
    property string detailsStatus: ""
    // "try" or "save" while the details window asks to confirm a new action
    // from the create page; "" for a saved custom action.
    property string confirm: ""

    // Custom tab feedback.
    property string customStatus: ""
    // The slot a prompt was copied for: reopening it goes back to the create
    // page, with the request, to paste the agent's answer.
    property int askedSlot: -1
    // What the user asked an agent for: the only thing of theirs the prompt carries.
    property alias request: requestField.text
    readonly property string home: Quickshell.env("HOME")
    // Always in the home folder, where the details window can show scripts.
    readonly property string scriptsDir: home + Actions.scriptsFolder

    // A command as a list row shows it: the home folder as ~.
    function tidy(command) { return home && command.indexOf(home + "/") !== -1 ? command.split(home + "/").join("~/") : command }

    function itemsFor(name) {
        return name === "apps" ? apps : name === "omarchy" ? presets : name === "bindings" ? bindings : libraryItems
    }

    function tabLabel(option) {
        if (!query) return option.label
        return option.label + " · " + Actions.filter(itemsFor(option.value), query).length
    }

    function show(index, action) {
        slot = index
        current = action
        creating = false
        details = null
        detailsStatus = ""
        query = ""
        cursor = 0
        if (tab === "bindings") loadBindings()
        customStatus = ""
        // Create new action makes a new action, so it starts empty.
        fill({ label: "", icon: "", description: "", command: "" })
        opened = true
        customScroll.contentY = 0
        if (index === askedSlot) {
            setTab("custom")
            setCreating(true)
            customStatus = "Copy the code block with Name, Icon, What it does and Command from the agent's answer, then Paste answer."
            Qt.callLater(showAsk)
            return
        }
        requestField.text = ""
        // Otherwise Apps, from the top (Keybindings may still have it).
        if (!revealCurrent()) {
            setTab("apps")
            if (action.command) {
                awaitingBindings = action.command
                loadBindings()
            }
        }
        Qt.callLater(focusTab)
    }

    // The tab holding the slot's current action, first match in this order.
    function tabOf(command) {
        if (!command) return ""
        var order = ["omarchy", "apps", "custom", "bindings"]
        for (var i = 0; i < order.length; ++i)
            if (itemsFor(order[i]).some(function(item) { return item.command === command })) return order[i]
        return ""
    }

    // Opens on the slot's current action, selected and in view. False when
    // no tab has it (yet).
    function revealCurrent() {
        var name = tabOf(current.command)
        if (!name) return false
        setTab(name)
        var index = results.findIndex(function(item) { return item.command === current.command })
        if (index < 0) return true
        cursor = index
        revealIndex = index
        Qt.callLater(scrollToReveal)
        return true
    }

    function scrollToReveal() {
        if (revealIndex >= 0 && revealIndex < list.count) list.positionViewAtIndex(revealIndex, ListView.Center)
    }

    function close() {
        if (!opened) return
        opened = false
        details = null
        closed()
    }

    function setCreating(on) {
        creating = on
        customStatus = ""
        if (on) customScroll.contentY = 0
        focusTab()
    }

    function showDetails(item) {
        confirm = ""
        details = Actions.pick(item)
        detailsStatus = ""
    }

    function closeDetails() {
        details = null
        confirm = ""
        detailsStatus = ""
        focusTab()
    }

    // The create page's action, as Save it or Try it would take it.
    function formAction() {
        var label = labelField.text.trim()
        var command = commandField.text.trim()
        return { label: label || "New action", icon: iconField.text.trim() || Actions.glyphFor(label, command),
                 description: descriptionField.text.trim(), command: command }
    }

    // Try it and Save it first show the action in full (command, warnings,
    // script) and ask; only Yes, a click, goes on.
    function askTry() {
        var action = formAction()
        if (!action.command) { customStatus = run(""); return }
        confirm = "try"
        details = Actions.pick(action)
        detailsStatus = ""
    }

    function askSave() {
        if (!labelField.text.trim()) { labelField.forceActiveFocus(); return }
        var action = formAction()
        // An empty command only clears the slot; there is nothing to read.
        if (!action.command) { keep(action); return }
        confirm = "save"
        details = Actions.pick(action)
        detailsStatus = ""
    }

    function confirmed() {
        var kind = confirm, action = details
        closeDetails()
        if (kind === "try") customStatus = run(action.command)
        else if (kind === "save") keep(action)
    }

    // Reading binds re-runs hyprland.lua in Omarchy's sandbox on a cache miss
    // (as Super+K does), so only when the Keybindings tab is actually opened.
    function loadBindings() {
        if (!bindingList.running) bindingList.running = true
    }

    function setTab(name) {
        awaitingBindings = ""
        revealIndex = -1
        tab = name
        creating = false
        if (name === "bindings") loadBindings()
        cursor = 0
        list.positionViewAtBeginning()
        focusTab()
    }

    function cycleTab(step) {
        var i = tabs.findIndex(function(t) { return t.value === tab })
        setTab(tabs[(i + step + tabs.length) % tabs.length].value)
    }

    // The details window keeps focus while it is open.
    function focusTab() {
        if (details) return
        if (tab === "custom" && creating) labelField.forceActiveFocus()
        else searchField.forceActiveFocus()
    }

    function move(step) {
        revealIndex = -1
        if (results.length === 0) return
        cursor = Math.max(0, Math.min(results.length - 1, cursor + step))
        list.positionViewAtIndex(cursor, ListView.Contain)
    }

    // Custom-tab rows open the create page or the details window; any other
    // row goes on the slot.
    function choose(item) {
        if (!item) return
        if (item.create) { setCreating(true); return }
        if (item.saved) { showDetails(item); return }
        var action = Actions.pick(item)
        action.custom = item.custom === true
        picked(slot, action)
        close()
    }

    // Save it: on the slot and saved at once, and kept under Custom actions.
    // Stays open, with the reason, when the drawer can't save it.
    function keep(action) {
        var chosen = Actions.pick(action)
        chosen.custom = true
        var refused = drawer ? drawer.saveSlot(slot, chosen) : "The wheel's drawer isn't available."
        if (refused) { customStatus = refused; return }
        if (slot === askedSlot) askedSlot = -1
        close()
    }

    function useDetails() {
        var action = Actions.pick(details)
        action.custom = true
        picked(slot, action)
        close()
    }

    // The drawer renames it in the list and on its slots, or says why not.
    function renameDetails(action) {
        var after
        try { after = Actions.validateAction(action, slot) }
        catch (e) { detailsStatus = e.message; return }
        var refused = drawer ? drawer.rename(details, after) : "The wheel's drawer isn't available."
        if (refused) { detailsStatus = refused; return }
        details = after
        detailsStatus = "Renamed."
    }

    function removeDetails() {
        forget(details.command)
        closeDetails()
    }

    // Returns what to tell the user.
    function run(command) {
        if (!command) return "There is no command to try."
        Quickshell.execDetached(["hyprctl", "eval", "hl.exec_cmd(" + Actions.luaString(command) + ")"])
        return "Ran it. Anything it opened is behind this window."
    }

    function prompt() {
        return Actions.agentPrompt(requestField.text, scriptsDir)
    }

    function fill(action) {
        labelField.text = action.label
        iconField.text = action.icon
        descriptionField.text = action.description
        commandField.text = action.command
    }

    // Scrolls to Ask an agent, for pasting the answer.
    function showAsk() { customScroll.contentY = Math.max(0, Math.min(askHeader.y, custom.implicitHeight - customScroll.height)) }

    // The agent's answer, copied whole: it fills the form, and nothing runs.
    function pasteAnswer() {
        if (!paster.running) paster.running = true
    }

    function fillFromAnswer(text) {
        var action
        try { action = Actions.parseAnswer(text) }
        catch (e) { customStatus = e.message; return false }
        fill(action)
        customStatus = "Filled in from the agent's answer. Read it, then Try it or Save it."
        customScroll.contentY = 0
        return true
    }

    // The prompt can hold private text, so it goes to wl-copy on stdin, never
    // on a command line, where other users can read it in the process list.
    function copyPrompt() {
        if (copier.running) return
        copier.text = prompt()
        copier.stdinEnabled = true
        copier.running = true
    }

    onQueryChanged: { revealIndex = -1; cursor = 0; list.positionViewAtBeginning() }

    FileView {
        id: hides
        path: Quickshell.env("OMARCHY_PATH") + "/default/omarchy/launcher.hides"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.hidesText = text()
    }

    Process {
        id: copier
        property string text: ""
        command: ["bash", "-c", "exec wl-copy --type text/plain >/dev/null 2>&1"]
        // Closing stdin is the end of the prompt.
        onStarted: { write(text); stdinEnabled = false }
        onExited: function(code, status) {
            var copied = code === 0 && status === 0
            if (copied) root.askedSlot = root.slot
            root.customStatus = copied
                ? "Prompt copied. Paste it into any agent. Its answer ends with a code block of four lines (Name to Command): copy that, open this slot again and Paste answer."
                : "Couldn't copy the prompt."
        }
    }

    // The clipboard comes back on stdout. Over 64 KB is refused rather than
    // cut, so a command can't lose its end at the cut.
    Process {
        id: paster
        command: ["bash", "-c", 'export LC_ALL=C
text=$(wl-paste --no-newline --type text 2>/dev/null | head -c 65537; printf x)
text=${text%x}
(( ${#text} <= 65536 )) || exit 3
printf "%s" "$text"']
        stdout: StdioCollector { id: pasted; waitForEnd: true }
        onExited: function(code) {
            if (code === 3) root.customStatus = "The clipboard holds more than 64 KB. Copy just the agent's code block (Name to Command)."
            else if (code === 0 && pasted.text.trim()) root.fillFromAnswer(pasted.text)
            else root.customStatus = "The clipboard has no text. Copy the agent's code block (Name to Command) first."
        }
    }

    Process {
        id: bindingList
        command: [Qt.resolvedUrl("hotkey-wheel").toString().replace(/^file:\/\//, ""), "records"]
        stdout: StdioCollector { id: bindingOutput; waitForEnd: true }
        onExited: function(code) {
            root.bindings = Actions.bindingItems(bindingOutput.text)
            root.bindingsError = code === 0 && root.bindings.length > 0 ? "" : "Could not read Omarchy's keybindings."
            // Still open on the same slot, and no tab picked meanwhile.
            if (root.opened && !root.details && root.awaitingBindings && root.awaitingBindings === root.current.command)
                root.revealCurrent()
            root.awaitingBindings = ""
        }
    }


    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
        id: body
        anchors {
            fill: parent
            topMargin: root.contentTopInset; bottomMargin: root.contentBottomInset
            leftMargin: root.contentLeftInset; rightMargin: root.contentRightInset
        }
        // Keys every tab shares; the search field handles list keys.
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (root.creating) root.setCreating(false)
                else root.close()
                event.accepted = true
            }
            else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                     && (event.modifiers & Qt.ControlModifier)) {
                root.cycleTab(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
                event.accepted = true
            }
        }

        Column {
            id: header
            width: parent.width
            spacing: Style.spacing.md

            Row {
                spacing: Style.spacing.md
                Text {
                    text: root.current.icon
                    textFormat: Text.PlainText
                    color: Color.menu.text
                    font { family: Style.font.family; pixelSize: Style.font.title }
                }
                Text {
                    text: "Slot " + (root.slot + 1) + " · " + root.current.label
                    textFormat: Text.PlainText
                    color: Color.menu.text
                    font { family: Style.font.menuFamily; pixelSize: Style.font.title }
                }
            }

            ButtonGroup {
                options: root.tabs.map(function(t) { return { value: t.value, label: root.tabLabel(t), icon: t.icon } })
                value: root.tab
                focusable: false
                foreground: Color.menu.text
                fontFamily: Style.font.menuFamily
                onChanged: function(value) { root.setTab(value) }
            }

            TextField {
                id: searchField
                width: parent.width
                visible: !(root.tab === "custom" && root.creating)
                foreground: Color.menu.text
                placeholderText: root.tab === "apps" ? "Search apps…"
                    : root.tab === "omarchy" ? "Search Omarchy actions…"
                    : root.tab === "bindings" ? "Search keybindings…" : "Search custom actions…"
                text: root.query
                onTextEdited: root.query = text
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    var page = Math.max(1, Math.floor(list.height / list.rowHeight))
                    if (event.key === Qt.Key_Escape && root.query) root.query = ""
                    else if (event.key === Qt.Key_Down) root.move(1)
                    else if (event.key === Qt.Key_Up) root.move(-1)
                    else if (event.key === Qt.Key_PageDown) root.move(page)
                    else if (event.key === Qt.Key_PageUp) root.move(-page)
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.choose(root.results[root.cursor])
                    else if (event.key === Qt.Key_Tab) root.cycleTab(1)
                    else if (event.key === Qt.Key_Backtab) root.cycleTab(-1)
                    else return
                    event.accepted = true
                }
            }
        }

        ListView {
            id: list
            readonly property real rowHeight: Style.space(40)
            anchors { top: header.bottom; topMargin: Style.spacing.md; bottom: parent.bottom }
            width: parent.width
            visible: !(root.tab === "custom" && root.creating)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.results
            onHeightChanged: root.scrollToReveal()
            onMovementStarted: root.revealIndex = -1

            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool hot: index === root.cursor
                readonly property color ink: hot ? Color.menu.selectedText : Color.menu.text
                width: list.width
                height: list.rowHeight
                radius: Style.cornerRadius
                color: hot ? Color.menu.selectedBackground : "transparent"

                Text {
                    id: glyph
                    anchors { left: parent.left; leftMargin: Style.spacing.md; verticalCenter: parent.verticalCenter }
                    width: Style.space(28)
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData.icon
                    textFormat: Text.PlainText
                    color: parent.ink
                    font { family: Style.font.family; pixelSize: Style.space(20) }
                }
                Text {
                    id: name
                    anchors { left: glyph.right; leftMargin: Style.spacing.md; verticalCenter: parent.verticalCenter }
                    width: Math.min(implicitWidth, parent.width * 0.55)
                    text: modelData.label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: parent.ink
                    font { family: Style.font.menuFamily; pixelSize: Style.font.body }
                }
                Text {
                    anchors {
                        left: name.right; leftMargin: Style.spacing.lg
                        right: mark.left; rightMargin: Style.spacing.md
                        verticalCenter: parent.verticalCenter
                    }
                    horizontalAlignment: root.tab === "bindings" ? Text.AlignRight : Text.AlignLeft
                    text: modelData.detail
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: parent.ink
                    opacity: 0.55
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }
                Text {
                    id: mark
                    anchors { right: parent.right; rightMargin: Style.spacing.md; verticalCenter: parent.verticalCenter }
                    text: modelData.command === root.current.command ? "󰄬" : ""
                    color: Color.accent
                    font { family: Style.font.family; pixelSize: Style.font.body }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: root.cursor = index
                    onClicked: root.choose(modelData)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.tab === "bindings" && root.bindingsError ? root.bindingsError
                    : root.tab === "bindings" && bindingList.running ? "Reading keybindings…"
                    : root.query ? "No matches for “" + root.query + "”" : "Nothing here yet."
                textFormat: Text.PlainText
                color: Color.menu.text
                opacity: 0.6
                font { family: Style.font.menuFamily; pixelSize: Style.font.body }
            }
        }

        // Create new action: your own command, with a prompt for any agent. Scrolls on short screens.
        Flickable {
            id: customScroll
            anchors { top: header.bottom; topMargin: Style.spacing.md; bottom: parent.bottom }
            width: parent.width
            visible: root.tab === "custom" && root.creating
            contentHeight: custom.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: custom
                width: parent.width
                spacing: Style.spacing.md

                Button {
                    text: "Custom actions"
                    iconText: "󰁍"
                    foreground: Color.menu.text
                    // Leaving on purpose, so the slot opens as usual again.
                    onClicked: { root.askedSlot = -1; root.setCreating(false) }
                }
                Text {
                    text: "󰐕  Create new action"
                    color: Color.menu.text
                    font { family: Style.font.menuFamily; pixelSize: Style.font.body; bold: true }
                }
                Text {
                    text: "Name and icon"
                    color: Color.menu.text
                    opacity: 0.7
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }
                Row {
                    width: parent.width
                    spacing: Style.spacing.md
                    TextField {
                        id: labelField
                        width: parent.width - iconField.width - parent.spacing
                        foreground: Color.menu.text
                        placeholderText: "Name"
                        maximumLength: 64
                        onAccepted: root.askSave()
                    }
                    TextField {
                        id: iconField
                        width: Style.space(124)
                        foreground: Color.menu.text
                        placeholderText: "Icon (auto)"
                        maximumLength: 16
                        onAccepted: root.askSave()
                    }
                }
                Text {
                    text: "What it does when you pick it (optional)"
                    color: Color.menu.text
                    opacity: 0.7
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }
                TextField {
                    id: descriptionField
                    width: parent.width
                    foreground: Color.menu.text
                    placeholderText: "e.g. Turns the webcam's background blur on or off"
                    maximumLength: Actions.descriptionLimit
                    onAccepted: root.askSave()
                }
                Text {
                    text: "Command"
                    color: Color.menu.text
                    opacity: 0.7
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }
                TextField {
                    id: commandField
                    width: parent.width
                    foreground: Color.menu.text
                    placeholderText: "Command (empty disables the slot)"
                    maximumLength: 4096
                    onAccepted: root.askSave()
                }
                // The details window's hints, before anything runs (Actions.warnings).
                Repeater {
                    model: root.creating ? Actions.warnings(commandField.text, "", root.home) : []
                    Text {
                        required property string modelData
                        width: commandField.width
                        text: "󰀦  " + modelData
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Color.urgent
                        font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                    }
                }
                Row {
                    spacing: Style.spacing.md
                    Button {
                        text: "Save it"
                        iconText: "󰆓"
                        bordered: true
                        foreground: Color.menu.text
                        onClicked: root.askSave()
                    }
                    Button {
                        text: "Try it"
                        iconText: "󰐊"
                        foreground: Color.menu.text
                        onClicked: root.askTry()
                    }
                    Button {
                        text: "Clear slot"
                        iconText: "󰅖"
                        foreground: Color.menu.text
                        onClicked: root.choose({ label: "Empty", icon: "󰐕", command: "" })
                    }
                }
                Text {
                    width: parent.width
                    text: "Try it and Save it first show you the command and its script to read. Save it puts it on slot " + (root.slot + 1) + " right away and keeps it under Custom actions."
                    wrapMode: Text.Wrap
                    color: Color.menu.text
                    opacity: 0.55
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }

                Item { width: 1; height: Style.spacing.md }
                Rectangle { width: parent.width; height: 1; color: Color.menu.text; opacity: 0.15 }

                Text {
                    id: askHeader
                    text: "󰚩  Ask an agent"
                    color: Color.menu.text
                    font { family: Style.font.menuFamily; pixelSize: Style.font.body; bold: true }
                }
                Text {
                    width: parent.width
                    text: "Describe what you want and copy the prompt into Claude Code, Codex or any other agent. The agent's answer ends with a code block of four lines, Name to Command: copy it, and Paste answer fills in the fields above. Read it, then Try it or Save it."
                    wrapMode: Text.Wrap
                    color: Color.menu.text
                    opacity: 0.7
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }
                TextField {
                    id: requestField
                    width: parent.width
                    foreground: Color.menu.text
                    placeholderText: "What should this slot do? e.g. toggle webcam blur"
                    onAccepted: root.copyPrompt()
                }
                Row {
                    spacing: Style.spacing.md
                    Button {
                        text: "Copy prompt"
                        iconText: "󰆏"
                        bordered: true
                        enabled: !copier.running
                        foreground: Color.menu.text
                        onClicked: root.copyPrompt()
                    }
                    Button {
                        text: "Paste answer"
                        iconText: "󰆒"
                        enabled: !paster.running
                        foreground: Color.menu.text
                        onClicked: root.pasteAnswer()
                    }
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: root.customStatus
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Color.accent
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }
            }
        }
    }
}
