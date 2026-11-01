// Ported from DAVE-atd/Brain_Shell (src/services/VulnixService.qml), AGPL-3.0 like Serpantinum.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// VulnixService — known CVEs in the running NixOS system (vulnix), shown in the security popup.
//
// Scans the runtime closure of /run/current-system (vulnix -C), not the build-time inputs.
// vulnix matches by package name + version against the NVD, so there are false positives
// (and nixpkgs patches that don't bump the version): entries can be ignored, which writes
// their current CVEs to ~/.config/serpantinum/vulnix-whitelist.toml (new CVEs still show up).
// Runs by itself after a system switch and once a day; the result is cached.

QtObject {
    id: root

    readonly property string home:       Quickshell.env("HOME")
    readonly property string cacheDir:   (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/serpantinum"
    readonly property string resultFile: cacheDir + "/vulnix.json"
    readonly property string whitelist:  (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/serpantinum/vulnix-whitelist.toml"
    readonly property int    maxAge:     24 * 3600 * 1000

    property bool   available: false
    property bool   running:   false
    property bool   failed:    false    // last check failed (offline, NVD unreachable …)
    property real   checkedAt: 0        // ms since epoch
    property string checkedSystem: ""   // store path the result belongs to

    // [{ pname, versions: ["1.2"], score: 9.8, cves: ["CVE-…"], top: "CVE-…" }] sorted by score
    property var    packages: []
    readonly property int critical: packages.filter(p => p.score >= 9).length
    readonly property int high:     packages.filter(p => p.score >= 7 && p.score < 9).length

    function check() {
        if (running || !available) return
        running = true
        failed = false
        _checkProc.running = true
    }

    // Hide the package's current CVEs from now on
    function ignore(pname) {
        var p = packages.find(x => x.pname === pname)
        if (!p) return
        packages = packages.filter(x => x.pname !== pname)
        _ignoreProc.command = ["bash", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '\\n[\"%s\"]\\ncve = [%s]\\ncomment = \"ignored in Serpantinum %s\"\\n' \"$2\" \"$3\" \"$(date +%F)\" >> \"$1\"",
            "_", whitelist, pname, p.cves.map(c => "\"" + c + "\"").join(", ")]
        _ignoreProc.running = true
    }

    function openCve(cve) {
        Quickshell.execDetached(["xdg-open", "https://nvd.nist.gov/vuln/detail/" + cve])
    }

    function _load(text) {
        var lines = text.split("\n")
        available = lines[0] === "avail"
        var current = lines[1] || ""
        var mtime = parseInt(lines[2]) || 0
        checkedSystem = lines[3] || ""
        checkedAt = mtime * 1000
        var json = lines.slice(4).join("\n").trim()
        if (json !== "") {
            try { packages = _group(JSON.parse(json)) } catch (e) { packages = [] }
        }
        // Outdated: new system generation or older than a day
        if (available && !running && (checkedAt === 0 || current !== checkedSystem || Date.now() - checkedAt > maxAge))
            check()
    }

    // vulnix lists every output (perl, perl-env, git-fish-completions …): one row per package
    function _group(list) {
        var by = {}
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            var g = by[e.pname] || (by[e.pname] = { pname: e.pname, versions: [], score: 0, cves: [], top: "" })
            var v = String(e.version).replace(/-(env|fish-completions|bin|lib|dev|man)$/, "")
            if (g.versions.indexOf(v) < 0) g.versions.push(v)
            var scores = e.cvssv3_basescore || {}
            for (var j = 0; j < e.affected_by.length; j++) {
                var c = e.affected_by[j]
                if (g.cves.indexOf(c) < 0) g.cves.push(c)
                var s = scores[c] || 0
                if (g.top === "" || s > g.score) { g.score = s; g.top = c }
            }
        }
        return Object.values(by).sort((a, b) => b.score - a.score || b.cves.length - a.cves.length)
    }

    // ── Processes ─────────────────────────────────────────────────────────────
    property Process _readProc: Process {
        command: ["bash", "-c",
            "command -v vulnix >/dev/null && echo avail || echo no; " +
            "readlink -f /run/current-system; " +
            "stat -c %Y \"$1\" 2>/dev/null || echo 0; " +
            "cat \"$1.system\" 2>/dev/null || echo; " +
            "cat \"$1\" 2>/dev/null",
            "_", root.resultFile]
        stdout: StdioCollector { onStreamFinished: root._load(text) }
    }

    // exit 0 = nothing found, 2 = vulnerable packages, anything else = error
    property Process _checkProc: Process {
        command: ["bash", "-c",
            "mkdir -p \"$(dirname \"$1\")\" \"$(dirname \"$2\")\" && touch \"$2\"; " +
            "sys=$(readlink -f /run/current-system); " +
            "nice -n 19 vulnix -C \"$sys\" --json -w \"$2\" > \"$1.tmp\"; rc=$?; " +
            "if [ $rc -eq 0 ] || [ $rc -eq 2 ]; then mv \"$1.tmp\" \"$1\" && echo \"$sys\" > \"$1.system\"; " +
            "else rm -f \"$1.tmp\"; exit 1; fi",
            "_", root.resultFile, root.whitelist]
        onExited: (code) => {
            root.running = false
            root.failed = code !== 0
            if (code === 0) root._readProc.running = true
        }
    }

    property Process _ignoreProc: Process {}

    // Cheap: readlink + stat, the scan itself only runs when something changed
    property Timer _poll: Timer {
        interval: 10 * 60 * 1000; repeat: true; running: true
        onTriggered: if (!root._readProc.running) root._readProc.running = true
    }

    Component.onCompleted: _readProc.running = true
}
