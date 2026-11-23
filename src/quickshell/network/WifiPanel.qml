// Wi-Fi panel: hangs from its bar section like the other dropdowns (Main.qml convexPlace, at least as
// wide as the section; height follows the content via drawerHeight).
// Top: three tiles (Wi-Fi, Hotspot, Airplane mode). Below a card for the connected network (link rates
// down/up, band, channel, IP), then the nearby networks in one card (secured networks unfold a password
// field), at the bottom "Other network…" (hidden SSID, inline form) and "Settings" (nmtui in kitty).
// Data comes from Quickshell.Networking (NetworkManager); link details from iw, hotspot via nmcli,
// airplane mode via rfkill. Opened by the bar face "wifi" (qs_manager.sh toggle network).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../"
import "../reusables"

Item {
    id: root
    visible: false
    focus: true

    function s(val) { return Scaler.s(val) }

    readonly property color accent: ThemeBackend.sapphire
    readonly property color dim: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.55)
    readonly property color faint: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)
    readonly property color card: Qt.alpha(ThemeBackend.surface0, 0.55)
    readonly property color cardHover: Qt.alpha(ThemeBackend.surface1, 0.65)
    // Connected card: accent sunk into the background
    readonly property color heroFill: Qt.tint(ThemeBackend.base, Qt.alpha(accent, 0.38))
    // Text on accent fills: dark on a light accent, light on a dark one
    readonly property real accentLum: 0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b
    readonly property color accentInk: accentLum > 0.55 ? ThemeBackend.base : "#ffffff"
    readonly property real cardRadius: Math.min(ThemeBackend.borderRadius, s(18))

    // ── Layout ────────────────────────────────────────────────────────────────
    readonly property real pad: s(14)
    readonly property real gap: s(10)
    readonly property real tileH: s(68)
    readonly property real heroH: s(92)
    readonly property real rowH: s(52)
    readonly property real pwH: s(48)
    readonly property real btnH: s(38)
    readonly property real otherH: s(96)
    readonly property int maxRows: 5
    readonly property bool showList: wifiOn && !hotspotOn
    readonly property real listH: netModel.count === 0 ? s(48)
        : Math.min(netModel.count, maxRows) * rowH + (pwFor !== "" ? pwH : 0) + s(12)
    // Main.qml sizes the popup to this (binding, never written by Main)
    readonly property real drawerHeight: pad * 2 + tileH + gap + heroH
        + (showList ? gap + listH : 0)
        + (otherOpen ? gap + otherH : 0)
        + gap + btnH

    // ── Intro (non-convex only; convex: Main.qml grows it out of the bar) ─────
    property real intro: 0
    property var exitCallback: null
    function startExit(onFinished) {
        introAnim.stop();
        exitCallback = onFinished;
        exitAnim.restart();
    }
    NumberAnimation { id: introAnim; target: root; property: "intro"; to: 1; duration: Motion.open; easing.type: Motion.openEasing }
    SequentialAnimation {
        id: exitAnim
        NumberAnimation { target: root; property: "intro"; to: 0; duration: Motion.close; easing.type: Motion.closeEasing }
        ScriptAction { script: { if (root.exitCallback) { let cb = root.exitCallback; root.exitCallback = null; cb(); } } }
    }

    onVisibleChanged: {
        if (visible) {
            pwFor = ""; failName = ""; hoverName = ""; otherOpen = false;
            forceActiveFocus();
            intro = 0; introAnim.restart();
            rebuild();
            fetchLink();
            fetchRfkill();
            fetchHotspot();
            if (Networking.canCheckConnectivity) Networking.checkConnectivity();
        } else {
            introAnim.stop(); exitAnim.stop(); intro = 0;
        }
        updateScan();
    }

    Keys.onEscapePressed: (event) => {
        if (pwFor !== "") pwFor = "";
        else if (otherOpen) otherOpen = false;
        else if (typeof masterWindow !== "undefined" && masterWindow.switchWidget) masterWindow.switchWidget("hidden", "");
        else Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }

    // ── Devices ───────────────────────────────────────────────────────────────
    function deviceOf(type) {
        let d = Networking.devices ? Networking.devices.values : [];
        for (let i = 0; i < d.length; i++) if (d[i] && d[i].type === type) return d[i];
        return null;
    }
    // No backend = NetworkManager was not on D-Bus when the shell started (Quickshell does not retry)
    readonly property bool noBackend: Networking.backend === NetworkBackendType.None
    readonly property var wifiDevice: deviceOf(DeviceType.Wifi)
    readonly property var wiredDevice: deviceOf(DeviceType.Wired)
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property bool wiredUp: !!wiredDevice && wiredDevice.connected
    readonly property bool hotspotOn: !!wifiDevice && wifiDevice.mode === WifiDeviceMode.AccessPoint

    function updateScan() {
        if (wifiDevice) wifiDevice.scannerEnabled = visible && wifiOn && !hotspotOn;
    }
    onWifiDeviceChanged: { updateScan(); rebuild(); }
    onWifiOnChanged: { updateScan(); rebuild(); fetchRfkill(); }
    onHotspotOnChanged: { updateScan(); fetchHotspot(); }

    // ── Networks ──────────────────────────────────────────────────────────────
    // name → WifiNetwork (strongest access point per SSID)
    property var netRefs: ({})
    // Connected network for the hero: { name, strength, secured, secLabel } or null
    property var current: null
    property string hoverName: ""   // row under the mouse
    property string pwFor: ""       // network whose password field is open
    property string connectingName: ""
    property string failName: ""
    property string failText: ""
    // Don't reorder rows under the mouse or while typing a password
    readonly property bool listHold: hoverName !== "" || pwFor !== ""
    onListHoldChanged: if (!listHold) rebuild()

    ListModel { id: netModel }

    function secLabel(sec) {
        switch (sec) {
            case WifiSecurityType.Wpa3SuiteB192:
            case WifiSecurityType.Sae:      return "WPA3";
            case WifiSecurityType.Wpa2Eap:  return "WPA2 Enterprise";
            case WifiSecurityType.Wpa2Psk:  return "WPA2";
            case WifiSecurityType.WpaEap:   return "WPA Enterprise";
            case WifiSecurityType.WpaPsk:   return "WPA";
            case WifiSecurityType.StaticWep:
            case WifiSecurityType.DynamicWep: return "WEP";
            case WifiSecurityType.Leap:     return "LEAP";
            case WifiSecurityType.Owe:      return "OWE";
            case WifiSecurityType.Open:     return "Open";
            default:                        return "";
        }
    }
    function isBusy(net) {
        return !!net && (net.stateChanging || net.state === ConnectionState.Connecting);
    }

    function rebuild() {
        let nets = (wifiOn && wifiDevice && wifiDevice.networks) ? wifiDevice.networks.values : [];
        let best = {};
        let cur = null;
        for (let i = 0; i < nets.length; i++) {
            let n = nets[i];
            if (!n || !n.name) continue;
            let e = {
                name: n.name,
                strength: Math.max(0, Math.min(1, n.signalStrength || 0)),
                secured: n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe,
                secLabel: secLabel(n.security),
                known: !!n.known,
                busy: isBusy(n)
            };
            if (n.connected) {
                cur = e;
                best[n.name] = { e: e, net: n, connected: true };
                continue;
            }
            let prev = best[n.name];
            if (!prev || (!prev.connected && e.strength > prev.e.strength)) best[n.name] = { e: e, net: n, connected: false };
        }
        let refs = {};
        let list = [];
        for (let k in best) {
            refs[k] = best[k].net;
            if (!best[k].connected) list.push(best[k].e);
        }
        list.sort((a, b) => (a.known !== b.known) ? (a.known ? -1 : 1) : (b.strength - a.strength));
        netRefs = refs;
        if (JSON.stringify(cur) !== JSON.stringify(current)) current = cur;
        if (cur && cur.name === connectingName) { connectingName = ""; Sounds.playSfx("network/connect.wav"); }
        if (!listHold) syncModel(list);
        else for (let i = 0; i < netModel.count; i++) {
            // Keep the order, only refresh what is shown
            let m = netModel.get(i);
            for (let j = 0; j < list.length; j++) if (list[j].name === m.name) { netModel.set(i, list[j]); break; }
        }
    }

    // Update in place so rows keep their hover state and slide (Column move transition)
    function syncModel(arr) {
        for (let i = 0; i < arr.length; i++) {
            let j = -1;
            for (let k = i; k < netModel.count; k++) if (netModel.get(k).name === arr[i].name) { j = k; break; }
            if (j < 0) netModel.insert(i, arr[i]);
            else {
                if (j !== i) netModel.move(j, i, 1);
                netModel.set(i, arr[i]);
            }
        }
        while (netModel.count > arr.length) netModel.remove(netModel.count - 1);
    }

    Timer { id: rebuildTimer; interval: 80; onTriggered: root.rebuild() }
    function queueRebuild() { if (visible) rebuildTimer.restart(); }

    Repeater {
        model: (root.visible && root.wifiDevice) ? root.wifiDevice.networks : null
        delegate: Item {
            required property var modelData
            Component.onCompleted: root.queueRebuild()
            Component.onDestruction: root.queueRebuild()
            Connections {
                target: modelData
                ignoreUnknownSignals: true
                function onSignalStrengthChanged() { root.queueRebuild(); }
                function onStateChanged() { root.queueRebuild(); }
                function onStateChangingChanged() { root.queueRebuild(); }
                function onConnectedChanged() { root.queueRebuild(); root.fetchLink(); }
                function onKnownChanged() { root.queueRebuild(); }
                function onConnectionFailed(reason) { root.onFailed(modelData, reason); }
            }
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────────
    function entryOf(name) {
        for (let i = 0; i < netModel.count; i++) if (netModel.get(i).name === name) return netModel.get(i);
        return null;
    }
    function activate(name) {
        let net = netRefs[name];
        if (!net || net.connected) return;
        let e = entryOf(name);
        if (e && e.secured && !e.known) {
            pwFor = (pwFor === name) ? "" : name;
            failName = "";
            return;
        }
        connectTo(name, "");
    }
    function connectTo(name, psk) {
        let net = netRefs[name];
        if (!net) return;
        failName = "";
        pwFor = "";
        connectingName = name;
        connectTimeout.restart();
        if (psk !== "") net.connectWithPsk(psk);
        else net.connect();
    }
    function onFailed(net, reason) {
        let name = net ? net.name : "";
        connectingName = "";
        failName = name;
        failText = reason === ConnectionFailReason.NoSecrets ? "Wrong password"
                 : reason === ConnectionFailReason.WifiAuthTimeout ? "Timed out"
                 : reason === ConnectionFailReason.WifiNetworkLost ? "Network lost"
                 : "Couldn't connect";
        failClear.restart();
        Sounds.playSfx("network/error.wav");
        // Secured network rejected the (saved) secret: ask for it
        let e = entryOf(name);
        if (reason === ConnectionFailReason.NoSecrets && e && e.secured) pwFor = name;
        queueRebuild();
    }
    Timer { id: failClear; interval: 4000; onTriggered: root.failName = "" }
    Timer { id: connectTimeout; interval: 30000; onTriggered: root.connectingName = "" }

    // ── Link details: IP, rates and frequency of the Wi-Fi interface ─────────
    property string ip: ""
    property string band: ""
    property int channel: 0
    property string rxRate: ""
    property string txRate: ""
    function fetchLink() {
        if (visible && wifiDevice && wifiDevice.name && !linkProc.running) linkProc.running = true;
    }
    function rate(v) {
        let n = parseFloat(v);
        return isNaN(n) ? "" : Math.round(n) + " Mbit/s";
    }
    Process {
        id: linkProc
        command: ["sh", "-c", "ip -4 -o addr show dev \"$1\" | awk '{print $4}' | cut -d/ -f1 | head -n1; "
                            + "iw dev \"$1\" link 2>/dev/null | awk '/freq:/{f=$2} /rx bitrate:/{r=$3} /tx bitrate:/{t=$3} END{print f; print r; print t}'",
                  "sh", root.wifiDevice ? root.wifiDevice.name : ""]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = this.text.split("\n");
                root.ip = (l[0] || "").trim();
                let f = parseFloat(l[1] || "");
                root.band = isNaN(f) ? "" : (f < 3000 ? "2.4 GHz" : (f < 5925 ? "5 GHz" : "6 GHz"));
                root.channel = isNaN(f) ? 0
                    : f === 2484 ? 14
                    : f < 3000 ? Math.round((f - 2407) / 5)
                    : f < 5925 ? Math.round((f - 5000) / 5)
                    : Math.round((f - 5950) / 5);
                root.rxRate = root.rate(l[2] || "");
                root.txRate = root.rate(l[3] || "");
            }
        }
    }
    Timer { interval: 5000; repeat: true; running: root.visible && root.current !== null; onTriggered: root.fetchLink() }
    onCurrentChanged: { ip = ""; band = ""; channel = 0; rxRate = ""; txRate = ""; fetchLink(); }

    // ── Airplane mode: every radio soft-blocked (rfkill) ─────────────────────
    property bool airplane: false
    function fetchRfkill() { if (!rfkillProc.running) rfkillProc.running = true; }
    Process {
        id: rfkillProc
        command: ["sh", "-c", "LC_ALL=C rfkill -n -o SOFT"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = this.text.split("\n").filter(x => x.trim() !== "");
                root.airplane = l.length > 0 && l.every(x => x.trim() === "blocked");
            }
        }
    }
    Process {
        id: rfkillSet
        onExited: root.fetchRfkill()
    }
    function toggleAirplane() {
        rfkillSet.command = ["rfkill", airplane ? "unblock" : "block", "all"];
        rfkillSet.running = true;
        airplane = !airplane;
    }

    // ── Hotspot (nmcli creates/reuses the connection "Hotspot") ──────────────
    property string hotspotSsid: ""
    property string hotspotPsk: ""
    property bool hotspotBusy: false
    function fetchHotspot() {
        if (hotspotOn && !hotspotInfo.running) hotspotInfo.running = true;
    }
    Process {
        id: hotspotInfo
        command: ["nmcli", "-s", "-g", "802-11-wireless.ssid,802-11-wireless-security.psk", "connection", "show", "Hotspot"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = this.text.split("\n");
                root.hotspotSsid = (l[0] || "").trim();
                root.hotspotPsk = (l[1] || "").trim();
            }
        }
    }
    Process {
        id: hotspotSet
        onExited: (code) => {
            root.hotspotBusy = false;
            if (code !== 0) Sounds.playSfx("network/error.wav");
            root.fetchHotspot();
        }
    }
    function toggleHotspot() {
        if (!wifiDevice || hotspotBusy) return;
        hotspotBusy = true;
        hotspotSet.command = hotspotOn
            ? ["nmcli", "connection", "down", "Hotspot"]
            : ["nmcli", "device", "wifi", "hotspot", "ifname", wifiDevice.name, "con-name", "Hotspot"];
        hotspotSet.running = true;
    }

    // ── Other network: hidden SSID ────────────────────────────────────────────
    property bool otherOpen: false
    property bool otherBusy: false
    property string otherError: ""
    Process {
        id: otherProc
        onExited: (code) => {
            root.otherBusy = false;
            if (code === 0) { root.otherOpen = false; Sounds.playSfx("network/connect.wav"); }
            else { root.otherError = "Couldn't connect"; Sounds.playSfx("network/error.wav"); }
        }
    }
    function connectHidden(ssid, psk) {
        if (ssid === "" || otherBusy) return;
        otherBusy = true;
        otherError = "";
        let cmd = ["nmcli", "device", "wifi", "connect", ssid];
        if (psk !== "") cmd.push("password", psk);
        cmd.push("hidden", "yes");
        otherProc.command = cmd;
        otherProc.running = true;
    }

    function sigIcon(strength, secured) {
        if (strength > 0.75) return secured ? "󰤪" : "󰤨";
        if (strength > 0.5)  return secured ? "󰤧" : "󰤥";
        if (strength > 0.25) return secured ? "󰤤" : "󰤢";
        return secured ? "󰤡" : "󰤟";
    }

    // ── Panel ─────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        scale: ConvexState.active ? 1 : 0.95 + 0.05 * root.intro
        transformOrigin: ConvexState.origin
        opacity: ConvexState.active ? 1 : root.intro
        transform: Translate { y: ConvexState.active ? 0 : root.s(20) * (1 - root.intro) }

        Rectangle {
            anchors.fill: parent
            radius: Math.min(ThemeBackend.borderRadius, root.s(28))
            topLeftRadius: ConvexState.tl(radius)
            topRightRadius: ConvexState.tr(radius)
            bottomLeftRadius: ConvexState.bl(radius)
            bottomRightRadius: ConvexState.br(radius)
            // Convex: solid like the bar it grows out of
            color: ConvexState.active ? ThemeBackend.base : Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
            clip: true

            WallpaperBlur {
                z: -1
                anchors.fill: parent
                topLeftRadius: parent.topLeftRadius
                topRightRadius: parent.topRightRadius
                bottomLeftRadius: parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius
            }

            Column {
                id: body
                anchors { fill: parent; margins: root.pad }
                spacing: root.gap

                // ── Tiles ─────────────────────────────────────────────────────
                Row {
                    id: tiles
                    width: parent.width
                    spacing: root.s(8)
                    readonly property real tileW: (width - spacing * 2) / 3
                    Tile {
                        width: tiles.tileW
                        icon: root.wifiOn ? "󰖩" : "󰖪"; label: "Wi-Fi"
                        active: root.wifiOn
                        enabled: !!root.wifiDevice
                        onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                    }
                    Tile {
                        width: tiles.tileW
                        icon: "󰀂"; label: "Hotspot"
                        active: root.hotspotOn
                        busy: root.hotspotBusy
                        enabled: !!root.wifiDevice && root.wifiOn
                        onClicked: root.toggleHotspot()
                    }
                    Tile {
                        width: tiles.tileW
                        icon: "󰀝"; label: "Airplane mode"
                        active: root.airplane
                        onClicked: root.toggleAirplane()
                    }
                }

                // ── Hero: connected network / state ───────────────────────────
                Rectangle {
                    id: hero
                    width: parent.width; height: root.heroH
                    radius: root.cardRadius
                    readonly property bool linked: root.wifiOn && (root.current !== null || root.hotspotOn)
                    color: linked ? root.heroFill : root.card
                    border.color: linked ? Qt.alpha(root.accent, 0.25) : root.faint
                    Behavior on color { ColorAnimation { duration: Motion.normal } }

                    Column {
                        anchors {
                            left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                            leftMargin: root.s(18); rightMargin: root.s(14)
                        }
                        spacing: root.s(6)

                        // Name + status pill
                        Item {
                            width: parent.width; height: root.s(26)
                            Text {
                                anchors { left: parent.left; right: pill.left; rightMargin: root.s(10); verticalCenter: parent.verticalCenter }
                                text: root.noBackend ? "Network unavailable"
                                    : !root.wifiDevice ? "No Wi-Fi adapter"
                                    : !root.wifiOn ? (root.airplane ? "Airplane mode" : "Wi-Fi is off")
                                    : root.hotspotOn ? (root.hotspotSsid || "Hotspot")
                                    : root.current ? root.current.name
                                    : root.connectingName !== "" ? root.connectingName
                                    : "Not connected"
                                elide: Text.ElideRight
                                font.pixelSize: root.s(18); font.weight: Font.Bold
                                color: hero.linked ? ThemeBackend.text : Qt.alpha(ThemeBackend.text, 0.8)
                            }
                            Pill {
                                id: pill
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                visible: hero.linked
                                readonly property bool portal: !root.hotspotOn && Networking.connectivity === NetworkConnectivity.Portal
                                text: hovered ? (portal ? "Sign in" : root.hotspotOn ? "Stop" : "Disconnect")
                                    : root.hotspotOn ? "Hotspot"
                                    : portal ? "Sign-in required"
                                    : Networking.connectivity === NetworkConnectivity.Limited ? "Limited"
                                    : "Connected"
                                tint: hovered && !portal ? ThemeBackend.red : portal ? ThemeBackend.yellow : root.accent
                                onClicked: {
                                    if (portal) Quickshell.execDetached(["xdg-open", "http://nmcheck.gnome.org/check_network_status.txt"]);
                                    else if (root.hotspotOn) root.toggleHotspot();
                                    else { let n = root.current ? root.netRefs[root.current.name] : null; if (n) n.disconnect(); }
                                }
                            }
                        }

                        // Rates · band · channel
                        Text {
                            width: parent.width
                            visible: text !== ""
                            elide: Text.ElideRight
                            font.pixelSize: root.s(12)
                            color: hero.linked ? Qt.alpha(ThemeBackend.text, 0.85) : root.dim
                            text: {
                                if (root.noBackend) return "NetworkManager was not reachable when the shell started.";
                                if (!root.wifiDevice) return root.wiredUp ? "Ethernet connected" : "";
                                if (!root.wifiOn) return "Turn it on with the Wi-Fi tile.";
                                if (root.hotspotOn) return root.hotspotPsk !== "" ? "Password  " + root.hotspotPsk : "Sharing this connection";
                                if (!root.current) return root.connectingName !== "" ? "Connecting…"
                                    : root.wiredUp ? "Ethernet connected" : "Pick a network below.";
                                let a = [];
                                if (root.rxRate !== "") a.push("↓ " + root.rxRate);
                                if (root.txRate !== "") a.push("↑ " + root.txRate);
                                let b = [root.band, root.channel > 0 ? "Channel " + root.channel : ""].filter(x => x !== "").join(" · ");
                                return a.join("   ") + (a.length && b ? "   " : "") + b;
                            }
                        }

                        // IP (click copies) / restart hint
                        Text {
                            id: ipText
                            visible: text !== ""
                            property bool copied: false
                            text: root.noBackend ? "Restart the shell: systemctl --user restart serpantinum"
                                : hero.linked && !root.hotspotOn && root.ip !== "" ? (copied ? "Copied" : root.ip)
                                : ""
                            font.pixelSize: root.s(11)
                            font.family: root.noBackend ? Qt.application.font.family : "JetBrains Mono"
                            color: ipH.hovered && !root.noBackend ? ThemeBackend.text : root.dim
                            Timer { id: copiedT; interval: 1200; onTriggered: ipText.copied = false }
                            HoverHandler { id: ipH; cursorShape: root.noBackend ? Qt.ArrowCursor : Qt.PointingHandCursor }
                            TapHandler {
                                enabled: !root.noBackend
                                onTapped: { Quickshell.execDetached(["wl-copy", root.ip]); ipText.copied = true; copiedT.restart(); }
                            }
                        }
                    }

                    // Pulse while connecting
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"; border.color: root.accent; border.width: root.s(2)
                        visible: root.connectingName !== ""
                        SequentialAnimation on opacity {
                            running: root.connectingName !== "" && root.visible; loops: Animation.Infinite
                            NumberAnimation { from: 0.15; to: 0.8; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.8; to: 0.15; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }
                }

                // ── Network list ──────────────────────────────────────────────
                Rectangle {
                    id: listCard
                    width: parent.width; height: root.listH
                    visible: root.showList
                    radius: root.cardRadius
                    color: root.card
                    border.color: root.faint

                    Text {
                        anchors.centerIn: parent
                        visible: netModel.count === 0
                        text: "Looking for networks…"; font.pixelSize: root.s(12); color: root.dim
                    }

                    Flickable {
                        id: flick
                        anchors { fill: parent; margins: root.s(6) }
                        contentHeight: rows.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: rows
                            width: flick.width
                            move: Transition { NumberAnimation { properties: "y"; duration: Motion.resize; easing.type: Motion.resizeEasing } }
                            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.normal } }
                            Repeater {
                                model: netModel
                                delegate: NetRow { width: rows.width }
                            }
                        }
                    }
                }

                // ── Other network (hidden SSID) ───────────────────────────────
                Rectangle {
                    id: other
                    width: parent.width; height: root.otherH
                    visible: root.otherOpen
                    radius: root.cardRadius
                    color: root.card
                    border.color: root.faint

                    onVisibleChanged: if (visible) { ssidIn.text = ""; otherPw.text = ""; root.otherError = ""; ssidIn.forceActiveFocus(); }

                    Column {
                        anchors { fill: parent; margins: root.s(10) }
                        spacing: root.s(8)
                        Field {
                            width: parent.width
                            TextInput {
                                id: ssidIn
                                anchors { fill: parent; leftMargin: root.s(14); rightMargin: root.s(14) }
                                verticalAlignment: TextInput.AlignVCenter
                                color: ThemeBackend.text; selectionColor: Qt.alpha(root.accent, 0.4)
                                font.pixelSize: root.s(12); clip: true
                                KeyNavigation.tab: otherPw
                                Keys.onReturnPressed: otherPw.forceActiveFocus()
                                Keys.onEscapePressed: (event) => { root.otherOpen = false; root.forceActiveFocus(); event.accepted = true; }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: ssidIn.text === ""
                                    text: root.otherError !== "" ? root.otherError : "Network name (SSID)"
                                    font.pixelSize: root.s(11); color: root.otherError !== "" ? ThemeBackend.red : root.dim
                                }
                            }
                        }
                        Item {
                            width: parent.width; height: root.s(32)
                            Field {
                                anchors { left: parent.left; right: otherGo.left; rightMargin: root.s(8) }
                                TextInput {
                                    id: otherPw
                                    anchors { fill: parent; leftMargin: root.s(14); rightMargin: root.s(14) }
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password; passwordCharacter: "•"
                                    color: ThemeBackend.text; selectionColor: Qt.alpha(root.accent, 0.4)
                                    font.pixelSize: root.s(12); clip: true
                                    Keys.onReturnPressed: root.connectHidden(ssidIn.text, otherPw.text)
                                    Keys.onEnterPressed: root.connectHidden(ssidIn.text, otherPw.text)
                                    Keys.onEscapePressed: (event) => { root.otherOpen = false; root.forceActiveFocus(); event.accepted = true; }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: otherPw.text === ""
                                        text: "Password (empty for open networks)"
                                        font.pixelSize: root.s(11); color: root.dim
                                    }
                                }
                            }
                            GoButton {
                                id: otherGo
                                anchors.right: parent.right
                                ready: ssidIn.text !== "" && !root.otherBusy
                                onClicked: root.connectHidden(ssidIn.text, otherPw.text)
                            }
                        }
                    }
                }

                // ── Buttons ───────────────────────────────────────────────────
                Row {
                    id: buttons
                    width: parent.width
                    spacing: root.s(8)
                    Button {
                        width: (buttons.width - buttons.spacing) / 2
                        label: root.otherOpen ? "Cancel" : "Other network…"
                        outlined: true
                        enabled: root.wifiOn && !root.hotspotOn
                        onClicked: root.otherOpen = !root.otherOpen
                    }
                    Button {
                        width: (buttons.width - buttons.spacing) / 2
                        label: "Settings"
                        onClicked: {
                            Quickshell.execDetached(["kitty", "--class", "nmtui", "-e", "nmtui"]);
                            if (typeof masterWindow !== "undefined" && masterWindow.switchWidget) masterWindow.switchWidget("hidden", "");
                        }
                    }
                }
            }
        }
    }

    // ── Components ────────────────────────────────────────────────────────────
    component Tile: Rectangle {
        id: tile
        property string icon
        property string label
        property bool active: false
        property bool busy: false
        signal clicked()
        height: root.tileH
        radius: root.cardRadius
        color: active ? (tileH.hovered ? Qt.lighter(root.accent, 1.08) : root.accent)
                      : (tileH.hovered && enabled ? root.cardHover : root.card)
        border.color: active ? "transparent" : root.faint
        opacity: enabled ? (busy ? 0.7 : 1) : 0.45
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Text {
            anchors { left: parent.left; top: parent.top; leftMargin: root.s(12); topMargin: root.s(10) }
            text: tile.icon; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(18)
            color: tile.active ? root.accentInk : ThemeBackend.text
        }
        Text {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: root.s(12); rightMargin: root.s(8); bottomMargin: root.s(10) }
            text: tile.label; elide: Text.ElideRight
            font.pixelSize: root.s(12); font.weight: Font.DemiBold
            color: tile.active ? root.accentInk : ThemeBackend.text
        }
        HoverHandler { id: tileH; cursorShape: tile.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        MouseArea { anchors.fill: parent; enabled: tile.enabled && !tile.busy; onClicked: tile.clicked() }
    }

    component Pill: Rectangle {
        id: pl
        property string text
        property color tint: root.accent
        readonly property bool hovered: plH.hovered
        signal clicked()
        height: root.s(24); radius: height / 2
        width: plText.implicitWidth + root.s(20)
        color: Qt.lighter(tint, 1.15)
        Behavior on color { ColorAnimation { duration: Motion.hover } }
        Behavior on width { NumberAnimation { duration: Motion.hover } }
        Text {
            id: plText
            anchors.centerIn: parent
            text: pl.text; font.pixelSize: root.s(11); font.weight: Font.DemiBold
            color: root.accentInk
        }
        HoverHandler { id: plH; cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; onClicked: pl.clicked() }
    }

    component Button: Rectangle {
        id: btn
        property string label
        property bool outlined: false
        signal clicked()
        height: root.btnH; radius: height / 2
        color: outlined ? (btnH.hovered && enabled ? root.faint : "transparent")
                        : (btnH.hovered ? root.cardHover : root.card)
        border.color: outlined ? Qt.alpha(ThemeBackend.text, 0.35) : root.faint
        opacity: enabled ? 1 : 0.45
        Behavior on color { ColorAnimation { duration: Motion.hover } }
        Text {
            anchors.centerIn: parent
            text: btn.label; font.pixelSize: root.s(12); font.weight: Font.DemiBold
            color: ThemeBackend.text
        }
        HoverHandler { id: btnH; cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        MouseArea { anchors.fill: parent; enabled: btn.enabled; onClicked: btn.clicked() }
    }

    component Field: Rectangle {
        height: root.s(32); radius: height / 2
        color: Qt.alpha(ThemeBackend.crust, 0.6)
        border.color: root.faint
    }

    component GoButton: Rectangle {
        id: gb
        property bool ready: false
        signal clicked()
        width: root.s(32); height: width; radius: width / 2
        color: ready ? (gbH.hovered ? Qt.lighter(root.accent, 1.1) : root.accent) : root.card
        Behavior on color { ColorAnimation { duration: Motion.hover } }
        Text {
            anchors.centerIn: parent
            text: "󰁔"; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(15)
            color: gb.ready ? root.accentInk : root.dim
        }
        HoverHandler { id: gbH; cursorShape: gb.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { onTapped: if (gb.ready) gb.clicked() }
    }

    component NetRow: Item {
        id: row
        required property int index
        required property string name
        required property real strength
        required property bool secured
        required property string secLabel
        required property bool known
        required property bool busy
        readonly property bool open: root.pwFor === name
        readonly property bool hot: hov.hovered
        readonly property bool failed: root.failName === name
        readonly property bool connecting: busy || root.connectingName === name
        height: root.rowH + (open ? root.pwH : 0)
        clip: true
        Behavior on height { NumberAnimation { duration: Motion.resize; easing.type: Motion.resizeEasing } }

        Rectangle {
            anchors.fill: parent
            radius: Math.min(ThemeBackend.borderRadius, root.s(14))
            color: row.open || row.hot ? root.cardHover : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.hover } }
        }

        // Header line of the row
        Item {
            id: line
            width: parent.width; height: root.rowH
            HoverHandler {
                id: hov
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: {
                    if (hovered) root.hoverName = row.name;
                    else if (root.hoverName === row.name) root.hoverName = "";
                }
            }
            TapHandler { onTapped: root.activate(row.name) }

            Rectangle {
                id: sig
                anchors { left: parent.left; leftMargin: root.s(8); verticalCenter: parent.verticalCenter }
                width: root.s(36); height: width; radius: width / 2
                color: row.known ? Qt.alpha(root.accent, 0.18) : Qt.alpha(ThemeBackend.surface1, 0.8)
                Text {
                    anchors.centerIn: parent
                    text: root.sigIcon(row.strength, row.secured)
                    font.family: ThemeBackend.iconFont; font.pixelSize: root.s(16)
                    color: row.known ? root.accent : ThemeBackend.text
                }
            }
            Column {
                anchors {
                    left: sig.right; leftMargin: root.s(12)
                    right: tail.left; rightMargin: root.s(8)
                    verticalCenter: parent.verticalCenter
                }
                spacing: root.s(2)
                Text {
                    width: parent.width
                    text: row.name; elide: Text.ElideRight
                    font.pixelSize: root.s(13); font.weight: Font.DemiBold
                    color: ThemeBackend.text
                }
                Text {
                    width: parent.width
                    text: row.failed ? root.failText
                        : row.connecting ? "Connecting…"
                        : [row.known ? "Saved" : "", row.secLabel].filter(s => s !== "").join(" · ")
                    elide: Text.ElideRight
                    font.pixelSize: root.s(11)
                    color: row.failed ? ThemeBackend.red : row.connecting ? root.accent : root.dim
                }
            }
            Row {
                id: tail
                anchors { right: parent.right; rightMargin: root.s(12); verticalCenter: parent.verticalCenter }
                spacing: root.s(10)
                // Forget a saved network (on hover)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.known && !row.connecting
                    opacity: hov.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.hover } }
                    text: "󰆴"; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(14)
                    color: forgetH.hovered ? ThemeBackend.red : root.dim
                    HoverHandler { id: forgetH; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { let n = root.netRefs[row.name]; if (n) n.forget(); } }
                }
                // Three dots while connecting, otherwise a chevron
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(3)
                    visible: row.connecting
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            width: root.s(4); height: width; radius: width / 2
                            color: root.accent
                            opacity: 0.3
                            SequentialAnimation on opacity {
                                running: row.connecting && root.visible; loops: Animation.Infinite
                                PauseAnimation { duration: index * 150 }
                                NumberAnimation { to: 1; duration: 300 }
                                NumberAnimation { to: 0.3; duration: 300 }
                                PauseAnimation { duration: (2 - index) * 150 }
                            }
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !row.connecting
                    text: row.open ? "󰅀" : "󰅂"
                    font.family: ThemeBackend.iconFont; font.pixelSize: root.s(14)
                    color: row.hot ? ThemeBackend.text : root.dim
                    Behavior on color { ColorAnimation { duration: Motion.hover } }
                }
            }
        }

        // Password field (secured networks without saved secret)
        Item {
            y: root.rowH
            width: parent.width; height: root.pwH
            opacity: row.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.normal } }

            Rectangle {
                id: field
                anchors { left: parent.left; right: go.left; leftMargin: root.s(12); rightMargin: root.s(8); verticalCenter: parent.verticalCenter; verticalCenterOffset: -root.s(3) }
                height: root.s(32); radius: height / 2
                color: Qt.alpha(ThemeBackend.crust, 0.6)
                border.color: pw.activeFocus ? Qt.alpha(root.accent, 0.6) : root.faint
                Behavior on border.color { ColorAnimation { duration: Motion.hover } }

                TextInput {
                    id: pw
                    anchors { left: parent.left; right: eye.left; leftMargin: root.s(14); rightMargin: root.s(6); verticalCenter: parent.verticalCenter }
                    property bool reveal: false
                    echoMode: reveal ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: ThemeBackend.text
                    selectionColor: Qt.alpha(root.accent, 0.4)
                    font.pixelSize: root.s(12)
                    clip: true
                    enabled: row.open
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pw.text === ""
                        text: "Password for " + row.name
                        font.pixelSize: root.s(11); color: root.dim
                        width: parent.width; elide: Text.ElideRight
                    }
                    Keys.onReturnPressed: if (text.length > 0) root.connectTo(row.name, text)
                    Keys.onEnterPressed: if (text.length > 0) root.connectTo(row.name, text)
                    Keys.onEscapePressed: (event) => { root.pwFor = ""; root.forceActiveFocus(); event.accepted = true; }
                }
                Text {
                    id: eye
                    anchors { right: parent.right; rightMargin: root.s(12); verticalCenter: parent.verticalCenter }
                    text: pw.reveal ? "󰈈" : "󰈉"
                    font.family: ThemeBackend.iconFont; font.pixelSize: root.s(14)
                    color: eyeH.hovered ? ThemeBackend.text : root.dim
                    HoverHandler { id: eyeH; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pw.reveal = !pw.reveal }
                }
            }
            GoButton {
                id: go
                anchors { right: parent.right; rightMargin: root.s(12); verticalCenter: field.verticalCenter }
                ready: pw.text.length >= 8
                onClicked: root.connectTo(row.name, pw.text)
            }
        }

        onOpenChanged: {
            if (open) { pw.text = ""; pw.reveal = false; pw.forceActiveFocus(); }
        }
    }
}
