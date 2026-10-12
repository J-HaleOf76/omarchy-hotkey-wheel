import QtQuick
import qs.Ui

BarWidget {
    id: root
    moduleName: "io.github.erikrjohansson.hotkey-wheel"
    readonly property bool opened: drawer.item ? drawer.item.opened : false
    readonly property bool popoutSwitchClosing: drawer.item ? drawer.item.popoutSwitchClosing : false
    function open() { if (drawer.item) drawer.item.open() }
    function close() { if (drawer.item) drawer.item.close() }
    function toggle() { if (opened) close(); else open() }
    function closeForPopoutSwitch() { if (drawer.item) drawer.item.closeForPopoutSwitch() }
    function inject() {
        if (!drawer.item) return
        drawer.item.bar = root.bar
        drawer.item.anchorItem = button
        drawer.item.hostWidget = root
    }
    onBarChanged: inject()
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    Loader {
        id: drawer
        source: Qt.resolvedUrl("WheelDrawer.qml")
        visible: false
        onLoaded: { root.inject(); Qt.callLater(root.inject) }
    }
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰄦"
        active: root.opened
        tooltipText: "Hotkey Wheel"
        onPressed: root.toggle()
    }
}
