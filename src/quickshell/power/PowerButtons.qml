import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import "../"
import "../reusables"

// Fünf Knöpfe zum Gedrückthalten: der Knopf füllt sich von unten nach oben, voll = Aktion,
// früh loslassen lässt ihn wieder leerlaufen. Aus dem alten System-Panel, jetzt in power/PowerMenu.qml.
// Tastatur: panel.focusIndex markiert einen Knopf, holdAt()/releaseAt() wirken wie die Maus.
RowLayout {
    id: buttonsRow
    required property var panel

    function holdAt(i) { let c = buttonsRepeater.itemAt(i); if (c) { c.keyHeld = true; c.startHold(); } }
    function releaseAt(i) { let c = buttonsRepeater.itemAt(i); if (c) c.releaseHold(); }

    spacing: panel.s(5)

    Repeater {
        id: buttonsRepeater
        model: ListModel {
            ListElement { cmd: "lock"; icon: ""; weight: 1.0 }
            ListElement { cmd: "sleep"; icon: "ᶻ 𝗓 𝗓"; weight: 1.0 }
            ListElement { cmd: "hibernate"; icon: "󰤄"; weight: 1.5 }
            ListElement { cmd: "logout"; icon: "󰍃"; weight: 2.0 }
            ListElement { cmd: "reboot"; icon: "󰑓"; weight: 2.5 }
            ListElement { cmd: "poweroff"; icon: ""; weight: 3.5 }
        }

        delegate: Rectangle {
            id: actionCapsule
            required property int index
            required property string cmd
            required property string icon
            required property real weight
            readonly property bool hovered: actionMa.containsMouse || panel.focusIndex === index
            readonly property bool held: actionMa.pressed || keyHeld
            property bool keyHeld: false
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: panel.boxRadius
            clip: !capsuleGlass.active

            property bool isHibernate: cmd === "hibernate"
            property bool isDisabled: isHibernate && !panel.canHibernate
            property bool showError: false
            property int chargingSoundHandle: -1

            transform: Translate { id: shakeTranslate; x: 0 }

            color: capsuleGlass.active ? "transparent" : ThemeBackend.faded((actionCapsule.hovered && !isDisabled) ? ThemeBackend.surface1 : Qt.darker(ThemeBackend.surface0, 1.04))

            GlassFill {
                id: capsuleGlass
                anchors.fill: parent
                radius: parent.radius
                tintColor: (actionCapsule.hovered && !isDisabled) ? ThemeBackend.surface1 : ThemeBackend.surface0
                tintAmount: 0.3
                press: (actionCapsule.held && !isDisabled) ? 0.6 + 0.4 * actionCapsule.fillLevel : ((actionCapsule.hovered && !isDisabled) ? 0.25 : 0)
                pulse: Math.min(1, actionCapsule.flashOpacity * 2.5)
                Behavior on press { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            }
            Behavior on color {
                enabled: panel.visible
                ColorAnimation { duration: Motion.normal }
            }

            scale: (actionCapsule.held && !isDisabled) ? (0.98 - (0.01 * weight)) : ((actionCapsule.hovered && !isDisabled) ? 1.02 : 1.0)
            Behavior on scale {
                enabled: panel.visible
                NumberAnimation { duration: Motion.ultraSlow; easing.type: Easing.OutQuart }
            }

            property real fillLevel: 0.0
            property bool triggered: false
            property real flashOpacity: 0.0

            Connections {
                target: panel
                function onVisibleChanged() {
                    actionCapsule.keyHeld = false;
                    if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                        Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                        actionCapsule.chargingSoundHandle = -1;
                    }
                    actionCapsule.fillLevel = 0.0;
                    actionCapsule.triggered = false;
                    actionCapsule.flashOpacity = 0.0;
                    fillAnim.stop();
                    drainAnim.stop();
                }
            }

            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: shakeTranslate; property: "x"; to: -panel.s(3); duration: 50 }
                NumberAnimation { target: shakeTranslate; property: "x"; to: panel.s(3); duration: 50 }
                NumberAnimation { target: shakeTranslate; property: "x"; to: -panel.s(3); duration: 50 }
                NumberAnimation { target: shakeTranslate; property: "x"; to: panel.s(3); duration: 50 }
                NumberAnimation { target: shakeTranslate; property: "x"; to: 0; duration: 50 }
                onStarted: actionCapsule.showError = true
                onStopped: actionCapsule.showError = false
            }

            function triggerError() {
                shakeAnim.stop();
                shakeAnim.start();
            }

            FluidWave {
                id: actionWaveCanvas
                anchors.fill: parent
                visible: panel.visible && actionCapsule.fillLevel > 0.001 && !capsuleGlass.active

                property real wavePhase: 0.0
                NumberAnimation on wavePhase {
                    running: panel.visible && actionCapsule.fillLevel > 0.0 && actionCapsule.fillLevel < 1.0
                    loops: Animation.Infinite
                    from: 0; to: Math.PI * 2; duration: 800
                }

                radius: actionCapsule.radius
                fillLevel: actionCapsule.fillLevel
                waveAmp: actionCapsule.fillLevel < 0.99 ? (panel.s(10) * Math.sin(actionCapsule.fillLevel * Math.PI)) : 0
                phase: wavePhase
                vertical: 1.0
                color1: (cmd === "poweroff" || cmd === "hibernate" ? ThemeBackend.red : ThemeBackend.blue)
                color2: color1
            }

            LiquidFill {
                anchors.centerIn: parent
                width: parent.height
                height: parent.width
                rotation: -90
                radius: actionCapsule.radius
                fillLevel: actionCapsule.fillLevel
                waveAmp: actionWaveCanvas.waveAmp
                phase: actionWaveCanvas.wavePhase
                color1: Qt.lighter(actionWaveCanvas.color1, 1.1)
                color2: actionWaveCanvas.color1
                bodyAlpha: 0.4
                visible: capsuleGlass.active && actionCapsule.fillLevel > 0.001
                property real lift: (actionCapsule.fillLevel > 0.001 && actionCapsule.fillLevel < 0.999) ? 1.0 : 0.0
                Behavior on lift { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
                scale: 1.0 + 0.07 * lift
            }

            Rectangle {
                anchors.fill: parent; radius: actionCapsule.radius; color: "#ffffff"
                opacity: actionCapsule.flashOpacity
                visible: !capsuleGlass.active
                PropertyAnimation on opacity { id: cardFlashAnim; to: 0; duration: Motion.expressive; easing.type: Easing.OutExpo }
            }

            Rectangle {
                anchors.fill: parent
                color: ThemeBackend.red
                opacity: actionCapsule.showError ? 0.15 : 0.0
                radius: actionCapsule.radius
                Behavior on opacity {
                    enabled: panel.visible
                    NumberAnimation { duration: Motion.normal }
                }
                z: 4
            }

            Text {
                anchors.centerIn: parent
                font.family: ThemeBackend.iconFont
                font.pixelSize: panel.s(16)
                color: isDisabled ? ThemeBackend.surface2 : (actionCapsule.hovered ? ThemeBackend.text : ThemeBackend.subtext0)
                text: icon
                Behavior on color {
                    enabled: panel.visible
                    ColorAnimation { duration: Motion.fast }
                }
            }

            Item {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: actionCapsule.height * actionCapsule.fillLevel
                clip: true

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (actionCapsule.height / 2) - (height / 2) - (actionCapsule.height - parent.height)
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: panel.s(16)
                    color: capsuleGlass.active ? ThemeBackend.text : ThemeBackend.crust
                    text: icon
                }
            }

            MouseArea {
                id: actionMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: isDisabled ? Qt.ForbiddenCursor : (actionCapsule.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor)

                onPressed: actionCapsule.startHold()
                onReleased: actionCapsule.releaseHold()
                onCanceled: actionCapsule.releaseHold()
            }

            function startHold() {
                if (isDisabled) {
                    actionCapsule.triggerError();
                    Quickshell.execDetached([
                        "notify-send",
                        "-a", I18n.t("syspanel.actions.system_name"),
                        "-u", "normal",
                        "-i", "dialog-warning",
                        I18n.t("syspanel.actions.hibernate_error_title"),
                        I18n.t("syspanel.actions.hibernate_error_body")
                    ]);
                } else if (!actionCapsule.triggered) {
                    if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                        Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                        actionCapsule.chargingSoundHandle = -1;
                    }
                    if (typeof Sounds !== "undefined") {
                        actionCapsule.chargingSoundHandle = Sounds.playUntilStopped("reusables/fillbutton/charge_loop.wav", 0.6, false);
                    }
                    drainAnim.stop();
                    fillAnim.start();
                }
            }

            function releaseHold() {
                actionCapsule.keyHeld = false;
                if (!isDisabled && !actionCapsule.triggered && actionCapsule.fillLevel < 1.0) {
                    if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                        Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                        actionCapsule.chargingSoundHandle = -1;
                    }
                    fillAnim.stop();
                    drainAnim.start();
                }
            }

            NumberAnimation {
                id: fillAnim; target: actionCapsule; property: "fillLevel"; to: 1.0
                duration: (550 * weight) * (1.0 - actionCapsule.fillLevel); easing.type: Easing.InSine
                onFinished: {
                    actionCapsule.triggered = true;
                    actionCapsule.flashOpacity = 0.6;
                    if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                        Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                        actionCapsule.chargingSoundHandle = -1;
                    }
                    if (typeof Sounds !== "undefined") {
                        Sounds.playSfx("reusables/fillbutton/button.wav");
                    }
                    cardFlashAnim.start();
                    drainAnim.start();
                    panel.closeAnim.start();
                    exitTimer.start();
                }
            }

            NumberAnimation {
                id: drainAnim; target: actionCapsule; property: "fillLevel"; to: 0.0
                duration: 1500 * actionCapsule.fillLevel; easing.type: Easing.OutQuad
            }

            Timer {
                id: exitTimer; interval: 500
                onTriggered: {
                    if (actionCapsule.chargingSoundHandle !== -1 && typeof Sounds !== "undefined") {
                        Sounds.stopSfx(actionCapsule.chargingSoundHandle);
                        actionCapsule.chargingSoundHandle = -1;
                    }
                    // logout = exit.sh (in nixos-config gepatcht, damit es die Session sauber beendet)
                    let scriptPath = cmd === "lock" ? Caching.serpantinumDir + "/scripts/lock.sh"
                        : Caching.serpantinumDir + "/scripts/system/" + (cmd === "sleep" ? "suspend.sh" : cmd === "logout" ? "exit.sh" : cmd + ".sh");
                    Quickshell.execDetached(["bash", scriptPath]);
                    Quickshell.execDetached(["sh", "-c", "echo 'close' > " + Caching.runDir + "/widget_state"]);

                    actionCapsule.fillLevel = 0.0;
                    actionCapsule.triggered = false;
                }
            }
        }
    }
}
