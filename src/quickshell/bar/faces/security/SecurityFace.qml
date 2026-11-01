// Bar module "security": ClamAV shield. Click opens the security popup (security/SecurityPopup.qml).
// Ported from DAVE-atd/Brain_Shell (src/modules/Right/Clamav.qml), AGPL-3.0 like Serpantinum.
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

    function cs(val) { return barWindow ? barWindow.cs(val) : val }

    readonly property var clam: ClamavService
    readonly property bool alert: !isPreview && (clam.unseen || clam.scanState === "infected")

    property real lengthPadding: cs(isCompact ? 10 : 12)
    implicitWidth: isVertical ? (parent ? parent.width : 0) : icon.implicitWidth + lengthPadding * 2
    implicitHeight: isVertical ? icon.implicitHeight + lengthPadding * 2 : (parent ? parent.height : 0)
    visible: isPreview || clam.available

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (!root.isPreview && Caching.serpantinumDir)
            Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "security"])
    }

    Text {
        id: icon
        anchors.centerIn: parent
        text: root.isPreview ? "󰕥"
            : !root.clam.enabled ? "󰦞"      // shield-off
            : root.alert          ? "󰻌"      // shield-alert
            : root.clam.scanning  ? "󰶚"      // shield-search
            : "󰕥"                            // shield-check
        font.family: ThemeBackend.iconFont
        font.pixelSize: root.cs(root.isCompact ? 16 : 18)
        color: root.alert ? ThemeBackend.red
             : mouse.containsMouse ? ThemeBackend.blue
             : ThemeBackend.text
        opacity: root.isPreview || root.clam.enabled ? 1 : 0.55
        Behavior on color { ColorAnimation { duration: 200 } }

        // Breathe while a system scan runs
        SequentialAnimation on scale {
            running: root.clam.scanning; loops: Animation.Infinite
            onRunningChanged: if (!running) icon.scale = 1
            NumberAnimation { to: 1.15; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutSine }
        }
    }
}
