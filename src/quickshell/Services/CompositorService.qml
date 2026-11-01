pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

QtObject {
    readonly property bool isNiri: false
    readonly property bool isHyprland: true
    function getFocusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0] ?? null
    }
}
