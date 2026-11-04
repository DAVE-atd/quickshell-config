// Bar module "tailscale": VPN pill. Click opens the Tailscale popup (tailscale/TailscalePopup.qml),
// right click switches Tailscale on/off without it.
// Ported from DAVE-atd/Brain_Shell (src/modules/Right/Network.qml), AGPL-3.0 like Serpantinum.
// Same pill as wifi/bt: accent while connected, surface0 when off.
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

    readonly property var ts: TailscaleService
    readonly property bool on: isPreview || ts.running

    readonly property real pillSize: s(isCompact ? 28 : 30)
    implicitWidth: isVertical ? (parent ? parent.width : 0) : pill.width + s(isCompact ? 8 : 10)
    implicitHeight: isVertical ? pill.height + s(isCompact ? 8 : 10) : (parent ? parent.height : 0)
    // BarModule gives a hidden face no width
    readonly property bool isFaceVisible: isPreview || ts.available
    visible: isFaceVisible

    ClickButton {
        id: pill
        anchors.centerIn: parent
        height: root.pillSize
        width: root.isVertical ? root.pillSize : implicitWidth
        cornerRadius: Math.max(0, ThemeBackend.borderRadius - root.s(2))
        horizontalPadding: root.isVertical ? 0 : root.s(root.isCompact ? 10 : 12)
        // Globe while an exit node routes all traffic
        buttonIcon: !root.isPreview && root.ts.exitNode !== "" ? "󰖟" : "󰖂"
        iconFontSize: root.s(root.isCompact ? 14 : 15)
        accentColor: root.on ? (root.isCompact ? Qt.lighter(ThemeBackend.mauve, 1.08) : ThemeBackend.mauve)
                             : (root.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0)
        textColor: root.on ? ThemeBackend.base : ThemeBackend.text
        Behavior on accentColor { ColorAnimation { duration: 200 } }
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: if (!root.isPreview && Caching.serpantinumDir)
            Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "tailscale"])
        onRightClicked: if (!root.isPreview && !root.ts.busy) root.ts.toggle()

        // Pulse while tailscale up/down runs
        SequentialAnimation on opacity {
            running: root.ts.busy; loops: Animation.Infinite
            onRunningChanged: if (!running) pill.opacity = 1
            NumberAnimation { to: 0.55; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 600; easing.type: Easing.InOutSine }
        }
    }
}
