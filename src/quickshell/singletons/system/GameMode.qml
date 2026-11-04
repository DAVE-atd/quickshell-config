pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "../../"

// Game Mode: Hyprland-Animationen, Blur und Schatten aus, Energieprofil "Performance".
// Beim Ausschalten kommen die vorherigen Werte zurück. Der Zustand liegt in
// $runDir/gamemode.json, damit er einen Neustart der Shell übersteht (Hyprland behält die
// per hyprctl eval gesetzten Werte bis zum nächsten Reload).
Singleton {
    id: root

    property bool active: false
    // Werte vor dem Einschalten: { anim, blur, shadow, profile }
    property var saved: null

    readonly property string stateFile: Caching.runDir + "/gamemode.json"

    function toggle() { active ? disable() : enable() }

    function enable() {
        if (active) return;
        active = true;
        saveProc.profile = PowerProfiles.profile;
        saveProc.running = true;
    }

    function disable() {
        if (!active) return;
        active = false;
        let s = saved || { anim: true, blur: true, shadow: true, profile: PowerProfile.Balanced };
        apply(s.anim, s.blur, s.shadow);
        PowerProfiles.profile = s.profile;
        saved = null;
        Quickshell.execDetached(["rm", "-f", stateFile]);
    }

    function apply(anim, blur, shadow) {
        let lua = "hl.config({ animations = { enabled = " + !!anim + " }, decoration = { blur = { enabled = " + !!blur
            + " }, shadow = { enabled = " + !!shadow + " } } })";
        applyProc.command = ["hyprctl", "eval", lua];
        applyProc.running = true;
    }

    // Aktuelle Werte lesen und speichern, erst danach abschalten
    Process {
        id: saveProc
        property int profile: PowerProfile.Balanced
        command: ["sh", "-c", "for o in animations:enabled decoration:blur:enabled decoration:shadow:enabled; do hyprctl getoption $o -j; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                let vals = [];
                for (let line of text.split("\n")) {
                    try { let o = JSON.parse(line); vals.push(o.bool !== undefined ? !!o.bool : o.int === 1); } catch (e) {}
                }
                let s = {
                    anim: vals.length > 0 ? vals[0] : true,
                    blur: vals.length > 1 ? vals[1] : true,
                    shadow: vals.length > 2 ? vals[2] : true,
                    profile: saveProc.profile
                };
                root.saved = s;
                Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "sh", root.stateFile, JSON.stringify(s)]);
                root.apply(false, false, false);
                if (PowerProfiles.hasPerformanceProfile) PowerProfiles.profile = PowerProfile.Performance;
            }
        }
    }

    // Motion liest animations:enabled neu ein (hyprctl eval löst kein configreloaded aus)
    Process {
        id: applyProc
        onExited: Motion.refresh()
    }

    // Nach einem Shell-Neustart den gespeicherten Zustand übernehmen
    Process {
        id: loadProc
        command: ["cat", root.stateFile]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let s = JSON.parse(text);
                    root.saved = s;
                    root.active = true;
                } catch (e) {}
            }
        }
    }

    // Ein Hyprland-Reload setzt die Config-Werte zurück: Game Mode ist dann vorbei,
    // nur das Energieprofil muss noch zurück
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded" || !root.active) return;
            root.active = false;
            if (root.saved) PowerProfiles.profile = root.saved.profile;
            root.saved = null;
            Quickshell.execDetached(["rm", "-f", root.stateFile]);
        }
    }
}
