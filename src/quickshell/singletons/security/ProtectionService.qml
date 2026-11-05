pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ProtectionService — on/off switches for USBGuard and OpenSnitch in the security popup
// (security/SecurityPopup.qml).

QtObject {
    id: svc

    // Switching on: devices plugged in while it was off stay allowed (the unit's ExecStartPre
    // adds them to the rules when it finds this marker). Switching off: the unit's ExecStopPost
    // gives new devices the kernel default again (allowed), see modules/security/usbguard.nix
    property ProtectionToggle usbguard: ProtectionToggle {
        name: "usbguard"
        unit: "usbguard.service"
        beforeOn: "touch \"$1/reenabled\""
    }

    // The tray UI only makes sense with the daemon running
    property ProtectionToggle opensnitch: ProtectionToggle {
        name: "opensnitch"
        unit: "opensnitchd.service"
        afterOn: "systemctl --user start opensnitch-ui.service"
        afterOff: "systemctl --user stop opensnitch-ui.service"
    }

    readonly property bool available: usbguard.available || opensnitch.available

    function refresh() { usbguard.refresh(); opensnitch.refresh() }

    // ── One switch ────────────────────────────────────────────────────────────
    // One on/off switch in the security popup (USBGuard, OpenSnitch; ClamAV has its own service).
    //
    // Expects the NixOS side (nixos-config modules/security/_toggle.nix):
    //   - /var/lib/<name>-toggle, writable by the user; the unit only starts while
    //     <dir>/disabled does not exist, so the switch survives reboots
    //   - a polkit rule that lets the user start/stop the unit without a password
    // available = false (row hidden) when the module isn't enabled on this host.
    component ProtectionToggle: QtObject {
        id: root

        required property string name       // "usbguard" → /var/lib/usbguard-toggle
        required property string unit       // "usbguard.service"
        // Extra bash run as the user ($1 = toggle dir), around starting/stopping the unit
        property string beforeOn: ""
        property string afterOn: ""
        property string afterOff: ""

        readonly property string dir: "/var/lib/" + name + "-toggle"
        readonly property string flag: dir + "/disabled"

        property bool available: false
        property bool enabled: true         // switch position (no off flag)
        property bool active: false         // unit is running
        property bool busy: false

        function refresh() { if (!_statusProc.running) _statusProc.running = true }

        // Clicked again while switching: remembered and applied once the running switch is done
        property var _pending: null

        function setEnabled(on) {
            if (busy) { _pending = on; enabled = on; return }
            busy = true
            enabled = on
            var pre = beforeOn !== "" ? beforeOn + " && " : ""
            _toggleProc.command = ["bash", "-c", on
                ? pre + "rm -f \"$1/disabled\" && systemctl start \"$2\"" + (afterOn !== "" ? "; " + afterOn : "")
                : "touch \"$1/disabled\" && systemctl stop \"$2\"" + (afterOff !== "" ? "; " + afterOff : ""),
                "_", dir, unit]
            _toggleProc.running = true
        }

        property Process _statusProc: Process {
            command: ["bash", "-c",
                "[ -d \"$1\" ] && echo avail; [ -e \"$1/disabled\" ] && echo off; " +
                "systemctl is-active -q \"$2\" && echo active",
                "_", root.dir, root.unit]
            stdout: StdioCollector {
                onStreamFinished: {
                    var lines = text.split("\n")
                    root.available = lines.indexOf("avail") >= 0
                    root.enabled   = lines.indexOf("off") < 0
                    root.active    = lines.indexOf("active") >= 0
                }
            }
        }

        property Process _toggleProc: Process {
            onExited: (code) => {
                root.busy = false
                if (root._pending !== null) {
                    var next = root._pending
                    root._pending = null
                    root.setEnabled(next)
                    return
                }
                if (code !== 0)
                    Quickshell.execDetached(["notify-send", "-a", "Security", "Security",
                                             "Could not switch " + root.name + " " + (root.enabled ? "on" : "off")])
                root.refresh()
            }
        }

        property Timer _poll: Timer { interval: 60000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.refresh() }
    }
}
