// Ported from DAVE-atd/Brain_Shell (src/services/TailscaleService.qml), AGPL-3.0 like Serpantinum.
pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell

// TailscaleService — polls `tailscale status --json`.
//
// Actions (up/down, exit node) need the user to be the tailscale operator:
//   sudo tailscale set --operator=$USER
// On NixOS: services.tailscale.extraSetFlags = [ "--operator=<user>" ];
// Failures are reported via notify-send with tailscale's error message.

QtObject {
    id: root

    // ── State ─────────────────────────────────────────────────────────────────
    property bool   available:    false   // tailscale CLI + daemon reachable
    property string backendState: ""      // Running | Stopped | NeedsLogin | Starting | …
    readonly property bool running: backendState === "Running"

    property string selfName: ""
    property string selfIp:   ""
    property string selfDns:  ""
    property string tailnet:  ""

    // [{ id, name, dns, ip, os, online, exitNode, exitNodeOption, lastSeen }]
    property var    peers:        []
    readonly property var exitNodes: peers.filter(function(p) { return p.exitNodeOption })
    readonly property int onlineCount: peers.filter(function(p) { return p.online }).length
    property string exitNode:     ""      // hostname of the active exit node, "" if none

    property bool   busy:         false   // an action is running
    property string busyLabel:    ""

    // Poll faster while the network popup is visible (set by tailscale/TailscalePopup.qml)
    property bool   fastPoll:     false

    // ── Public API ────────────────────────────────────────────────────────────
    function refresh() {
        if (statusProc.running) return
        statusProc.running = true
    }

    function setRunning(on) {
        _run(on ? ["tailscale", "up"] : ["tailscale", "down"],
             on ? "Connecting…" : "Disconnecting…",
             on ? "Tailscale connected" : "Tailscale disconnected")
    }

    function toggle() { setRunning(!running) }

    // ip = "" clears the exit node
    function setExitNode(ip, name) {
        _run(["tailscale", "set", "--exit-node=" + ip],
             ip ? "Switching exit node…" : "Clearing exit node…",
             ip ? "Exit node: " + name : "Exit node off")
    }

    function copy(text) {
        copyProc.command = ["wl-copy", text]
        copyProc.running = false
        copyProc.running = true
    }

    // ── Internals ─────────────────────────────────────────────────────────────
    function _run(cmd, label, doneMsg) {
        if (actionProc.running) return
        root.busy      = true
        root.busyLabel = label
        actionProc._doneMsg = doneMsg
        actionProc.command  = cmd
        actionProc.running  = true
    }

    function _notify(title, body, urgency) {
        notifyProc.command = ["notify-send", "--app-name=Tailscale",
                              "--urgency=" + urgency, "--icon=network-vpn", title, body]
        notifyProc.running = false
        notifyProc.running = true
    }

    function _parse(text) {
        var s
        try { s = JSON.parse(text) } catch (e) { root.available = false; return }

        root.available    = true
        root.backendState = s.BackendState || ""
        root.tailnet      = s.CurrentTailnet ? s.CurrentTailnet.Name : ""

        var self = s.Self || {}
        root.selfName = self.HostName || ""
        root.selfDns  = (self.DNSName || "").replace(/\.$/, "")
        root.selfIp   = (self.TailscaleIPs && self.TailscaleIPs.length) ? self.TailscaleIPs[0] : ""

        var list = []
        var exit = ""
        var peerMap = s.Peer || {}
        for (var key in peerMap) {
            var p = peerMap[key]
            var dns = (p.DNSName || "").replace(/\.$/, "")
            list.push({
                id:             p.ID,
                name:           dns ? dns.split(".")[0] : p.HostName,
                dns:            dns,
                ip:             (p.TailscaleIPs && p.TailscaleIPs.length) ? p.TailscaleIPs[0] : "",
                os:             p.OS || "",
                online:         !!p.Online,
                exitNode:       !!p.ExitNode,
                exitNodeOption: !!p.ExitNodeOption,
                lastSeen:       p.LastSeen || ""
            })
            if (p.ExitNode) exit = dns ? dns.split(".")[0] : p.HostName
        }
        // Online first, then alphabetical
        list.sort(function(a, b) {
            if (a.online !== b.online) return a.online ? -1 : 1
            return a.name.localeCompare(b.name)
        })
        root.peers    = list
        root.exitNode = exit
    }

    property var statusProc: Process {
        command: ["tailscale", "status", "--json"]
        running: false
        stdout: StdioCollector { onStreamFinished: root._parse(text) }
        onExited: function(code) { if (code !== 0 && code !== 1) root.available = false }
    }

    property var actionProc: Process {
        property string _doneMsg: ""
        running: false
        stderr: StdioCollector { id: actionErr }
        onExited: function(code) {
            root.busy      = false
            root.busyLabel = ""
            if (code === 0) {
                root._notify("Tailscale", actionProc._doneMsg, "low")
            } else {
                var err = actionErr.text.trim()
                if (err.indexOf("Access denied") >= 0 || err.indexOf("prefs write access denied") >= 0)
                    err += "\n\nRun once: sudo tailscale set --operator=$USER"
                root._notify("Tailscale failed", err, "critical")
            }
            root.refresh()
        }
    }

    property var copyProc:   Process { running: false }
    property var notifyProc: Process { running: false }

    property var pollTimer: Timer {
        interval: root.fastPoll ? 2000 : 5000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
