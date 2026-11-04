// Power-Menü: Schublade aus der unteren Rahmenkante (Main.qml convexPlace, "power" in
// WindowRegistry.js). Geöffnet mit Strg+Alt+Entf (nixos-config) und dem Bar-Modul "power".
// Knöpfe gedrückt halten (Maus oder Enter), Pfeiltasten wählen, Escape schließt.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

Item {
    id: root
    visible: false
    focus: true
    enabled: visible

    function s(val) { return Scaler.s(val) }

    readonly property real boxRadius: Math.min(ThemeBackend.borderRadius, root.s(16))
    property bool canHibernate: false
    // Tastaturauswahl; -1 = keine (Maus)
    property int focusIndex: -1
    readonly property int buttonCount: 6

    property alias closeAnim: closeSequence
    property var exitCallback: null
    function startExit(onFinished) {
        exitCallback = onFinished;
        closeSequence.restart();
    }

    SequentialAnimation {
        id: closeSequence
        // Main.qml schiebt die Schublade zurück; darauf warten
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

    onVisibleChanged: {
        if (visible) {
            focusIndex = -1;
            hibernateCheck.running = true;
            forceActiveFocus();
        } else {
            closeSequence.stop();
        }
    }

    Process {
        id: hibernateCheck
        command: ["bash", Caching.serpantinumDir + "/scripts/system/can_hibernate.sh"]
        stdout: StdioCollector {
            onStreamFinished: root.canHibernate = (this.text.trim() === "yes")
        }
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            if (typeof masterWindow !== "undefined" && masterWindow.switchWidget) masterWindow.switchWidget("hidden", "");
            else closeSequence.restart();
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
            focusIndex = focusIndex <= 0 ? buttonCount - 1 : focusIndex - 1;
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab) {
            focusIndex = (focusIndex + 1) % buttonCount;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && !event.isAutoRepeat) {
            if (focusIndex < 0) focusIndex = 0;
            buttons.holdAt(focusIndex);
        } else {
            return;
        }
        event.accepted = true;
    }
    Keys.onReleased: (event) => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && !event.isAutoRepeat && focusIndex >= 0) {
            buttons.releaseAt(focusIndex);
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        // Convex: deckend wie der Rahmen, an dem es hängt
        color: ConvexState.active ? ThemeBackend.base : Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
        radius: Math.min(ThemeBackend.borderRadius, root.s(22))
        // Convex: an der Rahmenkante eckig
        topLeftRadius: ConvexState.tl(radius)
        topRightRadius: ConvexState.tr(radius)
        bottomLeftRadius: ConvexState.bl(radius)
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

        PowerButtons {
            id: buttons
            panel: root
            anchors.fill: parent
            anchors.margins: root.s(8)
        }
    }
}
