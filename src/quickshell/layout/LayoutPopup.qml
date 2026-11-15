// Layout picker: one card per Hyprland tiling layout (HyprLayout.layouts), the active one highlighted.
// Opened from the bar module "layout" (bar/faces/layout) via qs_manager.sh toggle layout.
import QtQuick
import Quickshell
import "../"
import "../reusables"

Item {
    id: root
    visible: false
    focus: true

    function s(val) { return Scaler.s(val) }

    // Main.qml calls startExit(cb) before hiding the popup
    property real intro: 0
    property var exitCallback: null
    function startExit(onFinished) {
        introAnim.stop()
        exitCallback = onFinished
        exitAnim.restart()
    }
    onVisibleChanged: {
        if (visible) { HyprLayout.refresh(); forceActiveFocus(); intro = 0; introAnim.restart() }
        else { introAnim.stop(); exitAnim.stop(); intro = 0 }
    }
    NumberAnimation { id: introAnim; target: root; property: "intro"; to: 1; duration: Motion.open; easing.type: Motion.openEasing }
    SequentialAnimation {
        id: exitAnim
        NumberAnimation { target: root; property: "intro"; to: 0; duration: Motion.close; easing.type: Motion.closeEasing }
        ScriptAction { script: { if (root.exitCallback) { let cb = root.exitCallback; root.exitCallback = null; cb() } } }
    }

    Keys.onEscapePressed: Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close", "layout"])

    Item {
        anchors.fill: parent
        scale: ConvexState.active ? 1 : 0.95 + 0.05 * root.intro   // convex: Main.qml slides it out of the bar
        transformOrigin: ConvexState.origin
        opacity: ConvexState.active ? 1 : root.intro
        transform: Translate { y: ConvexState.active ? 0 : root.s(20) * (1 - root.intro) }

        Rectangle {
            anchors.fill: parent
            radius: ThemeBackend.borderRadius
            // Convex bar style: square corners on sides attached to the bar or frame
            topLeftRadius: ConvexState.tl(radius)
            topRightRadius: ConvexState.tr(radius)
            bottomLeftRadius: ConvexState.bl(radius)
            bottomRightRadius: ConvexState.br(radius)
            color: Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
            clip: true

            WallpaperBlur {
                z: -1
                anchors.fill: parent
                topLeftRadius: parent.topLeftRadius
                topRightRadius: parent.topRightRadius
                bottomLeftRadius: parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius
            }

            Column {
                anchors { fill: parent; margins: root.s(16) }
                spacing: root.s(12)

                Item {
                    width: parent.width; height: root.s(34)
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Layout"; color: ThemeBackend.text; font.pixelSize: root.s(15); font.weight: Font.Bold }
                        Text {
                            text: HyprLayout.currentEntry.name + "  ·  all workspaces"
                            color: Qt.alpha(ThemeBackend.text, 0.45)
                            font.pixelSize: root.s(10)
                        }
                    }
                }

                Grid {
                    id: grid
                    width: parent.width
                    columns: 4
                    spacing: root.s(8)

                    Repeater {
                        model: HyprLayout.layouts

                        Rectangle {
                            id: card
                            readonly property bool active: HyprLayout.current === modelData.id
                            width: Math.floor((grid.width - grid.spacing * (grid.columns - 1)) / grid.columns)
                            height: root.s(86)
                            radius: Math.max(0, ThemeBackend.borderRadius - root.s(2))
                            color: active ? Qt.alpha(ThemeBackend.mauve, 0.22)
                                 : ma.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.65) : Qt.alpha(ThemeBackend.surface0, 0.55)
                            border.width: active ? root.s(1.5) : 0
                            border.color: ThemeBackend.mauve
                            Behavior on color { ColorAnimation { duration: 150 } }

                            LayoutPreview {
                                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: root.s(12) }
                                width: root.s(60); height: root.s(38)
                                rects: modelData.rects
                                color: card.active ? ThemeBackend.mauve : ThemeBackend.text
                                gap: root.s(3)
                                cornerRadius: root.s(3)
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: root.s(9) }
                                text: modelData.name
                                color: ThemeBackend.text
                                font.pixelSize: root.s(11)
                                font.weight: card.active ? Font.Bold : Font.Normal
                            }
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: HyprLayout.set(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
