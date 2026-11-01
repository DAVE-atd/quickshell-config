// Bar module "tailscale": VPN icon. Click opens the Tailscale popup (tailscale/TailscalePopup.qml).
// Ported from DAVE-atd/Brain_Shell (src/modules/Right/Network.qml), AGPL-3.0 like Serpantinum.
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

    readonly property var ts: TailscaleService
    readonly property bool on: isPreview || ts.running

    property real lengthPadding: cs(isCompact ? 10 : 12)
    implicitWidth: isVertical ? (parent ? parent.width : 0) : icon.implicitWidth + lengthPadding * 2
    implicitHeight: isVertical ? icon.implicitHeight + lengthPadding * 2 : (parent ? parent.height : 0)
    visible: isPreview || ts.available

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: (ev) => {
            if (root.isPreview) return
            // Middle click: Tailscale on/off without the popup
            if (ev.button === Qt.MiddleButton) { if (!root.ts.busy) root.ts.toggle(); return }
            if (Caching.serpantinumDir)
                Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "tailscale"])
        }
    }

    Text {
        id: icon
        anchors.centerIn: parent
        text: "󰖂"
        font.family: ThemeBackend.iconFont
        font.pixelSize: root.cs(root.isCompact ? 16 : 18)
        // Blue while an exit node routes all traffic
        color: !root.isPreview && root.ts.exitNode !== "" ? ThemeBackend.blue
             : area.containsMouse ? ThemeBackend.blue
             : ThemeBackend.text
        opacity: root.on ? 1 : 0.45
        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        SequentialAnimation on scale {
            running: root.ts.busy; loops: Animation.Infinite
            onRunningChanged: if (!running) icon.scale = 1
            NumberAnimation { to: 1.15; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 600; easing.type: Easing.InOutSine }
        }
    }
}
