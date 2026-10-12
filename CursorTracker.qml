import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property bool active: false
    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/"
        + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket.sock"
    signal moved(real x, real y)

    // Held buttons retain pointer focus on the original surface. Read local
    // compositor IPC during a gesture, with no process per frame or idle work.
    Timer {
        interval: 16
        running: root.active
        repeat: true
        onTriggered: if (!socket.connected) socket.connected = true
    }
    Socket {
        id: socket
        path: root.socketPath
        onConnectionStateChanged: if (connected) { write("j/cursorpos"); flush() }
        onError: {}
        parser: SplitParser {
            splitMarker: "}"
            onRead: function(data) {
                if (!root.active) return
                try {
                    var point = JSON.parse(data + "}")
                    if (isFinite(point.x) && isFinite(point.y)) root.moved(point.x, point.y)
                } catch (e) {}
            }
        }
    }
}
