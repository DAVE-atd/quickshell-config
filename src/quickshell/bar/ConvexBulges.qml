// Bar style "convex": one bulge per bar section (left / center / right) hanging off the frame strip,
// joined to it with concave corners. A section that reaches a screen side merges into the side frame
// (frame/ScreenFrame.qml) instead. Drawn opaque in ThemeBackend.base, like the strip and the frame.
// A popup attached to the bar (ConvexState, set by Main.qml) gets a bulge of its own width, so it
// hangs straight off the strip.
import QtQuick
import "../"

Item {
    id: root
    required property var bar          // TopBar's contentWrapper
    readonly property var barWindow: bar.barWindow
    anchors.fill: parent

    function s(v) { return barWindow ? barWindow.s(v) : v }

    readonly property bool atBottom: bar.barAtBottom
    readonly property real frame: barWindow ? barWindow.convexFrame : 0
    readonly property real barH: barWindow ? barWindow.barHeight : 0
    readonly property real edgeY: barWindow ? barWindow.baseOffsetY : 0   // top of the bar band
    readonly property real radius: bar.cornerRadius
    readonly property real join: Math.min(radius, barH - frame)
    readonly property real pad: s(8)
    readonly property color fill: ThemeBackend.base
    readonly property string cutout: "file://" + Caching.serpantinumDir + "/assets/shaders/ui/corner_cutout.frag.qsb"

    readonly property string screenName: barWindow && barWindow.screen ? (barWindow.screen.name || "") : ""
    readonly property real centerW: bar.cWidthTarget > 0 ? bar.cWidthTarget + 2 * pad : 0
    onCenterWChanged: ConvexState.setCenterW(screenName, centerW)
    onScreenNameChanged: ConvexState.setCenterW(screenName, centerW)
    Component.onCompleted: ConvexState.setCenterW(screenName, centerW)

    readonly property bool popupAttached: ConvexState.active && ConvexState.screenName === screenName
        && (atBottom ? ConvexState.squareBottom : ConvexState.squareTop)

    // pad: room around the pills; popup: square ends, exact edges, fades with the popup
    readonly property var sections: [
        { x: bar.lFinalX, w: bar.lWidthTarget, pad: pad, popup: false },
        { x: bar.cFinalX, w: bar.cWidthTarget, pad: pad, popup: false },
        { x: bar.rFinalClampedX, w: bar.rWidthTarget, pad: pad, popup: false },
        { x: ConvexState.x, w: popupAttached ? ConvexState.w : 0, pad: 0, popup: true }
    ]

    // Rounded inner corners of the screen frame on the bar's edge (frame/ScreenFrame.qml draws the rest)
    readonly property real frameRadius: s(16)
    Corner {
        x: root.frame
        y: root.atBottom ? root.edgeY + root.barH - root.frame - height : root.edgeY + root.frame
        width: root.frameRadius; height: root.frameRadius
        cornerIndex: root.atBottom ? 2 : 0
    }
    Corner {
        x: root.width - root.frame - width
        y: root.atBottom ? root.edgeY + root.barH - root.frame - height : root.edgeY + root.frame
        width: root.frameRadius; height: root.frameRadius
        cornerIndex: root.atBottom ? 3 : 1
    }

    Repeater {
        model: 4
        delegate: Item {
            id: sec
            required property int index
            readonly property var def: root.sections[index]
            readonly property bool used: def.w > 0
            // Sections close to a screen side grow into the side frame
            readonly property real reach: def.popup ? 0.5 : root.join
            readonly property bool touchLeft: def.x - def.pad <= root.frame + reach
            readonly property bool touchRight: def.x + def.w + def.pad >= root.width - root.frame - reach
            readonly property real x0: touchLeft ? 0 : def.x - def.pad
            readonly property real x1: touchRight ? root.width : def.x + def.w + def.pad
            readonly property real r: def.popup ? 0 : root.radius
            visible: used
            opacity: def.popup ? ConvexState.opacity : 1

            Rectangle {
                id: body
                x: sec.x0
                width: sec.x1 - sec.x0
                y: root.atBottom ? root.edgeY : root.edgeY + root.frame
                height: root.barH - root.frame
                color: root.fill
                topLeftRadius: root.atBottom && !sec.touchLeft ? sec.r : 0
                topRightRadius: root.atBottom && !sec.touchRight ? sec.r : 0
                bottomLeftRadius: !root.atBottom && !sec.touchLeft ? sec.r : 0
                bottomRightRadius: !root.atBottom && !sec.touchRight ? sec.r : 0

                // The popup bulge follows Main.qml's own animation
                Behavior on x { enabled: !sec.def.popup && root.bar.layoutAnimationsEnabled; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: !sec.def.popup && root.bar.layoutAnimationsEnabled; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }

            // Concave joins between the strip and the bulge's sides
            Corner {
                visible: !sec.touchLeft
                x: body.x - width
                y: root.atBottom ? root.edgeY + root.barH - root.frame - height : root.edgeY + root.frame
                cornerIndex: root.atBottom ? 3 : 1
            }
            Corner {
                visible: !sec.touchRight
                x: body.x + body.width
                y: root.atBottom ? root.edgeY + root.barH - root.frame - height : root.edgeY + root.frame
                cornerIndex: root.atBottom ? 2 : 0
            }
            // Joins between a bulge that reaches a screen side and the side frame
            Corner {
                visible: sec.touchLeft && !sec.def.popup
                x: root.frame
                y: root.atBottom ? root.edgeY - height : root.edgeY + root.barH
                cornerIndex: root.atBottom ? 2 : 0
            }
            Corner {
                visible: sec.touchRight && !sec.def.popup
                x: root.width - root.frame - width
                y: root.atBottom ? root.edgeY - height : root.edgeY + root.barH
                cornerIndex: root.atBottom ? 3 : 1
            }
        }
    }

    // cornerIndex: which corner of the square stays filled (0 TL, 1 TR, 2 BL, 3 BR)
    component Corner: ShaderEffect {
        property real cornerIndex: 0
        width: root.join
        height: root.join
        property vector2d itemSize: Qt.vector2d(width, height)
        property color color: root.fill
        fragmentShader: root.cutout
    }
}
