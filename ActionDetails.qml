import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Actions.js" as Actions

// A custom action in full: what it does when picked, its command, and the
// script it runs. Opens over the picker for a custom action from the list:
// Use, Try it, Rename, Remove. Renaming changes the name, icon and
// description, never the command. For a new action from the create page
// (`confirm` "try" or "save") it asks before Try it or Save it goes on, with
// the script open; Yes takes a click, a moment after the window opens.
BorderSurface {
    id: root
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.panelPadding
    implicitHeight: contentTopInset + contentBottomInset + heading.implicitHeight + info.implicitHeight
                    + footer.implicitHeight + Style.spacing.md * 2

    property var action: null
    property int slot: 0
    property string confirm: ""
    // Yes is off for a moment, so the click that opened the window can't land on it.
    property bool armed: false
    property string status: ""
    readonly property string home: Quickshell.env("HOME")
    readonly property string script: action ? Actions.scriptPath(action.command, home) : ""
    // The script as last read: "" (none), "loading", "ok" (shown in full) or
    // "hidden" (scriptNote says why). Reads are bounded (a regular file of at
    // most scriptLimit bytes, with a timeout), so an app image or a pipe in the
    // home folder is never loaded or waited on.
    property string scriptState: ""
    property string scriptContents: ""
    property string scriptNote: ""
    readonly property var warnings: action ? Actions.warnings(action.command, scriptContents, home) : []
    readonly property int scriptLimit: 128 * 1024
    readonly property bool scriptHidden: Actions.hasHiddenChars(scriptContents)
    property bool editing: false
    // The script folds away behind an arrow.
    property bool scriptOpen: false
    readonly property int scriptLines: scriptContents ? scriptContents.replace(/\n$/, "").split("\n").length : 0
    // Bumped whenever the action changes; a read started for an older one is dropped.
    property int generation: 0
    onActionChanged: {
        generation++
        editing = false
        scriptOpen = confirm.length > 0
        armed = false
        if (confirm) armTimer.restart()
        Qt.callLater(inspectScript)
    }

    Timer { id: armTimer; interval: 700; onTriggered: root.armed = true }

    signal tryIt()
    signal use()
    signal remove()
    signal renamed(var action)
    signal closeRequested()
    signal confirmed()

    function focusBody() { body.forceActiveFocus() }

    function startEditing() {
        labelEdit.text = action.label
        iconEdit.text = action.icon
        descriptionEdit.text = action.description || ""
        editing = true
        labelEdit.forceActiveFocus()
    }

    function stopEditing() {
        editing = false
        focusBody()
    }

    function finishEditing() {
        var label = labelEdit.text.trim()
        if (!label) { labelEdit.forceActiveFocus(); return }
        renamed({ label: label, icon: iconEdit.text.trim() || Actions.glyphFor(label, action.command),
                  command: action.command, description: descriptionEdit.text.trim() })
        stopEditing()
    }

    // One read at a time: one asked for while another runs starts when it ends.
    function inspectScript() {
        scriptState = script ? "loading" : ""
        scriptContents = ""
        scriptNote = ""
        if (!script) return
        if (scriptReader.running) { scriptReader.stale = true; return }
        scriptReader.readFor = script
        scriptReader.generation = generation
        scriptReader.running = true
    }

    function scriptRead(code, out) {
        if (scriptReader.generation !== generation || scriptReader.readFor !== script) return
        var cut = out.indexOf("\n")
        var head = cut < 0 ? out : out.slice(0, cut)
        var text = cut < 0 ? "" : out.slice(cut + 1)
        var note = ""
        if (code !== 0) note = "Couldn't read it."
        else if (head === "missing") note = "Script not found."
        else if (head === "special") note = "Not a plain file, so it isn't shown."
        else if (head === "large") note = "Too large to show here (over " + Math.round(scriptLimit / 1024) + " KB)."
        else if (head === "encoding") note = "Not plain UTF-8 text, so it isn't shown."
        else if (head !== "ok") note = "Couldn't read it."
        else if (text.indexOf("\u0000") !== -1) note = "A binary file, so it isn't shown."
        scriptState = note ? "hidden" : "ok"
        scriptContents = note ? "" : text
        scriptNote = note
    }

    Process {
        id: scriptReader
        property string readFor: ""
        property int generation: -1
        property bool stale: false
        // The size is checked in bytes before any decoding; stat answers in
        // English whatever the user's language.
        command: ["bash", "-c", 'p=$1 limit=$2
export LC_ALL=C
[[ -e $p ]] || { echo missing; exit 0; }
type=$(stat -L -c %F -- "$p") || exit 1
[[ $type == "regular file" || $type == "regular empty file" ]] || { echo special; exit 0; }
snap=$(mktemp) || exit 1
trap \'rm -f "$snap"\' EXIT
timeout 2 head -c "$((limit + 1))" -- "$p" > "$snap" || exit 1
(( $(stat -c %s -- "$snap") <= limit )) || { echo large; exit 0; }
iconv -f UTF-8 -t UTF-8 -- "$snap" > /dev/null 2>&1 || { echo encoding; exit 0; }
echo ok
cat -- "$snap"', "_", readFor, String(root.scriptLimit)]
        stdout: StdioCollector { id: readOutput; waitForEnd: true }
        onExited: function(code) {
            if (stale) { stale = false; root.inspectScript(); return }
            root.scriptRead(code, readOutput.text)
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
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { if (root.editing) root.stopEditing(); else root.closeRequested(); event.accepted = true }
        }

        Column {
            id: heading
            width: parent.width
            spacing: Style.space(6)
            Row {
                width: parent.width
                visible: !root.editing
                spacing: Style.spacing.md
                Text {
                    id: glyph
                    text: root.action ? root.action.icon : ""
                    textFormat: Text.PlainText
                    color: Color.menu.text
                    font { family: Style.font.family; pixelSize: Style.font.title }
                }
                Text {
                    width: parent.width - glyph.width - parent.spacing
                    text: root.action ? root.action.label : ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Color.menu.text
                    font { family: Style.font.menuFamily; pixelSize: Style.font.title }
                }
            }
            Row {
                width: parent.width
                visible: root.editing
                spacing: Style.spacing.md
                TextField {
                    id: labelEdit
                    width: parent.width - iconEdit.width - parent.spacing
                    foreground: Color.menu.text
                    placeholderText: "Name"
                    maximumLength: 64
                    onAccepted: root.finishEditing()
                }
                TextField {
                    id: iconEdit
                    width: Style.space(124)
                    foreground: Color.menu.text
                    placeholderText: "Icon (auto)"
                    maximumLength: 16
                    onAccepted: root.finishEditing()
                }
            }
            Text {
                text: root.confirm ? "󰐕  New action · not saved yet" : "󰆓  Custom action"
                color: Color.menu.text
                opacity: 0.6
                font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
            }
        }

        Flickable {
            anchors { top: heading.bottom; topMargin: Style.spacing.md; bottom: footer.top; bottomMargin: Style.spacing.md }
            width: parent.width
            contentHeight: info.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: info
                width: parent.width
                spacing: Style.space(6)

                Text {
                    text: "What it does when you pick it"
                    color: Color.menu.text
                    font { family: Style.font.menuFamily; pixelSize: Style.font.body; bold: true }
                }
                TextField {
                    id: descriptionEdit
                    visible: root.editing
                    width: parent.width
                    foreground: Color.menu.text
                    placeholderText: "What it does when you pick it (optional)"
                    maximumLength: Actions.descriptionLimit
                    onAccepted: root.finishEditing()
                }
                Text {
                    visible: !root.editing
                    width: parent.width
                    text: root.action && root.action.description ? root.action.description
                        : "No description. It runs the command below."
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Color.menu.text
                    opacity: root.action && root.action.description ? 1 : 0.6
                    font { family: Style.font.menuFamily; pixelSize: Style.font.body }
                }

                Item { width: 1; height: Style.spacing.md }
                Text {
                    text: "Command"
                    color: Color.menu.text
                    font { family: Style.font.menuFamily; pixelSize: Style.font.body; bold: true }
                }
                Rectangle {
                    width: parent.width
                    height: commandText.implicitHeight + Style.spacing.md * 2
                    radius: Style.cornerRadius
                    color: Qt.rgba(0, 0, 0, 0.18)
                    Text {
                        id: commandText
                        x: Style.spacing.md
                        y: Style.spacing.md
                        width: parent.width - Style.spacing.md * 2
                        text: root.action ? (root.action.command || "(empty: the slot does nothing)") : ""
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        color: Color.menu.text
                        opacity: 0.85
                        font { family: Style.font.family; pixelSize: Style.font.caption }
                    }
                }

                Repeater {
                    model: root.warnings
                    Text {
                        required property string modelData
                        width: info.width
                        text: "󰀦  " + modelData
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Color.urgent
                        font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                    }
                }
                Item { width: 1; height: Style.spacing.md; visible: root.script.length > 0 }
                // Click anywhere on the header to fold or unfold the script.
                Item {
                    visible: root.script.length > 0
                    width: parent.width
                    height: scriptHeader.implicitHeight
                    Row {
                        id: scriptHeader
                        spacing: Style.spacing.md
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.scriptOpen ? "󰅀" : "󰅂"
                            color: Color.menu.text
                            font { family: Style.font.family; pixelSize: Style.font.body }
                        }
                        Text {
                            id: scriptTitle
                            text: "Script"
                            color: Color.menu.text
                            font { family: Style.font.menuFamily; pixelSize: Style.font.body; bold: true }
                        }
                        Text {
                            anchors.baseline: scriptTitle.baseline
                            text: root.scriptState === "loading" ? "reading…" : root.scriptState === "hidden" ? "not shown"
                                : root.scriptLines === 1 ? "1 line" : root.scriptLines + " lines"
                            color: Color.menu.text
                            opacity: 0.55
                            font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.scriptOpen = !root.scriptOpen
                    }
                }
                Text {
                    visible: root.script.length > 0 && root.scriptHidden
                    width: parent.width
                    text: "󰀦  The script has invisible or right-to-left characters, so what you read may not be what runs."
                    wrapMode: Text.Wrap
                    color: Color.urgent
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }
                Text {
                    visible: root.script.length > 0 && root.scriptOpen
                    width: parent.width
                    text: root.script
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: Color.menu.text
                    opacity: 0.55
                    font { family: Style.font.family; pixelSize: Style.font.caption }
                }
                Rectangle {
                    visible: root.script.length > 0 && root.scriptOpen
                    width: parent.width
                    height: visible ? scriptBody.implicitHeight + Style.spacing.md * 2 : 0
                    radius: Style.cornerRadius
                    color: Qt.rgba(0, 0, 0, 0.18)
                    Text {
                        id: scriptBody
                        x: Style.spacing.md
                        y: Style.spacing.md
                        width: parent.width - Style.spacing.md * 2
                        text: root.scriptState === "ok" ? root.scriptContents : root.scriptNote
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        color: Color.menu.text
                        opacity: 0.85
                        font { family: Style.font.family; pixelSize: Style.font.caption }
                    }
                }
            }
        }

        Column {
            id: footer
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: Style.spacing.md

            Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.editing ? "The command stays as it is; to change it, create a new action."
                    : root.confirm === "try" ? "Have you read what the command and its script do? Try it runs it now, as you."
                    : root.confirm === "save" ? "Have you read what the command and its script do? Save it puts it on slot "
                        + (root.slot + 1) + ", where it runs every time you pick it."
                    : root.status || "Use puts it on slot " + (root.slot + 1) + "; Save in the drawer keeps it there."
                wrapMode: Text.Wrap
                readonly property bool loud: !root.editing && (root.confirm.length > 0 || root.status.length > 0)
                color: loud ? Color.accent : Color.menu.text
                opacity: loud ? 1 : 0.55
                font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
            }
            Row {
                visible: root.editing
                spacing: Style.spacing.md
                Button {
                    text: "Save"
                    iconText: "󰆓"
                    bordered: true
                    foreground: Color.menu.text
                    onClicked: root.finishEditing()
                }
                Button {
                    text: "Cancel"
                    foreground: Color.menu.text
                    onClicked: root.stopEditing()
                }
            }
            Row {
                visible: root.confirm.length > 0
                spacing: Style.spacing.md
                Button {
                    text: root.confirm === "save" ? "Yes, save it" : "Yes, try it"
                    iconText: root.confirm === "save" ? "󰆓" : "󰐊"
                    bordered: true
                    enabled: root.armed
                    opacity: enabled ? 1 : 0.45
                    foreground: Color.menu.text
                    onClicked: if (root.armed) root.confirmed()
                }
                Button {
                    text: "No"
                    iconText: "󰅖"
                    foreground: Color.menu.text
                    onClicked: root.closeRequested()
                }
            }
            Row {
                visible: !root.editing && root.confirm.length === 0
                spacing: Style.spacing.md
                Button {
                    text: "Use on slot " + (root.slot + 1)
                    bordered: true
                    foreground: Color.menu.text
                    onClicked: root.use()
                }
                Button {
                    text: "Try it"
                    iconText: "󰐊"
                    foreground: Color.menu.text
                    onClicked: root.tryIt()
                }
                Button {
                    text: "Rename"
                    iconText: "󰏫"
                    foreground: Color.menu.text
                    onClicked: root.startEditing()
                }
                Button {
                    text: "Remove"
                    iconText: "󰆴"
                    foreground: Color.menu.text
                    onClicked: root.remove()
                }
                Button {
                    text: "Close"
                    iconText: "󰅖"
                    foreground: Color.menu.text
                    onClicked: root.closeRequested()
                }
            }
        }
    }
}
