// Notification drawer: slides out of the right frame edge like the System drawer (Main.qml
// convexPlace). Header with "N new" / "All caught up", Clear and Mute (notifications.dnd) and the
// history come from reusables/display/NotificationBox.qml. Opened by the bar module "notif".
// While it is open, new notifications skip the popup (sysPanelOpen); closing marks all as read.
import QtQuick
import Quickshell
import "../"
import "../reusables"

Item {
    id: root
    visible: false
    focus: true

    function s(val) { return Scaler.s(val) }

    // Count when the drawer opened, so "N new" stays put while reading
    property int newCount: 0

    onVisibleChanged: {
        NotificationManager.sysPanelOpen = visible;
        if (visible) {
            newCount = NotificationManager.unreadCount;
            focusTimer.restart();
        } else {
            closeSequence.stop();
            NotificationManager.markAllRead();
        }
    }
    Component.onDestruction: NotificationManager.sysPanelOpen = false

    Timer {
        id: focusTimer
        interval: 50
        onTriggered: root.forceActiveFocus()
    }

    property var exitCallback: null
    function startExit(onFinished) {
        exitCallback = onFinished;
        closeSequence.restart();
    }

    SequentialAnimation {
        id: closeSequence
        // The drawer slides back in Main.qml (contentStage.tuck); wait for it
        PauseAnimation { duration: Motion.close }
        ScriptAction {
            script: {
                if (root.exitCallback) {
                    let cb = root.exitCallback;
                    root.exitCallback = null;
                    cb();
                } else {
                    Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close"]);
                }
            }
        }
    }

    Keys.onEscapePressed: (event) => {
        if (typeof masterWindow !== "undefined" && masterWindow.switchWidget) masterWindow.switchWidget("hidden", "");
        else closeSequence.restart();
        event.accepted = true;
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        // Convex: solid like the frame it hangs from
        color: ConvexState.active ? ThemeBackend.base : Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
        radius: Math.min(ThemeBackend.borderRadius, root.s(28))
        topLeftRadius: ConvexState.tl(radius)
        bottomLeftRadius: ConvexState.bl(radius)
        topRightRadius: ConvexState.tr(radius)
        bottomRightRadius: ConvexState.br(radius)
        clip: true

        WallpaperBlur {
            z: -1
            anchors.fill: parent
            topLeftRadius: parent.topLeftRadius
            topRightRadius: parent.topRightRadius
            bottomLeftRadius: parent.bottomLeftRadius
            bottomRightRadius: parent.bottomRightRadius
        }

        NotificationBox {
            anchors.fill: parent
            anchors.margins: root.s(8)
            titleSize: root.s(16)
            subtitleText: root.newCount > 0
                ? I18n.t("syspanel.notifications.count_new", { count: root.newCount })
                : I18n.t("syspanel.notifications.caught_up")
            cornerRadius: Math.min(ThemeBackend.borderRadius, root.s(20))
            cardRadius: Math.min(ThemeBackend.borderRadius, root.s(14))
            rootContext: root
        }
    }
}
