import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Actions.js" as Actions

// A custom action in full: what it does when picked, its command, and the
// script it runs. Opens over the picker for an agent's suggestion (Save it /
// Try it / Discard) and for a custom action from the list (Use / Try it /
// Remove / Rename). Renaming changes the name, icon and description, never the
// command. Buttons take clicks only, so keys typed elsewhere can't press them.
BorderSurface {
    id: root
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.panelPadding
    implicitHeight: contentTopInset + contentBottomInset + heading.implicitHeight + info.implicitHeight
                    + footer.implicitHeight + Style.spacing.md * 2

    property var action: null
    property bool suggested: false
    property int slot: 0
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
    // SHA-256 of the script as last read; Save it pins it (Actions.runCommand).
    property string scriptHash: ""
    // A pinned custom action whose script is no longer the approved one.
    readonly property bool scriptChanged: !suggested && !!action && !!action.scriptHash
                                          && scriptState === "ok" && scriptHash !== action.scriptHash
    // A pinned custom action whose script is gone or can't be shown, so it can't be approved.
    readonly property bool scriptLost: !suggested && !!action && !!action.scriptHash && scriptState === "hidden"
    readonly property var warnings: action ? Actions.warnings(action.command, scriptContents, home) : []
    readonly property int scriptLimit: 128 * 1024
    readonly property bool scriptHidden: Actions.hasHiddenChars(scriptContents)
    // A suggestion can only be tried or saved once its script, if any, is on
    // screen in full.
    readonly property bool reviewable: !unchecked && (!script || (scriptState === "ok" && Actions.validHash(scriptHash)))
    // A file in the scripts folder the command runs some other way, which
    // this window can't show or pin (Actions.uncheckedFile).
    readonly property string unchecked: action ? Actions.uncheckedFile(action.command, home) : ""
    property bool tried: false
    property bool editing: false
    // Shown over `status`: what the window itself has to say.
    property string notice: ""
    // The script folds away for a custom action, behind an arrow; an agent's
    // suggestion shows it open, since that is when it has to be read.
    property bool scriptOpen: false
    readonly property int scriptLines: scriptContents ? scriptContents.replace(/\n$/, "").split("\n").length : 0
    // Buttons that act wait a moment after what is shown changes, so a click
    // meant for the old one can't land on the new one.
    property bool armed: false
    // A click waits for the script to be read again. Only if it is what is on
    // screen does the click go through; otherwise the new one is shown.
    property string pendingAct: ""
    // Bumped whenever the action changes; a read started for an older one is
    // dropped, so a click can never land on the action that replaced it.
    property int generation: 0
    onActionChanged: {
        generation++
        pendingAct = ""
        editing = false
        tried = false
        notice = ""
        scriptOpen = suggested
        disarm()
        // After `script` follows the new action.
        scriptState = "loading"
        Qt.callLater(inspectScript)
    }
    onSuggestedChanged: scriptOpen = suggested
    // A changed script is shown open: approving it means reading it first.
    onScriptChangedChanged: if (scriptChanged) scriptOpen = true

    Timer { id: armTimer; interval: 700; onTriggered: root.armed = true }

    signal tryIt()
    signal use()
    // The hash of the script as shown, "" when the command runs no script.
    signal saveIt(string hash)
    signal approve(string hash)
    signal remove()
    signal renamed(var action)
    signal closeRequested()

    function focusBody() { body.forceActiveFocus() }

    function disarm() { armed = false; armTimer.restart() }

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
                  command: action.command, description: descriptionEdit.text.trim(), scriptHash: action.scriptHash })
        stopEditing()
    }

    function inspectScript() {
        scriptState = script ? "loading" : ""
        scriptContents = ""
        scriptNote = ""
        scriptHash = ""
        readScript("")
    }

    // "try", "save", "use" or "approve", from a button.
    function act(name) {
        if (!armed || pendingAct || scriptState === "loading") return
        notice = ""
        readScript(name)
    }

    // One read at a time: a read asked for while one runs starts when it ends,
    // and the older result is dropped.
    function readScript(name) {
        pendingAct = name
        if (scriptReader.running) { scriptReader.stale = true; return }
        startRead()
    }

    function startRead() {
        scriptReader.readFor = script
        scriptReader.generation = generation
        if (script) scriptReader.running = true
        else if (pendingAct) finish()
    }

    function finish() {
        var name = pendingAct
        pendingAct = ""
        if (!armed) return
        var hash = scriptState === "ok" ? scriptHash : ""
        if (name === "try") { tried = true; tryIt() }
        else if (name === "save") saveIt(hash)
        else if (name === "use") use()
        else if (name === "approve" && hash) approve(hash)
    }

    function scriptRead(code, out) {
        if (scriptReader.generation !== generation || scriptReader.readFor !== script) return
        var cut = out.indexOf("\n")
        var head = (cut < 0 ? out : out.slice(0, cut)).split(" ")
        var text = cut < 0 ? "" : out.slice(cut + 1)
        var state = "hidden", contents = "", note = "", hash = ""
        if (code !== 0) note = "Couldn't read it."
        else if (head[0] === "missing") note = "Script not found."
        else if (head[0] === "special") note = "Not a plain file, so it isn't shown."
        else if (head[0] === "large") note = "Too large to show here (over " + Math.round(scriptLimit / 1024) + " KB)."
        else if (head[0] === "encoding") note = "Not plain UTF-8 text, so it isn't shown."
        else if (head[0] !== "ok" || !Actions.validHash(head[1])) note = "Couldn't read it."
        else if (text.indexOf("\u0000") !== -1) note = "A binary file, so it isn't shown."
        else { state = "ok"; contents = text; hash = head[1] }
        var changed = scriptState !== "loading" && (state !== scriptState || contents !== scriptContents || note !== scriptNote)
        scriptState = state
        scriptContents = contents
        scriptNote = note
        scriptHash = Actions.validHash(hash) ? hash : ""
        if (!pendingAct) return
        if (changed) {
            pendingAct = ""
            scriptOpen = true
            notice = "The script changed since it was shown. Read it again before you go on."
            disarm()
            return
        }
        if (suggested && !reviewable && pendingAct !== "use") { pendingAct = ""; return }
        finish()
    }

    Process {
        id: scriptReader
        property string readFor: ""
        property int generation: -1
        property bool stale: false
        // One bounded snapshot: the bytes shown and the hash that pins them
        // come from the same read, and the size is checked in bytes before
        // any decoding.
        command: ["bash", "-c", 'p=$1 limit=$2
[[ -e $p ]] || { echo missing; exit 0; }
type=$(stat -L -c %F -- "$p") || exit 1
[[ $type == "regular file" || $type == "regular empty file" ]] || { echo special; exit 0; }
snap=$(mktemp) || exit 1
trap \'rm -f "$snap"\' EXIT
timeout 2 head -c "$((limit + 1))" -- "$p" > "$snap" || exit 1
(( $(stat -c %s -- "$snap") <= limit )) || { echo large; exit 0; }
iconv -f UTF-8 -t UTF-8 -- "$snap" > /dev/null 2>&1 || { echo encoding; exit 0; }
hash=$(sha256sum < "$snap") || exit 1
echo "ok ${hash%% *}"
cat -- "$snap"', "_", readFor, String(root.scriptLimit)]
        stdout: StdioCollector { id: readOutput; waitForEnd: true }
        onExited: function(code) {
            if (stale) { stale = false; root.startRead(); return }
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
                text: root.suggested ? "󰚩  Suggested by an agent for slot " + (root.slot + 1)
                                       + (root.tried ? " · tried, not saved" : " · not run yet")
                                     : "󰆓  Custom action"
                color: root.suggested ? Color.accent : Color.menu.text
                opacity: root.suggested ? 1 : 0.6
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
                    text: root.suggested ? "What it does, as the agent describes it" : "What it does when you pick it"
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
                Text {
                    visible: root.scriptChanged
                    width: parent.width
                    text: "󰀦  The script changed since you saved it, so its slot won't run it until you approve this version."
                    wrapMode: Text.Wrap
                    color: Color.urgent
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
                }
                Text {
                    visible: root.scriptLost
                    width: parent.width
                    text: "󰀦  Its slot won't run it: the script it was saved with can't be shown here, so this version can't be approved."
                    wrapMode: Text.Wrap
                    color: Color.urgent
                    font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
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
                text: root.editing ? "The command stays as it is; to change it, create a new action."
                    : root.notice || (root.suggested && root.unchecked
                                      ? "It runs " + root.unchecked + " in a way this window can't show or check, so it can't be tried or saved from here. Ask the agent to make the command the script's path, then any arguments."
                                      : root.suggested && !root.reviewable && root.scriptState !== "loading"
                                      ? "Its script can't be shown in full here, so it can't be tried or saved from this window."
                                      : "")
                    || root.status || (root.suggested
                    ? "Read it first. Try it runs it once; Save it puts it on slot " + (root.slot + 1)
                      + " and keeps it under Custom actions. Esc throws it away."
                    : root.scriptChanged ? "Read the new version above. Approve this version lets its slot run it again."
                    : "Use puts it on slot " + (root.slot + 1) + "; Save in the drawer keeps it there.")
                wrapMode: Text.Wrap
                readonly property bool loud: !root.editing && (root.notice || root.status || (root.suggested && !root.reviewable))
                color: root.notice ? Color.urgent : loud ? Color.accent : Color.menu.text
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
                visible: !root.editing
                spacing: Style.spacing.md
                Button {
                    visible: root.suggested
                    text: "Save it"
                    iconText: "󰆓"
                    bordered: true
                    enabled: root.armed && root.reviewable && !root.pendingAct
                    opacity: enabled ? 1 : 0.45
                    foreground: Color.menu.text
                    onClicked: root.act("save")
                }
                Button {
                    visible: root.scriptChanged
                    text: "Approve this version"
                    iconText: "󰄬"
                    bordered: true
                    enabled: root.armed && !root.pendingAct && root.scriptState !== "loading"
                    opacity: enabled ? 1 : 0.45
                    foreground: Color.menu.text
                    onClicked: root.act("approve")
                }
                Button {
                    visible: !root.suggested && !root.scriptChanged
                    text: "Use on slot " + (root.slot + 1)
                    bordered: true
                    enabled: root.armed && !root.pendingAct && root.scriptState !== "loading"
                    opacity: enabled ? 1 : 0.45
                    foreground: Color.menu.text
                    onClicked: root.act("use")
                }
                Button {
                    text: "Try it"
                    iconText: "󰐊"
                    enabled: root.armed && (root.reviewable || !root.suggested) && !root.pendingAct
                             && root.scriptState !== "loading"
                    opacity: enabled ? 1 : 0.45
                    foreground: Color.menu.text
                    onClicked: root.act("try")
                }
                Button {
                    visible: !root.suggested && !root.scriptChanged
                    text: "Rename"
                    iconText: "󰏫"
                    foreground: Color.menu.text
                    onClicked: root.startEditing()
                }
                Button {
                    visible: !root.suggested
                    text: "Remove"
                    iconText: "󰆴"
                    foreground: Color.menu.text
                    onClicked: root.remove()
                }
                Button {
                    text: root.suggested ? "Discard" : "Close"
                    iconText: "󰅖"
                    foreground: Color.menu.text
                    onClicked: root.closeRequested()
                }
            }
        }
    }
}
