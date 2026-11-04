// Wi-Fi panel: hangs from its bar section like the other dropdowns (Main.qml convexPlace, at least as
// wide as the section; height follows the content via drawerHeight).
// Radar hero: nearby networks are blips placed by signal strength (stronger = closer to the centre)
// that light up as the sweep passes; the connected network sits in the centre, its details beside it.
// List below: hovering a row highlights its blip, secured networks unfold a password field.
// Data comes straight from Quickshell.Networking (NetworkManager). Opened by the bar face "wifi"
// (qs_manager.sh toggle network). Bluetooth has its own popup (bluetooth/BluetoothPopup.qml).
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
    readonly property color dim: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.45)
    readonly property color faint: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)
    readonly property color card: Qt.alpha(ThemeBackend.surface0, 0.55)
    readonly property color cardHover: Qt.alpha(ThemeBackend.surface1, 0.65)

    // ── Layout ────────────────────────────────────────────────────────────────
    readonly property real pad: s(14)
    readonly property real gap: s(12)
    readonly property real headerH: s(34)
    readonly property real heroH: s(150)
    readonly property real rowH: s(44)
    readonly property real pwH: s(48)
    readonly property int maxRows: 6
    readonly property bool showList: wifiOn
    readonly property real listH: netModel.count === 0 ? s(40)
        : Math.min(netModel.count, maxRows) * rowH + (pwFor !== "" ? pwH : 0)
    // Main.qml sizes the popup to this (binding, never written by Main)
    readonly property real drawerHeight: pad * 2 + headerH + gap + heroH
        + (showList ? gap + s(20) + listH : 0)

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
            pwFor = ""; failName = ""; hoverName = "";
            forceActiveFocus();
            intro = 0; introAnim.restart();
            rebuild();
            fetchLink();
            if (Networking.canCheckConnectivity) Networking.checkConnectivity();
        } else {
            introAnim.stop(); exitAnim.stop(); intro = 0;
        }
        updateScan();
    }

    Keys.onEscapePressed: (event) => {
        if (pwFor !== "") pwFor = "";
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
    readonly property var wifiDevice: deviceOf(DeviceType.Wifi)
    readonly property var wiredDevice: deviceOf(DeviceType.Wired)
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property bool wiredUp: !!wiredDevice && wiredDevice.connected

    function updateScan() {
        if (wifiDevice) wifiDevice.scannerEnabled = visible && wifiOn;
    }
    onWifiDeviceChanged: { updateScan(); rebuild(); }
    onWifiOnChanged: { updateScan(); rebuild(); }

    // ── Networks ──────────────────────────────────────────────────────────────
    // name → WifiNetwork (strongest access point per SSID)
    property var netRefs: ({})
    // Connected network for the hero: { name, strength, secured, secLabel } or null
    property var current: null
    property string hoverName: ""   // row or blip under the mouse
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

    // ── Link details: IP + frequency of the Wi-Fi interface ──────────────────
    property string ip: ""
    property string band: ""
    function fetchLink() {
        if (visible && wifiDevice && wifiDevice.name && !linkProc.running) linkProc.running = true;
    }
    Process {
        id: linkProc
        command: ["sh", "-c", "ip -4 -o addr show dev \"$1\" | awk '{print $4}' | cut -d/ -f1 | head -n1; "
                            + "iw dev \"$1\" link 2>/dev/null | awk '/freq:/{print $2}'", "sh", root.wifiDevice ? root.wifiDevice.name : ""]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = this.text.split("\n");
                root.ip = (l[0] || "").trim();
                let f = parseFloat(l[1] || "");
                root.band = isNaN(f) ? "" : (f < 3000 ? "2.4 GHz" : (f < 5925 ? "5 GHz" : "6 GHz"));
            }
        }
    }
    Timer { interval: 8000; repeat: true; running: root.visible && root.current !== null; onTriggered: root.fetchLink() }
    onCurrentChanged: { ip = ""; band = ""; fetchLink(); }

    function sigIcon(strength, secured) {
        if (strength > 0.75) return secured ? "󰤪" : "󰤨";
        if (strength > 0.5)  return secured ? "󰤧" : "󰤥";
        if (strength > 0.25) return secured ? "󰤤" : "󰤢";
        return secured ? "󰤡" : "󰤟";
    }
    // Stable pseudo-random direction per SSID
    function angleFor(name) {
        let h = 7;
        for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 3600;
        return h / 10;
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

            Item {
                id: body
                anchors { fill: parent; margins: root.pad }

                // ── Header ────────────────────────────────────────────────────
                Item {
                    id: header
                    width: parent.width; height: root.headerH
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Wi-Fi"; color: ThemeBackend.text; font.pixelSize: root.s(15); font.weight: Font.Bold }
                        Text {
                            text: !root.wifiDevice ? "No Wi-Fi adapter"
                                : !root.wifiOn ? "Off"
                                : root.connectingName !== "" ? "Connecting to " + root.connectingName + "…"
                                : root.current ? (Networking.connectivity === NetworkConnectivity.Portal ? "Sign-in required"
                                               : Networking.connectivity === NetworkConnectivity.Limited ? "Limited connectivity"
                                               : "Connected")
                                : netModel.count + (netModel.count === 1 ? " network nearby" : " networks nearby")
                            color: root.current && root.wifiOn ? Qt.alpha(root.accent, 0.85) : root.dim
                            font.pixelSize: root.s(10)
                        }
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: root.s(10)
                        // Wired link, if any
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.wiredUp
                            height: root.s(24); radius: height / 2
                            width: ethRow.implicitWidth + root.s(18)
                            color: root.card
                            border.color: root.faint
                            Row {
                                id: ethRow; anchors.centerIn: parent; spacing: root.s(6)
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰈀"; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(12); color: ThemeBackend.green }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.wiredDevice && root.wiredDevice.linkSpeed ? root.wiredDevice.linkSpeed + " Mb/s" : "Ethernet"
                                    font.pixelSize: root.s(10); color: ThemeBackend.text
                                }
                            }
                        }
                        Switch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.wifiOn
                            enabled: !!root.wifiDevice
                            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                        }
                    }
                }

                // ── Hero: radar + connected network ───────────────────────────
                Item {
                    id: hero
                    y: header.height + root.gap
                    width: parent.width; height: root.heroH

                    Rectangle {
                        anchors.fill: parent
                        radius: Math.min(ThemeBackend.borderRadius, root.s(20))
                        color: root.card
                        border.color: root.faint
                    }

                    Radar {
                        id: radar
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: root.s(8) }
                        width: height
                    }

                    Column {
                        id: info
                        anchors {
                            left: radar.right; leftMargin: root.s(14)
                            right: parent.right; rightMargin: root.s(14)
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: root.s(8)

                        Label { text: !root.wifiOn ? "WI-FI OFF" : root.current ? "CONNECTED" : "NOT CONNECTED" }
                        Text {
                            width: parent.width
                            text: !root.wifiOn ? "Radio is off"
                                : root.current ? root.current.name
                                : root.connectingName !== "" ? root.connectingName
                                : "Pick a network"
                            elide: Text.ElideRight
                            font.pixelSize: root.s(17); font.weight: Font.Bold
                            color: root.current && root.wifiOn ? ThemeBackend.text : root.dim
                            Behavior on color { ColorAnimation { duration: Motion.normal } }
                        }

                        Flow {
                            width: parent.width; spacing: root.s(6)
                            visible: root.wifiOn && root.current !== null
                            Chip { icon: root.current ? root.sigIcon(root.current.strength, false) : ""; label: root.current ? Math.round(root.current.strength * 100) + "%" : "" }
                            Chip { visible: root.band !== ""; icon: "󰖩"; label: root.band }
                            Chip { visible: !!root.current && root.current.secLabel !== ""; icon: root.current && root.current.secured ? "󰌾" : "󰿆"; label: root.current ? root.current.secLabel : "" }
                        }

                        Row {
                            spacing: root.s(6)
                            visible: root.wifiOn && root.current !== null
                            Chip {
                                id: ipChip
                                visible: root.ip !== ""
                                icon: copied ? "󰄬" : "󰆏"; label: root.ip; mono: true; clickable: true
                                property bool copied: false
                                Timer { id: copiedT; interval: 1200; onTriggered: ipChip.copied = false }
                                onClicked: { Quickshell.execDetached(["wl-copy", root.ip]); copied = true; copiedT.restart(); }
                            }
                            Chip {
                                visible: Networking.connectivity === NetworkConnectivity.Portal
                                icon: "󰖟"; label: "Sign in"; clickable: true; tint: ThemeBackend.yellow
                                onClicked: Quickshell.execDetached(["xdg-open", "http://nmcheck.gnome.org/check_network_status.txt"])
                            }
                            Chip {
                                icon: "󰖪"; label: "Disconnect"; clickable: true; tint: ThemeBackend.red
                                onClicked: { let n = root.current ? root.netRefs[root.current.name] : null; if (n) n.disconnect(); }
                            }
                        }

                        Text {
                            width: parent.width
                            visible: !root.wifiOn || root.current === null
                            wrapMode: Text.WordWrap
                            text: !root.wifiOn ? "Turn Wi-Fi on with the switch above."
                                : netModel.count > 0 ? "Stronger networks sit closer to the centre."
                                : "Scanning…"
                            font.pixelSize: root.s(11); color: root.dim
                        }
                    }
                }

                // ── Network list ──────────────────────────────────────────────
                Item {
                    id: listArea
                    y: hero.y + hero.height + root.gap
                    width: parent.width
                    height: root.s(20) + root.listH
                    visible: root.showList
                    opacity: root.showList ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.normal } }

                    Label { text: "NEARBY"; anchors.left: parent.left; anchors.leftMargin: root.s(4) }
                    Label {
                        anchors.right: parent.right; anchors.rightMargin: root.s(4)
                        text: "SCANNING"
                        visible: !!root.wifiDevice && root.wifiDevice.scannerEnabled
                        SequentialAnimation on opacity {
                            running: root.visible && root.wifiOn && Motion.factor > 0; loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        y: root.s(20)
                        width: parent.width; height: root.s(40)
                        visible: netModel.count === 0
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: "Looking for networks…"; font.pixelSize: root.s(11); color: root.dim
                    }

                    Flickable {
                        id: flick
                        y: root.s(20)
                        width: parent.width; height: root.listH
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
            }
        }
    }

    // ── Components ────────────────────────────────────────────────────────────
    component Label: Text {
        font.family: ThemeBackend.fontFamily
        font.pixelSize: root.s(9); font.weight: Font.Bold; font.letterSpacing: 1.2
        color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.3)
    }

    component Chip: Rectangle {
        id: chip
        property string icon
        property string label
        property bool mono: false
        property bool clickable: false
        property color tint: root.accent
        signal clicked()
        height: root.s(24); radius: height / 2
        width: chipRow.implicitWidth + root.s(16)
        color: clickable && chipH.hovered ? Qt.alpha(tint, 0.18) : root.card
        border.color: clickable && chipH.hovered ? Qt.alpha(tint, 0.4) : root.faint
        Behavior on color { ColorAnimation { duration: Motion.hover } }
        Row {
            id: chipRow; anchors.centerIn: parent; spacing: root.s(5)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(11)
                color: chip.clickable && chipH.hovered ? chip.tint : root.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label; font.pixelSize: root.s(10)
                font.family: chip.mono ? "JetBrains Mono" : Qt.application.font.family
                color: ThemeBackend.text
            }
        }
        HoverHandler { id: chipH; cursorShape: chip.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        MouseArea { anchors.fill: parent; enabled: chip.clickable; onClicked: chip.clicked() }
    }

    // Radar: rings, a sweep and one blip per nearby network
    component Radar: Item {
        id: rd
        readonly property real cx: width / 2
        readonly property real cy: height / 2
        readonly property real radius: width / 2 - root.s(2)
        readonly property bool sweeping: root.visible && root.wifiOn && Motion.factor > 0
        property real sweep: 0
        NumberAnimation on sweep {
            running: rd.sweeping
            from: 0; to: 360; duration: 4200; loops: Animation.Infinite
        }

        Canvas {
            id: rings
            anchors.fill: parent
            property color c: root.accent
            onCChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                let ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = String(c);
                ctx.lineWidth = 1;
                ctx.globalAlpha = 0.16;
                for (let i = 1; i <= 3; i++) {
                    ctx.beginPath();
                    ctx.arc(rd.cx, rd.cy, rd.radius * i / 3, 0, 2 * Math.PI);
                    ctx.stroke();
                }
                ctx.globalAlpha = 0.08;
                ctx.beginPath();
                ctx.moveTo(rd.cx - rd.radius, rd.cy); ctx.lineTo(rd.cx + rd.radius, rd.cy);
                ctx.moveTo(rd.cx, rd.cy - rd.radius); ctx.lineTo(rd.cx, rd.cy + rd.radius);
                ctx.stroke();
            }
        }

        // Sweep: fading wedge behind a bright leading edge, painted once and rotated
        Canvas {
            anchors.fill: parent
            visible: rd.sweeping
            rotation: rd.sweep
            property color c: root.accent
            onCChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                let ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = String(c);
                ctx.strokeStyle = String(c);
                let steps = 36, span = 75 * Math.PI / 180;
                for (let i = 0; i < steps; i++) {
                    ctx.globalAlpha = 0.20 * Math.pow(1 - i / steps, 1.6);
                    ctx.beginPath();
                    ctx.moveTo(rd.cx, rd.cy);
                    ctx.arc(rd.cx, rd.cy, rd.radius, -span * (i + 1) / steps, -span * i / steps + 0.004);
                    ctx.closePath();
                    ctx.fill();
                }
                ctx.globalAlpha = 0.55;
                ctx.lineWidth = 1.5;
                ctx.beginPath();
                ctx.moveTo(rd.cx, rd.cy); ctx.lineTo(rd.cx + rd.radius, rd.cy);
                ctx.stroke();
            }
        }

        Repeater {
            model: netModel
            delegate: Item {
                id: blip
                required property string name
                required property real strength
                required property bool known
                required property bool busy
                readonly property real ang: root.angleFor(name)
                readonly property real dist: rd.radius * (0.32 + 0.6 * (1 - strength))
                readonly property bool hot: root.hoverName === name
                // 1 right after the sweep passed, fading over the next 120°
                readonly property real glow: {
                    if (!rd.sweeping) return 1;
                    let d = ((rd.sweep - ang) % 360 + 360) % 360;
                    return d < 120 ? 1 - d / 120 : 0;
                }
                x: rd.cx + dist * Math.cos(ang * Math.PI / 180)
                y: rd.cy + dist * Math.sin(ang * Math.PI / 180)
                z: hot ? 2 : 1
                Behavior on x { NumberAnimation { duration: Motion.slow; easing.type: Motion.resizeEasing } }
                Behavior on y { NumberAnimation { duration: Motion.slow; easing.type: Motion.resizeEasing } }

                // Ping ring as the sweep passes
                Rectangle {
                    anchors.centerIn: parent
                    width: root.s(7); height: width; radius: width / 2
                    color: "transparent"
                    border.color: blip.known ? root.accent : ThemeBackend.text
                    border.width: 1
                    scale: 1 + 1.8 * (1 - blip.glow)
                    opacity: rd.sweeping ? 0.5 * blip.glow * blip.glow : 0
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: blip.hot ? root.s(11) : root.s(7); height: width; radius: width / 2
                    color: blip.known ? root.accent : ThemeBackend.text
                    opacity: blip.hot || blip.busy ? 1 : 0.45 + 0.55 * blip.glow
                    Behavior on width { NumberAnimation { duration: Motion.hover; easing.type: Motion.popEasing } }
                }
                // Name tag while hovered (row or blip)
                Rectangle {
                    visible: opacity > 0
                    opacity: blip.hot ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.hover } }
                    x: blip.x > rd.width * 0.6 ? -width - root.s(8) : root.s(8)
                    y: -height / 2
                    width: tag.implicitWidth + root.s(12); height: root.s(18); radius: height / 2
                    color: ThemeBackend.surface0
                    Text { id: tag; anchors.centerIn: parent; text: blip.name; font.pixelSize: root.s(9); color: ThemeBackend.text }
                }
                Item {
                    anchors.centerIn: parent
                    width: root.s(16); height: width
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                        onHoveredChanged: {
                            if (hovered) root.hoverName = blip.name;
                            else if (root.hoverName === blip.name) root.hoverName = "";
                        }
                    }
                    TapHandler { onTapped: root.activate(blip.name) }
                }
            }
        }

        // Centre: this device / the connected network
        Rectangle {
            anchors.centerIn: parent
            width: root.s(40); height: width; radius: width / 2
            color: root.wifiOn && root.current ? root.accent : ThemeBackend.surface0
            border.color: root.faint
            Behavior on color { ColorAnimation { duration: Motion.normal } }
            Text {
                anchors.centerIn: parent
                text: !root.wifiOn ? "󰤮" : root.current ? root.sigIcon(root.current.strength, false) : "󰤯"
                font.family: ThemeBackend.iconFont; font.pixelSize: root.s(18)
                color: root.wifiOn && root.current ? ThemeBackend.base : root.dim
            }
            // Pulse while connecting
            Rectangle {
                anchors.centerIn: parent
                width: parent.width; height: width; radius: width / 2
                color: "transparent"; border.color: root.accent; border.width: root.s(2)
                visible: root.connectingName !== ""
                property real t: 0
                scale: 1 + 0.9 * t; opacity: 1 - t
                NumberAnimation on t { running: root.connectingName !== "" && root.visible; from: 0; to: 1; duration: 1100; loops: Animation.Infinite; easing.type: Easing.OutCubic }
            }
        }
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
        readonly property bool hot: hov.hovered || root.hoverName === name
        readonly property bool failed: root.failName === name
        readonly property bool connecting: busy || root.connectingName === name
        height: root.rowH + (open ? root.pwH : 0)
        clip: true
        Behavior on height { NumberAnimation { duration: Motion.resize; easing.type: Motion.resizeEasing } }

        Rectangle {
            anchors { fill: parent; topMargin: root.s(2); bottomMargin: root.s(2) }
            radius: Math.min(ThemeBackend.borderRadius, root.s(14))
            color: row.open ? root.card : row.hot ? root.cardHover : "transparent"
            border.color: row.open ? root.faint : "transparent"
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

            Text {
                id: sig
                anchors { left: parent.left; leftMargin: root.s(12); verticalCenter: parent.verticalCenter }
                width: root.s(20)
                text: root.sigIcon(row.strength, row.secured)
                font.family: ThemeBackend.iconFont; font.pixelSize: root.s(16)
                color: row.known ? root.accent : (row.hot ? ThemeBackend.text : root.dim)
                Behavior on color { ColorAnimation { duration: Motion.hover } }
            }
            Column {
                anchors {
                    left: sig.right; leftMargin: root.s(10)
                    right: tail.left; rightMargin: root.s(8)
                    verticalCenter: parent.verticalCenter
                }
                spacing: root.s(1)
                Text {
                    width: parent.width
                    text: row.name; elide: Text.ElideRight
                    font.pixelSize: root.s(12); font.weight: row.known ? Font.Medium : Font.Normal
                    color: ThemeBackend.text
                }
                Text {
                    width: parent.width
                    text: row.failed ? root.failText
                        : row.connecting ? "Connecting…"
                        : [row.known ? "Saved" : "", row.secLabel].filter(s => s !== "").join("  ·  ")
                    elide: Text.ElideRight
                    font.pixelSize: root.s(9)
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
                    color: row.hot ? ThemeBackend.text : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.2)
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
            Rectangle {
                id: go
                anchors { right: parent.right; rightMargin: root.s(12); verticalCenter: field.verticalCenter }
                width: root.s(32); height: width; radius: width / 2
                readonly property bool ready: pw.text.length >= 8
                color: ready ? (goH.hovered ? Qt.lighter(root.accent, 1.1) : root.accent) : root.card
                Behavior on color { ColorAnimation { duration: Motion.hover } }
                Text {
                    anchors.centerIn: parent
                    text: "󰁔"; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(15)
                    color: go.ready ? ThemeBackend.base : root.dim
                }
                HoverHandler { id: goH; cursorShape: go.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { onTapped: if (pw.text.length > 0) root.connectTo(row.name, pw.text) }
            }
        }

        onOpenChanged: {
            if (open) { pw.text = ""; pw.reveal = false; pw.forceActiveFocus(); }
        }
    }

    component Switch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled()
        width: root.s(44); height: root.s(24); radius: height / 2
        color: checked ? (swHov.hovered ? Qt.lighter(root.accent, 1.1) : root.accent)
                       : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, swHov.hovered ? 0.15 : 0.1)
        border.color: checked ? Qt.darker(root.accent, 1.2) : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.2)
        border.width: 1
        opacity: !enabled ? 0.6 : 1
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Rectangle {
            width: root.s(18); height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? sw.width - width - root.s(3) : root.s(3)
            color: "white"
            Behavior on x { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack } }
        }
        HoverHandler { id: swHov; cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; enabled: sw.enabled; onClicked: sw.toggled() }
    }
}
