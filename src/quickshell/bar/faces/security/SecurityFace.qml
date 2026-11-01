// Bar module "security": ClamAV shield pill. Click opens the security popup (security/SecurityPopup.qml).
// Ported from DAVE-atd/Brain_Shell (src/modules/Right/Clamav.qml), AGPL-3.0 like Serpantinum.
// Same pill as wifi/bt: accent when protection is on, red on a detection, surface0 when off.
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

    readonly property var clam: ClamavService
    readonly property bool on: isPreview || clam.enabled
    readonly property bool alert: !isPreview && (clam.unseen || clam.scanState === "infected")

    readonly property color accent: alert ? ThemeBackend.red
                                  : on ? (isCompact ? Qt.lighter(ThemeBackend.mauve, 1.08) : ThemeBackend.mauve)
                                  : (isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0)

    readonly property real pillSize: s(isCompact ? 28 : 30)
    implicitWidth: isVertical ? (parent ? parent.width : 0) : pill.width + s(isCompact ? 8 : 10)
    implicitHeight: isVertical ? pill.height + s(isCompact ? 8 : 10) : (parent ? parent.height : 0)
    visible: isPreview || clam.available

    ClickButton {
        id: pill
        anchors.centerIn: parent
        height: root.pillSize
        width: root.isVertical ? root.pillSize : implicitWidth
        cornerRadius: Math.max(0, ThemeBackend.borderRadius - root.s(2))
        horizontalPadding: root.isVertical ? 0 : root.s(root.isCompact ? 10 : 12)
        buttonIcon: root.isPreview ? "󰕥"
            : !root.clam.enabled ? "󰦞"      // shield-off
            : root.alert          ? "󰻌"      // shield-alert
            : root.clam.scanning  ? "󰶚"      // shield-search
            : "󰕥"                            // shield-check
        iconFontSize: root.s(root.isCompact ? 14 : 15)
        accentColor: root.accent
        textColor: root.on || root.alert ? ThemeBackend.base : ThemeBackend.text
        Behavior on accentColor { ColorAnimation { duration: 200 } }

        onClicked: if (!root.isPreview && Caching.serpantinumDir)
            Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "security"])

        // Breathe while a system scan runs
        SequentialAnimation on opacity {
            running: root.clam.scanning; loops: Animation.Infinite
            onRunningChanged: if (!running) pill.opacity = 1
            NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutSine }
        }
    }
}
