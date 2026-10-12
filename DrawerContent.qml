import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Actions.js" as Actions

// The drawer's contents: Omarchy's panel header with the On switch, the wheel
// to click and drag, setup and the trigger, the slot count, and Save / Cancel.
// While the wheel is off, everything under the header is faded, as in
// Omarchy's own panels; it can still be edited.
Column {
    id: drawerContent
    required property var drawer
    spacing: Style.spacing.md

    PanelHero {
        width: parent.width
        title: "Hotkey Wheel"
        detail: drawer.dirty ? "Unsaved" : ""
        meta: drawer.setupState === "not-setup" ? "Not set up yet"
            : (drawer.saved.enabled ? Actions.triggerLabel(drawer.saved.trigger) : "Off")
              + " · " + drawer.draft.slots + " slots"
        foreground: Color.popups.text
        fontFamily: Style.font.menuFamily
        iconOpacity: drawer.saved.enabled ? 1 : 0.5
        // Off gives the button back to your apps; the slots are kept.
        trailingControl: Component {
            ToggleSwitch {
                checked: drawerContent.drawer.saved.enabled
                interactive: drawerContent.drawer.setupState === "setup" && !drawerContent.drawer.saving
                             && !drawerContent.drawer.helperBusy
                busy: drawerContent.drawer.helperBusy
                opacity: drawerContent.drawer.setupState === "setup" ? 1 : 0.5
                foreground: Color.popups.text
                onToggled: drawerContent.drawer.setEnabled(!drawerContent.drawer.saved.enabled)
            }
        }
        iconComponent: Component {
            Text {
                text: "󰄦"
                textFormat: Text.PlainText
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.display
            }
        }
    }

    Column {
        width: parent.width
        spacing: Style.spacing.md
        opacity: drawer.saved.enabled ? 1 : 0.4

        Item {
            width: parent.width
            height: face.height

            WheelFace {
                id: face
                anchors.horizontalCenter: parent.horizontalCenter
                radius: Math.min(parent.width / 2, Style.space(190))
                actions: drawer.draftSlots
                labels: drawer.draft.labels
                selected: slotDrag.active ? slotDrag.target : drawer.cursor
                dimmed: slotDrag.active ? slotDrag.from : -1
                editing: true
            }

            // Click a slot to change it; drag it onto another to swap the two.
            MouseArea {
                id: slotDrag
                anchors.fill: face
                hoverEnabled: true
                property int from: -1
                property int target: -1
                property bool active: false
                property point start
                cursorShape: active ? Qt.ClosedHandCursor : slotAt(mouseX, mouseY) >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                function slotAt(x, y) {
                    var dx = x - face.radius, dy = y - face.radius
                    if (dx * dx + dy * dy > face.radius * face.radius) return -1
                    return Actions.selection(x, y, face.radius, face.radius, face.inner, drawer.draftSlots.length)
                }
                onPressed: function(mouse) {
                    from = slotAt(mouse.x, mouse.y)
                    start = Qt.point(mouse.x, mouse.y)
                    active = false
                }
                onPositionChanged: function(mouse) {
                    var slot = slotAt(mouse.x, mouse.y)
                    if (pressed && from >= 0 && !active
                            && Math.abs(mouse.x - start.x) + Math.abs(mouse.y - start.y) > Style.space(12)) active = true
                    if (active) target = slot
                    else if (!pressed) drawer.cursor = slot
                }
                onReleased: function(mouse) {
                    if (active) {
                        if (target >= 0 && target !== from) drawer.swap(from, target)
                    } else if (from >= 0 && from === slotAt(mouse.x, mouse.y)) drawer.edit(from)
                    active = false
                    from = -1
                    target = -1
                }
                onExited: if (!drawer.pickerOpen && !pressed) drawer.cursor = -1
            }

            // What is being dragged, under the pointer.
            Column {
                visible: slotDrag.active && slotDrag.from >= 0
                x: face.x + slotDrag.mouseX - width / 2
                y: face.y + slotDrag.mouseY - height / 2
                spacing: Style.space(2)
                readonly property var action: slotDrag.from >= 0 ? drawer.draftSlots[slotDrag.from] : null
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.action ? parent.action.icon : ""
                    textFormat: Text.PlainText
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.space(25)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.action ? parent.action.label : ""
                    textFormat: Text.PlainText
                    color: Color.accent
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                }
            }
        }

        // Until Set up, Hyprland has no binding that opens the wheel.
        Item {
            width: parent.width
            visible: drawer.setupState === "not-setup"
            height: visible ? Math.max(setupText.implicitHeight, setupButton.implicitHeight) : 0
            Text {
                id: setupText
                anchors { left: parent.left; right: setupButton.left; rightMargin: Style.spacing.md; verticalCenter: parent.verticalCenter }
                text: "The wheel can't open from your mouse yet."
                wrapMode: Text.Wrap
                color: Color.popups.text
                font { family: Style.font.menuFamily; pixelSize: Style.font.body }
            }
            Button {
                id: setupButton
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: drawer.helperBusy ? "Setting up…" : "Set up"
                bordered: true
                enabled: !drawer.helperBusy
                onClicked: drawer.runHelper("setup")
            }
        }

        PanelSectionHeader {
            text: "OPEN WITH"
            foreground: Color.popups.text
            fontFamily: Style.font.menuFamily
        }
        Item {
            width: parent.width
            height: triggerChoice.implicitHeight
            ButtonGroup {
                id: triggerChoice
                anchors.verticalCenter: parent.verticalCenter
                options: Actions.triggers.map(function(t) {
                    var taken = drawer.conflicts[t.value]
                    return { value: t.value, label: t.short, tooltip: t.label + (taken ? " · also used by " + taken.join(", ") : "") }
                })
                value: drawer.saved.trigger
                focusable: false
                foreground: Color.popups.text
                fontFamily: Style.font.menuFamily
                enabled: drawer.saved.enabled && !drawer.saving && !drawer.helperBusy
                onChanged: function(value) { drawer.setTrigger(value) }
            }
        }
        Text {
            width: parent.width
            readonly property var taken: drawer.saved.enabled ? drawer.conflicts[drawer.saved.trigger] : null
            visible: !!taken || drawer.setupError.length > 0
            text: drawer.setupError || (taken ? Actions.triggerLabel(drawer.saved.trigger) + " is also bound to "
                + taken.join(", ") + "; the wheel takes it." : "")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: drawer.setupError ? Color.urgent : Color.popups.text
            opacity: drawer.setupError ? 1 : 0.7
            font { family: Style.font.menuFamily; pixelSize: Style.font.caption }
        }

        PanelSectionHeader {
            text: "SLOTS"
            foreground: Color.popups.text
            fontFamily: Style.font.menuFamily
        }
        Item {
            width: parent.width
            height: Math.max(slotCounts.implicitHeight, namesSwitch.implicitHeight)
            ButtonGroup {
                id: slotCounts
                anchors.verticalCenter: parent.verticalCenter
                options: Actions.slotCounts.map(function(n) { return { value: String(n), label: String(n) } })
                value: String(drawer.draft.slots)
                focusable: false
                foreground: Color.popups.text
                fontFamily: Style.font.menuFamily
                onChanged: function(value) { drawer.setSlots(Number(value)) }
            }
            // Names under the icons, like the slot count a draft until Save.
            Text {
                anchors { right: namesSwitch.left; rightMargin: Style.spacing.sm; verticalCenter: parent.verticalCenter }
                text: "Show names"
                color: Color.popups.text
                font { family: Style.font.menuFamily; pixelSize: Style.font.body }
            }
            ToggleSwitch {
                id: namesSwitch
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                checked: drawer.draft.labels
                foreground: Color.popups.text
                onToggled: drawer.setLabels(!drawer.draft.labels)
            }
        }

        Text {
            width: parent.width
            visible: text.length > 0
            text: drawer.configError
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Color.urgent
            font { family: Style.font.menuFamily; pixelSize: Style.font.body }
        }

        PanelSeparator { width: parent.width }

        Item {
            width: parent.width
            height: saveButton.implicitHeight
            Button {
                text: "Reset to defaults"
                iconText: "󰑓"
                enabled: !drawer.saving
                opacity: enabled ? 1 : 0.45
                onClicked: drawer.reset()
            }
            Row {
                anchors.right: parent.right
                spacing: Style.spacing.md
                Button {
                    text: "Cancel"
                    enabled: drawer.dirty && !drawer.saving
                    opacity: enabled ? 1 : 0.45
                    onClicked: drawer.discard()
                }
                Button {
                    id: saveButton
                    text: "Save"
                    bordered: true
                    enabled: drawer.dirty && !drawer.saving
                    opacity: enabled ? 1 : 0.45
                    onClicked: drawer.save()
                }
            }
        }
    }
}
