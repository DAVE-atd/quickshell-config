// Ported from DAVE-atd/Brain_Shell (src/services/ClamavService.qml), AGPL-3.0 like Serpantinum.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ClamavService — state behind the ClamAV bar widget and drop-down.
//
// Expects the NixOS side (nixos-config modules/security/clamav.nix):
//   - clamav-daemon.socket/.service + clamav-clamonacc.service watching ~/Downloads
//   - the units only start while /var/lib/clamav-toggle/disabled does not exist
//     (directory writable by the user, so the switch survives reboots)
//   - a polkit rule that lets the user start/stop those three units without a password
// Detections from the on-access scanner are read from the clamonacc journal
// ("<path>: <signature> FOUND") and announced with notify-send.
// The system scan runs clamdscan (clamscan when clamd is switched off).

QtObject {
    id: root

    readonly property string flagDir: "/var/lib/clamav-toggle"
    readonly property string offFlag: flagDir + "/disabled"
    readonly property var    scanTargets: ["/home", "/share", "/data"]

    // ── Status ────────────────────────────────────────────────────────────────
    property bool available: false      // ClamAV installed and the toggle dir exists
    property bool enabled:   true       // switch position (no off flag)
    property bool monitoring: false     // clamonacc is running
    property bool busy:      false      // switching on/off
    property string sigVersion: ""      // daily database version, e.g. "27812"
    property real   sigDate: 0          // ms since epoch of the newest database file

    // [{ time: ms, name: "Eicar-Signature", path: "/home/…", source: "Downloads" | "Scan" }]
    property var detections: []
    property bool unseen: false         // new detection since the drop-down was last opened

    // ── Scan ──────────────────────────────────────────────────────────────────
    property bool   scanning: false
    property real   scanStarted: 0
    property real   scanEnded: 0
    property var    scanFound: []       // [{ path, name }]
    property int    scanErrors: 0
    property string scanState: ""       // "", "clean", "infected", "cancelled", "error"

    function refresh() { if (!_statusProc.running) _statusProc.running = true }

    // Clicked again while switching: remembered and applied once the running switch is done
    property var _pending: null

    function setEnabled(on) {
        if (busy) { _pending = on; enabled = on; return }
        busy = true
        enabled = on
        // One unit per systemctl call: with several units systemd doesn't pass the unit name
        // to polkit, and the NixOS rule only allows these three units
        _toggleProc.command = ["bash", "-c", on
            ? "rm -f \"$1\" && systemctl start clamav-daemon.socket && systemctl start clamav-clamonacc.service"
            : "touch \"$1\" && systemctl stop clamav-clamonacc.service && systemctl stop clamav-daemon.socket && systemctl stop clamav-daemon.service",
            "_", offFlag]
        _toggleProc.running = true
    }

    function startScan() {
        if (scanning) return
        scanFound = []
        scanErrors = 0
        scanState = ""
        scanStarted = Date.now()
        scanEnded = 0
        scanning = true
        // clamdscan --fdpass: the client walks the tree and hands clamd open files, so clamd
        // (user clamav) can scan the user's home; --multiscan scans them in parallel.
        // ExcludePath from clamd.conf (btrfs snapshots) applies to clamdscan only.
        _scanProc.command = ["bash", "-c",
            "t=(); for d in \"$@\"; do [ -d \"$d\" ] && t+=(\"$d\"); done; " +
            "if systemctl is-active -q clamav-daemon.socket; then " +
            "  exec clamdscan --fdpass --multiscan --infected \"${t[@]}\"; " +
            "else " +
            "  exec clamscan --recursive --infected --exclude-dir='^/home/\\.snapshots' --exclude-dir='^/data/\\.snapshots' \"${t[@]}\"; " +
            "fi", "_"].concat(scanTargets)
        _scanProc.running = true
    }

    function cancelScan() {
        if (!scanning) return
        scanState = "cancelled"
        _scanProc.running = false   // SIGTERM
    }

    function _addDetection(path, name, source, time) {
        var list = detections.slice()
        for (var i = 0; i < list.length; i++)
            if (list[i].path === path && list[i].name === name && Math.abs(list[i].time - time) < 60000) return false
        list.unshift({ time: time, name: name, path: path, source: source })
        detections = list.slice(0, 20)
        return true
    }

    function _notify(path, name) {
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "ClamAV", "-i", "security-low",
                                 "Threat detected: " + name, path])
    }

    // "<path>: <signature> FOUND"
    function _parseFound(line) {
        var m = /^(.*): (\S+) FOUND$/.exec(line.trim())
        return m ? { path: m[1], name: m[2] } : null
    }

    // ── Processes ─────────────────────────────────────────────────────────────
    property Process _statusProc: Process {
        command: ["bash", "-c",
            "command -v clamscan >/dev/null && [ -d \"$1\" ] && echo avail; " +
            "[ -e \"$2\" ] && echo off; " +
            "systemctl is-active -q clamav-clamonacc.service && echo mon; " +
            "sigtool --info /var/lib/clamav/daily.c?d 2>/dev/null | grep '^Version:'; " +
            "stat -c %Y /var/lib/clamav/daily.c?d 2>/dev/null | sort -n | tail -1",
            "_", root.flagDir, root.offFlag]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n")
                root.available  = lines.indexOf("avail") >= 0
                root.enabled    = lines.indexOf("off") < 0
                root.monitoring = lines.indexOf("mon") >= 0
                for (var i = 0; i < lines.length; i++) {
                    // sigtool: "Version: 28170" (clamscan -V doesn't know the database dir)
                    var v = /^Version: (\d+)/.exec(lines[i])
                    if (v) root.sigVersion = v[1]
                    if (/^\d{9,}$/.test(lines[i])) root.sigDate = parseInt(lines[i]) * 1000
                }
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
                Quickshell.execDetached(["notify-send", "-a", "ClamAV", "ClamAV",
                                         "Could not switch real-time protection " + (root.enabled ? "on" : "off")])
            root.refresh()
        }
    }

    // Past detections (last 20) once, then follow the journal for new ones
    property Process _historyProc: Process {
        command: ["journalctl", "-u", "clamav-clamonacc.service", "-o", "json", "--grep", "FOUND",
                  "-n", "20", "--no-pager", "-q"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var e = JSON.parse(line)
                    var f = root._parseFound(String(e.MESSAGE || ""))
                    if (f) root._addDetection(f.path, f.name, "Downloads", parseInt(e.__REALTIME_TIMESTAMP) / 1000)
                } catch (err) {}
            }
        }
        onExited: root._watchProc.running = true
    }

    property Process _watchProc: Process {
        command: ["journalctl", "-f", "-n", "0", "-u", "clamav-clamonacc.service", "-o", "cat", "--grep", "FOUND", "-q"]
        stdout: SplitParser {
            onRead: (line) => {
                var f = root._parseFound(line)
                if (!f) return
                if (root._addDetection(f.path, f.name, "Downloads", Date.now())) {
                    root.unseen = true
                    root._notify(f.path, f.name)
                }
            }
        }
        // journalctl only exits on errors; try again later
        onExited: _watchRestart.restart()
    }
    property Timer _watchRestart: Timer { interval: 10000; onTriggered: root._watchProc.running = true }

    property Process _scanProc: Process {
        stdout: SplitParser {
            onRead: (line) => {
                var f = root._parseFound(line)
                if (f) {
                    root.scanFound = root.scanFound.concat([f])
                    root._addDetection(f.path, f.name, "Scan", Date.now())
                } else if (/(ERROR|WARNING|Permission denied|Can't)/.test(line)) {
                    root.scanErrors++
                }
            }
        }
        stderr: SplitParser { onRead: (line) => { if (line.trim() !== "") root.scanErrors++ } }
        // clamdscan/clamscan: 0 = clean, 1 = virus found, 2 = errors (unreadable files etc.)
        onExited: (code) => {
            root.scanning = false
            root.scanEnded = Date.now()
            if (root.scanState === "cancelled") return
            if (root.scanFound.length > 0) {
                root.scanState = "infected"
                root.unseen = true
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "ClamAV", "-i", "security-low",
                                         "System scan: " + root.scanFound.length + " threat" + (root.scanFound.length > 1 ? "s" : "") + " found",
                                         root.scanFound.map(f => f.name + "  " + f.path).join("\n")])
            } else {
                root.scanState = code === 0 || code === 2 ? "clean" : "error"
                Quickshell.execDetached(["notify-send", "-a", "ClamAV", "-i", "security-high",
                                         "System scan finished", "No threats found"])
            }
        }
    }

    // Cheap status poll (systemctl + stat), mostly to catch freshclam updates
    property Timer _poll: Timer { interval: 60000; repeat: true; running: true; onTriggered: root.refresh() }

    Component.onCompleted: {
        refresh()
        _historyProc.running = true
    }
}
