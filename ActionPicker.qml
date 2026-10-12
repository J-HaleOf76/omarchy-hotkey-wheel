import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Actions.js" as Actions

// Modal layer for the picker card and its details window. Clicking outside
// the card closes only the picker, so the drawer underneath stays open;
// outside the details window, only that window.
Item {
    id: root
    property var screen: null
    property var library: []
    // The bar drawer: Save it and Rename go to it directly and report back.
    property var drawer: null
    readonly property bool opened: card.opened

    signal picked(int index, var action)
    signal closed()
    signal agentStarted()
    signal forget(string command)

    function show(index, action) { card.show(index, action) }
    function suggest(index, action, suggestion) { card.suggest(index, action, suggestion) }
    function close() { card.close() }

    PanelWindow {
        id: window
        screen: root.screen
        visible: card.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-hotkey-wheel-picker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: card.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle { anchors.fill: parent; color: Color.menu.scrim }
        MouseArea { anchors.fill: parent; onClicked: card.close() }

        PickerCard {
            id: card
            anchors.centerIn: parent
            width: Math.min(Style.space(560), window.width - Style.gapsOut * 2)
            height: Math.min(Style.space(620), window.height - Style.gapsOut * 2)
            onPicked: function(index, action) { root.picked(index, action) }
            onClosed: root.closed()
            library: root.library
            onAgentStarted: root.agentStarted()
            onForget: function(command) { root.forget(command) }
            drawer: root.drawer
            // Only the details window takes keys and clicks while it is open.
            enabled: card.details === null
        }

        Rectangle {
            anchors.fill: parent
            visible: card.details !== null
            color: Color.menu.scrim
            MouseArea { anchors.fill: parent; onClicked: card.closeDetails() }
        }

        ActionDetails {
            id: details
            anchors.centerIn: parent
            visible: card.details !== null
            width: Math.min(Style.space(620), window.width - Style.gapsOut * 2)
            height: Math.min(implicitHeight, Style.space(720), window.height - Style.gapsOut * 2)
            action: card.details
            suggested: card.detailsSuggested
            slot: card.slot
            status: card.detailsStatus
            onTryIt: card.detailsStatus = card.run(card.details.command)
            onUse: card.useDetails()
            onSaveIt: function(hash) {
                var action = Actions.pick(card.details)
                if (hash) action.scriptHash = hash
                card.keep(action)
            }
            onApprove: function(hash) { card.approveDetails(hash) }
            onRemove: card.removeDetails()
            onRenamed: function(action) { card.renameDetails(action) }
            onCloseRequested: card.closeDetails()
        }

        // Focus moves into the window, off every field, as soon as it opens.
        Connections {
            target: card
            function onDetailsChanged() { if (card.details) Qt.callLater(details.focusBody) }
        }
    }
}
