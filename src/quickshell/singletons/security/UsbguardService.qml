// Ported from DAVE-atd/Brain_Shell (src/services/UsbguardService.qml), AGPL-3.0 like Serpantinum.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// UsbguardService — asks before a newly plugged-in USB device may be used.
//
// Expects USBGuard with the user in IPCAllowedUsers (nixos-config modules/security/usbguard.nix).
// Follows `usbguard watch`; a device that gets blocked on insert raises a notification with
// "Allow" (this time) and "Always allow" (appends a rule to the policy). Ignoring it keeps it blocked.
// Devices that pretend to be a keyboard are flagged (BadUSB sticks do exactly that).

QtObject {
    id: root

    // Event being read: "[device] PresenceChanged: id=N" followed by " key=value" lines
    property var _ev: null

    function _line(line) {
        var head = /^\[device\] PresenceChanged: id=(\d+)/.exec(line)
        if (head) { _ev = { id: head[1] }; return }
        if (line.charAt(0) === "[") { _ev = null; return }
        var kv = /^ (\w+)=(.*)$/.exec(line)
        if (!_ev || !kv) return
        _ev[kv[1]] = kv[2]
        // device_rule is the last line of the event
        if (kv[1] === "device_rule") {
            if (_ev.event === "Insert" && _ev.target === "block") _ask(_ev.id, _ev.device_rule)
            _ev = null
        }
    }

    // USB interface classes (bInterfaceClass:SubClass:Protocol) → what the device claims to be
    function _kinds(ifaces) {
        var k = []
        function add(x) { if (k.indexOf(x) < 0) k.push(x) }
        for (var i = 0; i < ifaces.length; i++) {
            var c = ifaces[i].split(":")
            switch (c[0]) {
            case "03": add(c[2] === "01" ? "keyboard" : c[2] === "02" ? "mouse" : "input device"); break
            case "08": add("storage"); break
            case "01": add("audio"); break
            case "0e": add("camera"); break
            case "02": case "0a": add("network"); break
            case "e0": add("wireless"); break
            case "07": add("printer"); break
            case "06": add("camera/phone"); break
            case "09": add("hub"); break
            case "ff": add("vendor-specific"); break
            }
        }
        return k
    }

    function _esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    function _ask(id, rule) {
        var name = ((/ name "((?:[^"\\]|\\.)*)"/.exec(rule) || [])[1] || "").replace(/\\(.)/g, "$1")
        var vidpid = (/ id ([0-9a-f]{4}:[0-9a-f]{4})/.exec(rule) || [])[1] || "?"
        var ifm = / with-interface (\{[^}]*\}|\S+)/.exec(rule)
        var ifaces = ifm ? (ifm[1].match(/[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}/g) || []) : []
        var kinds = _kinds(ifaces)

        var title = "USB device blocked: " + (name !== "" ? name : vidpid)
        var body = _esc((kinds.length > 0 ? kinds.join(", ") : "unknown type") + "  ·  " + vidpid)
        if (kinds.indexOf("keyboard") >= 0)
            body += "<br>⚠ Acts as a keyboard: only allow it if you just plugged in a keyboard."

        // Names come from the device itself: passed as arguments, never spliced into the script.
        // The body is rendered as StyledText (escaped, <br>); the summary is plain text
        Quickshell.execDetached(["bash", "-c",
            "a=$(notify-send -u critical -a USBGuard -i drive-removable-media " +
            "  -A allow=Allow -A always='Always allow' \"$1\" \"$2\"); " +
            "case \"$a\" in " +
            "  allow)  usbguard allow-device \"$3\" ;; " +
            "  always) usbguard allow-device -p \"$3\" ;; " +
            "  *) exit 0 ;; " +
            "esac || notify-send -a USBGuard 'USBGuard' 'Could not allow the device (unplugged?)'",
            "_", title, body, id])
    }

    property Process _watchProc: Process {
        command: ["bash", "-c", "command -v usbguard >/dev/null || exit 127; exec usbguard watch -w"]
        running: true
        stdout: SplitParser { onRead: (line) => root._line(line) }
        // 127: USBGuard not installed, nothing to do. Otherwise the daemon went away: retry
        onExited: (code) => { if (code !== 127) _watchRestart.restart() }
    }
    property Timer _watchRestart: Timer { interval: 10000; onTriggered: root._watchProc.running = true }
}
