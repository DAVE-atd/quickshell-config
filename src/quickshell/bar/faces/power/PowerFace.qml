// Bar module "power": opens the power menu (power/PowerMenu.qml), same as Ctrl+Alt+Del.
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

    ClickButton {
        id: pill
        anchors.centerIn: parent
        height: root.pillSize
        width: root.pillSize
        cornerRadius: Math.max(0, ThemeBackend.borderRadius - root.s(2))
        horizontalPadding: 0
        buttonIcon: "󰐥"
        iconFontSize: root.s(root.isCompact ? 14 : 15)
        accentColor: root.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
        textColor: ThemeBackend.red

        onClicked: if (!root.isPreview && Caching.serpantinumDir)
            Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "power"])
    }
}
