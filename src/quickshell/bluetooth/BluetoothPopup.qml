// Bluetooth popup: Orbit Bluetooth's orbit view (vendor/orbitBluetooth, MIT, © lung595), as in
// DAVE-atd/Brain_Shell (src/popups/BluetoothTab.qml). Devices float around this machine; drag one to
// the centre to connect, pull it away to disconnect, click it for battery/volume/details.
// Background services run in OrbitHost (Shell.qml). Opened from the bar module "bt" via
// qs_manager.sh toggle bluetooth.
import QtQuick
import Quickshell
import "../"
import "../vendor/orbitBluetooth/components/scene"

Item {
    id: root
    visible: false
    focus: true

    function s(val) { return Scaler.s(val) }

    // Main.qml calls startExit(cb) before hiding the popup
    property real intro: 0
    property var exitCallback: null
    function startExit(onFinished) {
        introAnim.stop()
        exitCallback = onFinished
        exitAnim.restart()
    }
    onVisibleChanged: {
        if (visible) { forceActiveFocus(); intro = 0; introAnim.restart() }
        else { introAnim.stop(); exitAnim.stop(); intro = 0 }
    }
    NumberAnimation { id: introAnim; target: root; property: "intro"; to: 1; duration: 260; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: exitAnim
        NumberAnimation { target: root; property: "intro"; to: 0; duration: 160; easing.type: Easing.InCubic }
        ScriptAction { script: { if (root.exitCallback) { let cb = root.exitCallback; root.exitCallback = null; cb() } } }
    }

    Keys.onEscapePressed: Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close", "bluetooth"])

    NightColors { id: night }

    Item {
        anchors.fill: parent
        scale: ConvexState.active ? 1 : 0.95 + 0.05 * root.intro   // convex: Main.qml slides it out of the bar
        transformOrigin: ConvexState.origin
        opacity: ConvexState.active ? 1 : root.intro
        transform: Translate { y: ConvexState.active ? 0 : root.s(20) * (1 - root.intro) }

        Rectangle {
            anchors.fill: parent
            radius: ThemeBackend.borderRadius
            // Convex bar style: square corners on sides attached to the bar or frame
            topLeftRadius: ConvexState.tl(radius)
            topRightRadius: ConvexState.tr(radius)
            bottomLeftRadius: ConvexState.bl(radius)
            bottomRightRadius: ConvexState.br(radius)
            color: night.sky
            clip: true

            OrbitScene {
                anchors.fill: parent
                cornerRadius: ThemeBackend.borderRadius
                foldVolume: true
                // Only animate and scan while the popup is open
                active: root.visible
            }
        }
    }
}
