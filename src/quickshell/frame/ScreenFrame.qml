// Bar style "convex": thin frame around the screen with rounded inner corners.
// The bar draws the strip on its own edge (bar/TopBar.qml + bar/ConvexBulges.qml); this draws the other
// three edges and reserves their space so tiled windows stay inside the frame.
// Only for a top or bottom bar; left/right bars fall back to the fill look.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

Variants {
    id: root

    property int configRevision: 0
    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() { root.configRevision++ }
        function onRawSettingsChanged() { root.configRevision++ }
    }

    readonly property var barSettings: {
        void configRevision
        return (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) ? Config.rawSettings.bar : {}
    }
    readonly property string barPosition: barSettings.position || "top"
    readonly property bool active: barSettings.style === "convex" && (barPosition === "top" || barPosition === "bottom")

    // Must match bar/Bar.qml (convexFrame: s(7))
    readonly property int thickness: Math.round(Scaler.s(7))
    readonly property int radius: Math.round(Scaler.s(16))

    model: active ? Quickshell.screens : []

    delegate: Scope {
        id: scope
        required property var modelData
        readonly property bool barAtBottom: root.barPosition === "bottom"

        // ── Drawing: fullscreen, click-through ────────────────────────────────
        PanelWindow {
            id: frameWin
            screen: scope.modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "qs-frame"
            color: "transparent"
            mask: Region {}

            readonly property int t: root.thickness
            readonly property int r: root.radius
            readonly property string cutout: "file://" + Caching.serpantinumDir + "/assets/shaders/ui/corner_cutout.frag.qsb"

            // Edge opposite the bar (full width)
            Rectangle {
                x: 0; width: parent.width; height: frameWin.t
                y: scope.barAtBottom ? 0 : parent.height - frameWin.t
                color: ThemeBackend.base
            }
            // Side edges, between the two horizontal strips
            Rectangle { x: 0; y: frameWin.t; width: frameWin.t; height: parent.height - 2 * frameWin.t; color: ThemeBackend.base }
            Rectangle { x: parent.width - frameWin.t; y: frameWin.t; width: frameWin.t; height: parent.height - 2 * frameWin.t; color: ThemeBackend.base }

            // Rounded inner corners (cornerIndex = filled corner: 0 TL, 1 TR, 2 BL, 3 BR)
            Repeater {
                model: [
                    { x: frameWin.t,                          y: frameWin.t,                           c: 0 },
                    { x: frameWin.width - frameWin.t - frameWin.r, y: frameWin.t,                      c: 1 },
                    { x: frameWin.t,                          y: frameWin.height - frameWin.t - frameWin.r, c: 2 },
                    { x: frameWin.width - frameWin.t - frameWin.r, y: frameWin.height - frameWin.t - frameWin.r, c: 3 }
                ]
                delegate: ShaderEffect {
                    required property var modelData
                    x: modelData.x; y: modelData.y
                    width: frameWin.r; height: frameWin.r
                    property real cornerIndex: modelData.c
                    property vector2d itemSize: Qt.vector2d(width, height)
                    property color color: ThemeBackend.base
                    fragmentShader: frameWin.cutout
                }
            }
        }

        // ── Reserved space on the three edges without the bar ─────────────────
        Variants {
            model: scope.barAtBottom ? ["top", "left", "right"] : ["bottom", "left", "right"]
            delegate: PanelWindow {
                required property string modelData
                screen: scope.modelData
                anchors {
                    top: modelData !== "bottom"
                    bottom: modelData !== "top"
                    left: modelData !== "right"
                    right: modelData !== "left"
                }
                implicitWidth: root.thickness
                implicitHeight: root.thickness
                exclusiveZone: root.thickness
                // Overlay: arranged after the bar (Top), so the bar keeps the full screen width
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "qs-frame-zone"
                color: "transparent"
                mask: Region {}
            }
        }
    }
}
