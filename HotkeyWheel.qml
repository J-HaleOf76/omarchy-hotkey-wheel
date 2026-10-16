import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "Actions.js" as Actions

Item {
    id: root
    property var shell: null
    property var manifest: null
    property bool opened: false
    property bool locating: false
    property bool holding: false
    property bool finishing: false
    property string gestureToken: ""
    // Recent released tokens: a release IPC can overtake its own press.
    property var releasedTokens: []
    // Bumped per gesture; cursor replies from an older gesture are dropped.
    property int generation: 0
    property int queryGeneration: -1
    property int selected: -1
    property real originX: 0
    property real originY: 0
    property var targetScreen: Quickshell.screens[0] || null
    // From the settings file; null until it loads (the defaults show meanwhile).
    property var settings: null
    readonly property var actions: Actions.visible(settings || Actions.defaults())
    // Direction of the pointer from the wheel's centre, for the hub's tick;
    // NaN while it rests in the dead zone.
    property real pointerAngle: NaN
    property string configError: ""
    property string pendingCommand: ""
    property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
                                + "/omarchy/extensions/hotkey-wheel.json"
    readonly property real radius: Math.min(Style.space(218), Math.min(panel.width, panel.height) / 2 - Style.space(20))
    readonly property real innerRadius: radius * 0.40
    readonly property real centerX: Actions.center(originX, radius + Style.space(8), panel.width)
    readonly property real centerY: Actions.center(originY, radius + Style.space(8), panel.height)
    readonly property var activeAction: selected >= 0 ? actions[selected] : null

    function open(payloadJson) {
        var payload = {}
        try { payload = JSON.parse(payloadJson || "{}") } catch (e) { return }
        if (!payload || typeof payload !== "object") return
        if (payload.mode === "hold" && payload.token && releasedTokens.indexOf(payload.token) !== -1) {
            // A late press for a finished gesture: never disturb a newer one.
            if (!opened && !locating) dismiss()
            return
        }
        if (pendingCommand) return
        // Click mode is open: dropping its keyboard grab for a hold now would
        // lose the button's release, so the trigger does nothing here.
        if (payload.mode === "hold" && opened && !holding) return
        generation++
        gestureToken = String(payload.token || "")
        holding = payload.mode === "hold"
        finishing = false
        selected = -1
        pointerAngle = NaN
        locating = true
        opened = false
        // Hyprland's events carry the pointer position; IPC callers do not.
        if (isFinite(payload.x) && isFinite(payload.y)) place(payload.x, payload.y)
        else queryCursor()
    }

    function queryCursor() {
        // A running query belongs to an older gesture; its reply re-queries.
        if (cursorQuery.running) return
        queryGeneration = generation
        cursorQuery.running = true
    }

    function place(x, y) {
        if (!locating) return
        locating = false
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; ++i) {
            var s = screens[i]
            if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) {
                targetScreen = s
                break
            }
        }
        if (!targetScreen) { dismiss(); return }
        originX = x - targetScreen.x
        originY = y - targetScreen.y
        opened = true
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    function close() {
        locating = false
        finishing = false
        opened = false
        holding = false
        selected = -1
        pointerAngle = NaN
    }

    function dismiss() {
        close()
        if (shell) shell.hide("io.github.erikrjohansson.hotkey-wheel")
    }

    // x and y are where the button was let go, when the caller knows it.
    function release(x, y) {
        if (!holding || finishing) return
        if (locating) { dismiss(); return }
        if (!opened) return
        if (isFinite(x) && isFinite(y)) {
            point(x - targetScreen.x, y - targetScreen.y)
            activate()
        } else {
            finishing = true
            queryCursor()
        }
    }

    function releaseGesture(token, x, y) {
        releasedTokens = releasedTokens.concat([token]).slice(-16)
        if (token === gestureToken) release(x, y)
    }

    // "<id> hold <token> x y", "<id> release <token> x y" and "<id> cancel"
    // from bindings.lua.
    function hyprlandEvent(data) {
        var parts = String(data).split(" ")
        if (parts[0] !== "io.github.erikrjohansson.hotkey-wheel") return
        var x = Number(parts[parts.length - 2]), y = Number(parts[parts.length - 1])
        if (parts[1] === "hold" && parts.length === 5)
            open(JSON.stringify({ mode: "hold", token: parts[2], x: x, y: y }))
        else if (parts[1] === "release" && parts.length === 5) releaseGesture(parts[2], x, y)
        else if (parts[1] === "cancel") dismiss()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "custom") root.hyprlandEvent(event.data) }
    }

    function activate() {
        var command = activeAction && activeAction.command ? activeAction.command : ""
        dismiss()
        if (!command || pendingCommand) return
        pendingCommand = command
        dispatchDelay.restart()
    }

    function reload() { settingsFile.reload() }

    function point(x, y) {
        // Both modes hit-test what is drawn: the shown centre, with the hub as
        // the dead zone. Hold mode keeps a smaller dead zone for quick flicks
        // and picks nothing until the pointer leaves where the gesture started,
        // so a wheel clamped at a screen edge never picks a slot at rest. In
        // click mode a click outside the wheel picks nothing.
        var dx = x - centerX, dy = y - centerY
        var clamped = centerX !== originX || centerY !== originY
        var deadZone = holding && !clamped ? Style.space(28) : innerRadius
        var armed = !holding || Math.hypot(x - originX, y - originY) >= Style.space(28)
        var inside = holding || dx * dx + dy * dy <= radius * radius
        selected = armed && inside ? Actions.selection(x, y, centerX, centerY, deadZone, actions.length) : -1
        pointerAngle = selected < 0 ? NaN : Math.atan2(dy, dx)
    }

    IpcHandler {
        target: "io.github.erikrjohansson.hotkey-wheel"
        function release(): void { root.release() }
        function releaseGesture(token: string): void { root.releaseGesture(token) }
        function cancel(): void { root.dismiss() }
        // The bar drawer saves the settings file; this picks it up even when
        // the file did not exist yet, which the watcher cannot see.
        function reload(): void { root.reload() }
        function status(): string {
            return JSON.stringify({ opened: root.opened, locating: root.locating,
                holding: root.holding, selected: root.selected,
                error: root.configError, gesture: root.gestureToken, released: root.releasedTokens })
        }
    }

    Process {
        id: cursorQuery
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector { id: cursorOutput; waitForEnd: true }
        onExited: function(code) {
            if (root.queryGeneration !== root.generation) {
                if (root.locating || root.finishing) root.queryCursor()
                return
            }
            if (!root.locating && !root.finishing) return
            try {
                var cursor = JSON.parse(cursorOutput.text)
                if (code !== 0 || !isFinite(cursor.x) || !isFinite(cursor.y)) throw new Error("cursor")
                if (root.finishing) {
                    root.point(cursor.x - root.targetScreen.x, cursor.y - root.targetScreen.y)
                    root.activate()
                } else root.place(cursor.x, cursor.y)
            } catch (e) { root.dismiss() }
        }
    }

    CursorTracker {
        active: root.opened && root.holding && !root.finishing
        onMoved: function(x, y) { root.point(x - root.targetScreen.x, y - root.targetScreen.y) }
    }

    // Execute through the compositor after the layer has released focus. This
    // also keeps shell-only Qt environment overrides out of launched apps.
    Timer {
        id: dispatchDelay
        interval: 100
        onTriggered: {
            var command = root.pendingCommand
            root.pendingCommand = ""
            if (command) Quickshell.execDetached(["hyprctl", "eval", "hl.exec_cmd(" + Actions.luaString(command) + ")"])
        }
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
                root.settings = Actions.validate(JSON.parse(text()))
                root.configError = ""
            } catch (e) { root.configError = "Settings not loaded: " + e.message }
        }
        onLoadFailed: function(error) {
            if (error !== FileViewError.FileNotFound) root.configError = "Could not read wheel settings."
        }
    }

    PanelWindow {
        id: panel
        screen: root.targetScreen
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-hotkey-wheel"
        WlrLayershell.layer: WlrLayer.Overlay
        // An exclusive keyboard grab resets held pointer buttons in Hyprland
        // 0.56. Keep hold mode pointer-only so its release binding survives.
        WlrLayershell.keyboardFocus: root.opened && !root.holding ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle { anchors.fill: parent; color: Color.menu.scrim }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true; return }
                var count = root.actions.length
                // 1–9 pick the first nine slots and 0 the tenth.
                var digit = event.key === Qt.Key_0 ? 10 : event.key >= Qt.Key_1 && event.key <= Qt.Key_9 ? event.key - Qt.Key_0 : 0
                if (digit) {
                    if (digit > count) return
                    root.selected = digit - 1
                    root.activate()
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.activate()
                else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
                    root.selected = (root.selected + 1) % count
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up)
                    root.selected = root.selected < 0 ? count - 1 : (root.selected + count - 1) % count
                else return
                event.accepted = true
            }

            WheelFace {
                x: root.centerX - root.radius
                y: root.centerY - root.radius
                radius: root.radius
                actions: root.actions
                labels: (root.settings || Actions.defaults()).labels
                selected: root.selected
                pointerAngle: root.pointerAngle
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPositionChanged: function(mouse) { root.point(mouse.x, mouse.y) }
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) root.dismiss()
                    else if (!root.holding && mouse.button === Qt.LeftButton) {
                        // Run what is under the click, not an arrow-key pick.
                        root.point(mouse.x, mouse.y)
                        root.activate()
                    }
                }
            }
        }
    }
}
