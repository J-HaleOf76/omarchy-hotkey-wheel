import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
    id: root
    property real radius: Style.space(218)
    property var actions: []
    property int selected: -1
    // Drawer copy: slots are clicked to be changed, not run.
    property bool editing: false
    // Slot being dragged in the drawer, drawn faded; -1 when none.
    property int dimmed: -1
    // Slot names under the icons; the hub names the pointed slot either way.
    property bool labels: true
    // Direction of the pointer (radians, 0 = right) for the hub's tick; NaN hides it.
    property real pointerAngle: NaN
    readonly property real inner: radius * 0.40
    readonly property real labelRadius: radius * 0.71
    // Same border as Omarchy's own menu: theme colour or gradient, alpha and width.
    readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
    readonly property real borderWidth: Border.uniformWidth(borderSpec)
    readonly property real hubRadius: inner - Style.space(5)
    readonly property string palette: [Color.menu.background, Color.menu.text, borderSpec.color, borderWidth,
        borderSpec.gradient.colors.join(","), borderSpec.gradient.angle,
        Color.menu.selectedBackground, Color.menu.selectedText, Color.accent].join("|")
    width: radius * 2
    height: width
    onPaletteChanged: ring.requestPaint()
    onSelectedChanged: ring.requestPaint()
    onActionsChanged: ring.requestPaint()

    Canvas {
        id: ring
        anchors.fill: parent
        antialiasing: true
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            // The hidden panel has no size yet, which makes the radius negative.
            if (root.radius <= 2) return
            var border = root.borderSpec.gradient.enabled ? themeGradient(ctx) : root.borderSpec.color
            var edge = Math.max(2, root.borderWidth / 2 + 1)
            var n = root.actions.length
            for (var i = 0; i < n; ++i) {
                var step = 2 * Math.PI / n
                var start = -Math.PI / 2 + (i - 0.5) * step + 0.014
                var end = start + step - 0.028
                ctx.beginPath()
                ctx.arc(root.radius, root.radius, root.radius - edge, start, end)
                ctx.arc(root.radius, root.radius, root.inner, end, start, true)
                ctx.closePath()
                ctx.fillStyle = Color.menu.background
                ctx.fill()
                if (i === root.selected) {
                    ctx.fillStyle = Color.menu.selectedBackground
                    ctx.fill()
                    ctx.strokeStyle = Color.accent
                    ctx.lineWidth = Math.max(2, root.borderWidth)
                    ctx.stroke()
                } else if (root.borderWidth > 0) {
                    // Like the menu card: the theme border outlines the wheel, not every slice.
                    ctx.beginPath()
                    ctx.arc(root.radius, root.radius, root.radius - edge, start, end)
                    ctx.strokeStyle = border
                    ctx.lineWidth = root.borderWidth
                    ctx.stroke()
                }
            }
            ctx.beginPath()
            ctx.arc(root.radius, root.radius, root.hubRadius, 0, 2 * Math.PI)
            ctx.fillStyle = Color.menu.background
            ctx.fill()
            ctx.strokeStyle = border
            ctx.lineWidth = root.borderWidth
            if (ctx.lineWidth > 0) ctx.stroke()
        }

        // Matches the shell's BorderOverlay: one linear gradient across the whole surface.
        function themeGradient(ctx) {
            var g = root.borderSpec.gradient
            var rad = (Number(g.angle) || 0) * Math.PI / 180
            var dx = Math.cos(rad), dy = Math.sin(rad)
            var len = (Math.abs(width * dx) + Math.abs(height * dy)) / 2
            var grad = ctx.createLinearGradient(width / 2 - dx * len, height / 2 - dy * len,
                                                width / 2 + dx * len, height / 2 + dy * len)
            for (var i = 0; i < g.colors.length; ++i)
                grad.addColorStop(i / (g.colors.length - 1), g.colors[i])
            return grad
        }
    }

    Repeater {
        model: root.actions
        delegate: Column {
            required property int index
            required property var modelData
            readonly property real angle: -Math.PI / 2 + index * Math.PI * 2 / root.actions.length
            readonly property color ink: index === root.selected ? Color.menu.selectedText : Color.menu.text
            // Narrower when many slots share the ring, so labels never touch.
            width: Math.min(root.radius * 0.44, 2 * root.labelRadius * Math.sin(Math.PI / root.actions.length)
                            * (root.actions.length > 8 ? 1 : 0.9))
            x: root.radius + Math.cos(angle) * root.labelRadius - width / 2
            y: root.radius + Math.sin(angle) * root.labelRadius - height / 2
            spacing: Style.space(5)
            opacity: index === root.dimmed ? 0.25 : modelData.command ? 1 : 0.4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.icon
                textFormat: Text.PlainText
                color: parent.ink
                font.family: Style.font.family
                font.pixelSize: Style.space(25)
            }
            // Past eight slots the names get a touch smaller. Long names take
            // a second line, breaking between words only.
            Text {
                visible: root.labels
                width: parent.width
                text: modelData.label
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: parent.ink
                font.family: Style.font.menuFamily
                font.pixelSize: root.actions.length > 8 ? Math.round(Style.font.caption * 0.9) : Style.font.caption
            }
        }
    }

    // A bright arc on the hub's rim, turned toward the pointer. It uses the
    // menu's selected-text colour, which themes keep in contrast (the accent
    // can match the border). A vector shape, like Omarchy's own dials: a
    // rotated Canvas showed as a see-through square on real GPUs.
    Shape {
        id: pointerArc
        anchors.centerIn: parent
        width: root.hubRadius * 2
        height: width
        visible: isFinite(root.pointerAngle) && root.hubRadius > 2
        preferredRendererType: Shape.CurveRenderer
        rotation: isFinite(root.pointerAngle) ? root.pointerAngle * 180 / Math.PI : 0
        Behavior on rotation { RotationAnimation { duration: 60; direction: RotationAnimation.Shortest } }
        ShapePath {
            strokeColor: Color.menu.selectedText
            strokeWidth: Math.max(4, root.borderWidth + 3)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.hubRadius
                centerY: root.hubRadius
                radiusX: root.hubRadius
                radiusY: root.hubRadius
                startAngle: -17
                sweepAngle: 34
            }
        }
    }

    Item {
        anchors.centerIn: parent
        width: root.hubRadius * 2
        height: width
        Column {
            anchors.centerIn: parent
            // Narrower than the hub so wrapped lines stay inside the circle
            // above and below the middle, not just across it.
            width: root.hubRadius * 1.45
            spacing: Style.space(6)
            // At rest the hub shows the wheel's mark; pointing shows the slot.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.selected < 0 && !root.editing
                text: "󰄦"
                textFormat: Text.PlainText
                color: Color.menu.text
                opacity: 0.3
                font.family: Style.font.family
                font.pixelSize: Style.space(34)
            }
            Text {
                width: parent.width
                visible: root.selected >= 0
                text: root.selected >= 0 ? root.actions[root.selected].label : ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                color: Color.menu.text
            }
            Text {
                width: parent.width
                visible: root.editing && root.selected < 0
                text: "Click a slot to change it, or drag it onto another"
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                color: Color.menu.text
                opacity: 0.6
            }
        }
    }
}
