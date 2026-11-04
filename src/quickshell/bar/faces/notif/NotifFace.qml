// Bar module "notif": bell with an unread badge. Click opens the notification drawer
// (notifications/NotificationCenter.qml), right click toggles Mute (notifications.dnd).
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

    readonly property int unread: isPreview ? 3 : NotificationManager.unreadCount
    readonly property bool dnd: Boolean(Config.rawSettings && Config.rawSettings.notifications && Config.rawSettings.notifications.dnd)

    function toggleDnd() {
        let n = Config.getSetting("notifications", { "dnd": false });
        if (typeof n !== "object" || n === null) n = {};
        n.dnd = !root.dnd;
        Config.setSetting("notifications", n);
    }

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
        buttonIcon: root.dnd ? "󰂛" : (root.unread > 0 ? "󰂞" : "󰂚")
        iconFontSize: root.s(root.isCompact ? 14 : 15)
        accentColor: root.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
        textColor: root.dnd ? ThemeBackend.subtext0 : ThemeBackend.text
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: if (!root.isPreview && Caching.serpantinumDir)
            Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "notifications"])
        onRightClicked: if (!root.isPreview) root.toggleDnd()
    }

    // Unread badge, pops in with the count
    Rectangle {
        readonly property bool shown: root.unread > 0 && !root.dnd
        x: pill.x + pill.width - width * 0.7
        y: pill.y - height * 0.25
        height: root.s(14)
        width: Math.max(height, badgeText.implicitWidth + root.s(6))
        radius: height / 2
        color: ThemeBackend.red
        scale: shown ? 1 : 0
        visible: scale > 0
        Behavior on scale { NumberAnimation { duration: Motion.normal; easing.type: Motion.popEasing } }

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.unread > 99 ? "99+" : String(root.unread)
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: root.s(9)
            color: ThemeBackend.crust
        }
    }
}
