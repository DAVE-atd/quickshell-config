// Bar module "layout": current Hyprland tiling layout as a small wireframe. Click opens the picker
// (layout/LayoutPopup.qml), scroll cycles, right click toggles monocle. State: HyprLayout.
import QtQuick
import Quickshell
import "../../../reusables"
import "../../../"

Item {
    id: root

    property var module: null
    property var widget: module

    property string orientation: module ? module.orientation : "horizontal"
    readonly property bool isVertical: orientation === "vertical"

    readonly property bool isCompact: module ? module.isCompact : false
    readonly property var barWindow: module ? module.barWindow : null
    readonly property bool isPreview: module ? Boolean(module.isPreview) : false

    function s(val) { return barWindow ? barWindow.cs(val) : val }

    readonly property real pillSize: s(isCompact ? 28 : 30)
    implicitWidth: isVertical ? (parent ? parent.width : 0) : pill.width + s(isCompact ? 8 : 10)
    implicitHeight: isVertical ? pill.height + s(isCompact ? 8 : 10) : (parent ? parent.height : 0)

    property real wheelAcc: 0

    ClickButton {
        id: pill
        anchors.centerIn: parent
        height: root.pillSize
        width: root.isVertical ? root.pillSize : Math.round(root.pillSize * 1.35)
        cornerRadius: Math.max(0, ThemeBackend.borderRadius - root.s(2))
        accentColor: root.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: if (!root.isPreview && Caching.serpantinumDir)
            Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "layout"])
        onRightClicked: if (!root.isPreview) HyprLayout.toggle("monocle")
        onWheel: wheel => {
            if (root.isPreview) return;
            root.wheelAcc += wheel.angleDelta.y;
            if (Math.abs(root.wheelAcc) < 120) return;
            HyprLayout.cycle(root.wheelAcc > 0 ? -1 : 1);
            root.wheelAcc = 0;
        }

        LayoutPreview {
            anchors.centerIn: parent
            width: Math.round(root.pillSize * 0.72)
            height: Math.round(root.pillSize * 0.5)
            rects: HyprLayout.currentEntry.rects
            color: ThemeBackend.text
            gap: root.s(1.5)
            cornerRadius: root.s(1.5)
        }
    }
}
