pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../"

// Gemeinsame Animationswerte, nach minflair (github.com/t4lentles5/minflair, GPL-3.0,
// Core/Constants.qml und die Convex-Panels): sechs Dauern, alle mit einem Faktor skaliert.
// Faktor 0 (alles sofort), wenn Hyprlands Animationen aus sind oder general.performance an ist;
// general.animationSpeed (Standard 1) macht alles schneller (>1) oder langsamer (<1).
//
// Benutzung: `duration: Motion.open; easing.type: Motion.openEasing` statt fester Zahlen.
Item {
    id: root
    visible: false

    property bool hyprAnimations: true
    readonly property real speed: {
        let g = Config.getSetting("general", {});
        let v = Number(g.animationSpeed);
        return (isFinite(v) && v > 0) ? v : 1;
    }
    readonly property real factor: (hyprAnimations && !Config.getSetting("general", {}).performance) ? 1 / Math.max(0.1, speed) : 0

    function ms(base) { return Math.round(base * factor); }

    // Stufen (minflair: animUltraFast … animExpressive)
    readonly property int ultraFast: ms(100)
    readonly property int fast: ms(150)
    readonly property int normal: ms(250)
    readonly property int slow: ms(350)
    readonly property int ultraSlow: ms(400)
    readonly property int expressive: ms(500)

    // Bedeutung → Dauer + Kurve. Öffnen gleitet lang aus, Schließen ist kurz,
    // Größenänderungen dazwischen, Hover/kleine Zustände knapp.
    readonly property int open: expressive
    readonly property int openEasing: Easing.OutQuint
    readonly property int close: normal
    readonly property int closeEasing: Easing.OutCubic
    readonly property int resize: slow
    readonly property int resizeEasing: Easing.OutQuint
    readonly property int hover: fast
    readonly property int hoverEasing: Easing.OutQuad
    // Kleine Elemente, die "aufploppen" (Badges, Punkte)
    readonly property int popEasing: Easing.OutBack

    // animations:enabled bei Start und nach jedem Hyprland-Reload lesen
    Process {
        id: animQuery
        command: ["hyprctl", "getoption", "animations:enabled", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let o = JSON.parse(text);
                    let v = o.int !== undefined ? o.int : (o.bool !== undefined ? o.bool : o.value);
                    root.hyprAnimations = !(v === 0 || v === false || v === "false");
                } catch (e) {}
            }
        }
    }
    Component.onCompleted: animQuery.running = true
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") animQuery.running = true;
        }
    }
}
