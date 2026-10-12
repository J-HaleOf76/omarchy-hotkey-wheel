import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Actions.js" as Actions

// The picker card: everything a slot can run, in tabs: desktop apps, curated
// Omarchy actions, every Omarchy keybinding, and custom actions (with a page to
// create one or ask an agent). ActionPicker hosts it in a modal layer, with the
// details window for a custom action or an agent's suggestion.
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
        detail: library.length ? "Your own command, or ask an agent" : "Saved ones show up here" })
    readonly property var results: tab === "custom" ? [createItem].concat(Actions.filter(itemsFor(tab), query))
                                                    : Actions.filter(itemsFor(tab), query)

    signal picked(int index, var action)
    signal closed()
    signal agentStarted()
    signal forget(string command)
    // The bar drawer (WheelDrawer): saveSlot and rename return "" or an error.
    property var drawer: null
    // Custom actions (see Actions.validateLibrary).
    property var library: []
    readonly property var libraryItems: library.map(function(a) {
        return { label: a.label, icon: a.icon, command: a.command, description: a.description || "",
                 scriptHash: a.scriptHash, detail: a.description || root.tidy(a.command), keywords: a.command, saved: true }
    })
    // The Custom tab's create page is showing.
    property bool creating: false
    // The action in the details window (ActionPicker shows it): a custom
    // action, or an agent's suggestion, which has not run; only Try it or
    // Save it (both clicks) act on it.
    property var details: null
    property bool detailsSuggested: false
    property string detailsStatus: ""

    // Agents found on PATH (ids from Actions.agents), and Custom tab feedback.
    property var foundAgents: []
    property string customStatus: ""
    // The agent whose prompt is shown for a yes/no before it opens.
    property string pendingAgent: ""
    readonly property string pendingAgentLabel: (foundAgents.filter(function(a) { return a.id === pendingAgent })[0] || { label: "" }).label
    readonly property string home: Quickshell.env("HOME")
    // Always in the home folder, where the details window can show and pin scripts.
    readonly property string scriptsDir: home + Actions.scriptsFolder
    // Omarchy installs agent launchers in ~/.local/bin, which the shell's own
    // PATH may not include.
    readonly property string agentPath: "PATH=\"$HOME/.local/bin:$PATH\"; "

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
        pendingAgent = ""
        query = ""
        cursor = 0
        if (tab === "bindings") loadBindings()
        customStatus = ""
        requestField.text = ""
        // The create form starts from the slot's own command, if it has one.
        var own = action.command ? action : { label: "", icon: "", command: "" }
        labelField.text = own.label
        iconField.text = own.icon
        descriptionField.text = own.description || ""
        commandField.text = own.command
        opened = true
        customScroll.contentY = 0
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

    // Opens on the Custom tab with the suggestion in the details window, which
    // takes keyboard focus off every field (see ActionPicker), so keys still
    // being typed in the agent's terminal can't edit or save it.
    function suggest(index, action, suggested) {
        var replacing = opened && details !== null && detailsSuggested
        show(index, action)
        awaitingBindings = ""
        tab = "custom"
        detailsSuggested = true
        details = suggested
        if (replacing) detailsStatus = "The agent sent a newer suggestion; this replaces the one you were reading."
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
        pendingAgent = ""
        if (on) customScroll.contentY = 0
        focusTab()
    }

    function showDetails(item) {
        detailsSuggested = false
        details = Actions.pick(item)
        detailsStatus = ""
    }

    function closeDetails() {
        details = null
        detailsStatus = ""
        focusTab()
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
    function saveCustom() {
        var label = labelField.text.trim()
        var command = commandField.text.trim()
        if (!label) { labelField.forceActiveFocus(); return }
        keep({ label: label, icon: iconField.text.trim() || Actions.glyphFor(label, command),
               description: descriptionField.text.trim(), command: command })
    }

    // Stays open, with the reason, when the drawer can't save it.
    function keep(action) {
        var chosen = Actions.pick(action)
        chosen.custom = true
        var refused = drawer ? drawer.saveSlot(slot, chosen) : "The wheel's drawer isn't available."
        if (refused) {
            if (details) detailsStatus = refused
            else customStatus = refused
            return
        }
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

    // A pinned action whose script changed: the version now on screen becomes the approved one.
    function approveDetails(hash) {
        var after = Actions.pick(details)
        after.scriptHash = hash
        var refused = drawer ? drawer.rename(details, after) : "The wheel's drawer isn't available."
        if (refused) { detailsStatus = refused; return }
        details = after
        detailsStatus = "Approved. Its slot runs this version now."
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
        return Actions.agentPrompt(slot + 1, current, requestField.text, scriptsDir)
    }

    function copyPrompt() {
        Quickshell.execDetached(["wl-copy", prompt()])
        customStatus = "Prompt copied. Paste it into any agent."
    }

    // Through Hyprland like the wheel's own commands, so the terminal does not
    // inherit the shell's Qt environment. The agent starts in the scripts folder.
    function askAgent(agent) {
        var script = agentPath + 'mkdir -p "$1" && cd "$1" && exec "$2" "$3"'
        var command = "omarchy-launch-tui --app-id=org.omarchy.hotkey-wheel-agent bash -c "
            + Actions.shellQuote(script) + " _ " + Actions.shellQuote(scriptsDir) + " "
            + Actions.shellQuote(agent) + " " + Actions.shellQuote(prompt())
        Quickshell.execDetached(["hyprctl", "eval", "hl.exec_cmd(" + Actions.luaString(command) + ")"])
        close()
        agentStarted()
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
        running: true
        command: ["bash", "-c", root.agentPath + 'for a in "$@"; do command -v "$a" >/dev/null && echo "$a"; done', "_"]
            .concat(Actions.agents.map(function(a) { return a.id }))
        stdout: StdioCollector { id: agentOutput; waitForEnd: true }
        onExited: {
            var found = agentOutput.text.split("\n")
            root.foundAgents = Actions.agents.filter(function(a) { return found.indexOf(a.id) !== -1 })
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
                if (root.pendingAgent) root.pendingAgent = ""
                else if (root.creating) root.setCreating(false)
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

        // Create new action: your own command, or ask an agent. Scrolls on short screens.
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
                    onClicked: root.setCreating(false)
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
                        onAccepted: root.saveCustom()
                    }
                    TextField {
                        id: iconField
                        width: Style.space(124)
                        foreground: Color.menu.text
                        placeholderText: "Icon (auto)"
                        maximumLength: 16
                        onAccepted: root.saveCustom()
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
                    onAccepted: root.saveCustom()
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
                    onAccepted: root.saveCustom()
                }
                Row {
                    spacing: Style.spacing.md
                    Button {
                        text: "Save it"
                        iconText: "󰆓"
                        bordered: true
                        foreground: Color.menu.text
                        onClicked: root.saveCustom()
                    }
                    Button {
                        text: "Try it"
                        iconText: "󰐊"
                        foreground: Color.menu.text
                        onClicked: root.customStatus = root.run(commandField.text.trim())
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
                    text: "Save it puts it on slot " + (root.slot + 1) + " right away and keeps it under Custom actions."
                    wrapMode: Text.Wrap
                    color: Color.menu.text
                    opacity: 0.55
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }

                Item { width: 1; height: Style.spacing.md }
                Rectangle { width: parent.width; height: 1; color: Color.menu.text; opacity: 0.15 }

                Text {
                    text: "󰚩  Ask an agent"
                    color: Color.menu.text
                    font { family: Style.font.menuFamily; pixelSize: Style.font.body; bold: true }
                }
                Text {
                    width: parent.width
                    text: "Its suggestion opens here with what it does, for you to read, try and save. The agent is told not to run it."
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
                    onAccepted: root.foundAgents.length ? root.pendingAgent = root.foundAgents[0].id : root.copyPrompt()
                }
                Row {
                    visible: !root.pendingAgent
                    spacing: Style.spacing.md
                    Repeater {
                        model: root.foundAgents
                        Button {
                            required property var modelData
                            text: "Open in " + modelData.label
                            bordered: true
                            foreground: Color.menu.text
                            onClicked: root.pendingAgent = modelData.id
                        }
                    }
                    Button {
                        text: "Copy prompt"
                        iconText: "󰆏"
                        foreground: Color.menu.text
                        onClicked: root.copyPrompt()
                    }
                }
                // The exact prompt, read before anything opens. Sending takes a click.
                Column {
                    visible: root.pendingAgent.length > 0
                    width: parent.width
                    spacing: Style.spacing.md
                    Text {
                        width: parent.width
                        text: "This is what " + root.pendingAgentLabel + " will get. Send it?"
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Color.accent
                        font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                    }
                    Rectangle {
                        width: parent.width
                        height: Math.min(promptBody.implicitHeight + Style.spacing.md * 2, Style.space(260))
                        radius: Style.cornerRadius
                        color: Qt.rgba(0, 0, 0, 0.18)

                        Flickable {
                            anchors { fill: parent; margins: Style.spacing.md }
                            contentHeight: promptBody.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            Text {
                                id: promptBody
                                width: parent.width
                                text: root.pendingAgent ? root.prompt() : ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: Color.menu.text
                                opacity: 0.8
                                font { family: Style.font.family; pixelSize: Style.font.caption }
                            }
                        }
                    }
                    Row {
                        spacing: Style.spacing.md
                        Button {
                            text: "Send to " + root.pendingAgentLabel
                            bordered: true
                            foreground: Color.menu.text
                            onClicked: root.askAgent(root.pendingAgent)
                        }
                        Button {
                            text: "Back"
                            foreground: Color.menu.text
                            onClicked: root.pendingAgent = ""
                        }
                    }
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: root.customStatus
                    wrapMode: Text.Wrap
                    color: Color.accent
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }
            }
        }
    }
}
