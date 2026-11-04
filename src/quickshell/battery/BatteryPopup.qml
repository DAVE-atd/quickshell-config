// Battery dropdown: charge ring (spark travels along it while charging), power draw, energy, health
// and cycles, a 24 h charge graph from UPower's history (D-Bus GetHistory, hover shows the value) and
// the power-profiles-daemon profile. Ported from DAVE-atd/Brain_Shell (src/popups/BatteryPopup.qml),
// AGPL-3.0 like Serpantinum; the graph is new. Opened by the bar face "bat" (qs_manager.sh toggle battery).
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../"
import "../reusables"

Item {
    id: root
    visible: false
    focus: true

    function s(val) { return Scaler.s(val) }

    readonly property color dim: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.45)
    readonly property color faint: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)
    readonly property color card: Qt.alpha(ThemeBackend.surface0, 0.55)

    // ── Layout ────────────────────────────────────────────────────────────────
    readonly property real pad: s(14)
    readonly property real gap: s(10)
    readonly property real headerH: s(34)
    readonly property real heroH: s(170)
    readonly property real graphH: s(112)
    readonly property real segH: s(58)
    readonly property real labelH: s(14)
    readonly property bool limited: PowerProfiles.profile === PowerProfile.Performance && PowerProfiles.degradationReason !== 0
    // Main.qml sizes the popup to this (binding, never written by Main)
    readonly property real drawerHeight: pad * 2 + content.implicitHeight

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
            forceActiveFocus();
            intro = 0; introAnim.restart();
            cycleProc.running = true;
            historyProc.running = true;
        } else {
            introAnim.stop(); exitAnim.stop(); intro = 0;
        }
    }

    Keys.onEscapePressed: (event) => {
        if (typeof masterWindow !== "undefined" && masterWindow.switchWidget) masterWindow.switchWidget("hidden", "");
        else Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }

    // ── Data ──────────────────────────────────────────────────────────────────
    readonly property var bat: UPower.displayDevice
    // The real battery (health lives there, not on the aggregate device)
    readonly property var cell: {
        let list = UPower.devices.values;
        for (let i = 0; i < list.length; i++) if (list[i].isLaptopBattery) return list[i];
        return null;
    }
    readonly property real pct: bat && bat.ready ? bat.percentage : 0
    readonly property bool charging: !!bat && (bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: !!bat && bat.state === UPowerDeviceState.FullyCharged
    readonly property real watts: bat ? Math.abs(bat.changeRate || 0) : 0

    readonly property color levelColor: {
        if (charging || full) return ThemeBackend.green;
        if (pct <= 0.10) return ThemeBackend.red;
        if (pct <= 0.20) return ThemeBackend.peach;
        if (pct <= 0.30) return ThemeBackend.yellow;
        return ThemeBackend.blue;
    }

    function dur(sec) {
        if (!sec || sec <= 0) return "";
        let h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
        if (m === 60) { h++; m = 0; }
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }
    readonly property string statusText: {
        if (!bat || !bat.ready) return "No battery";
        if (full) return "Fully charged";
        if (bat.state === UPowerDeviceState.PendingCharge) return "Plugged in, not charging";
        if (charging) return bat.timeToFull > 0 ? "Full in " + dur(bat.timeToFull) : "Charging";
        return bat.timeToEmpty > 0 ? dur(bat.timeToEmpty) + " left" : "On battery";
    }

    // Cycle count is not exported by UPower (0 = not reported by the firmware)
    property int cycles: -1
    Process {
        id: cycleProc
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT*/cycle_count 2>/dev/null | head -n1"]
        stdout: StdioCollector { onStreamFinished: { let n = parseInt(this.text); root.cycles = isNaN(n) ? -1 : n; } }
    }

    // Charge history of the last 24 h: [{ t, v (0-100), st (1 charging, 2 discharging, 4 full) }], oldest first
    readonly property int span: 86400
    property var history: []
    property real historyNow: 0
    Process {
        id: historyProc
        command: ["sh", "-c", "d=$(busctl --system tree --list org.freedesktop.UPower 2>/dev/null | grep /battery_ | head -n1); "
                            + "[ -n \"$d\" ] && busctl --system --json=short call org.freedesktop.UPower \"$d\" "
                            + "org.freedesktop.UPower.Device GetHistory suu charge " + root.span + " 400"]
        stdout: StdioCollector {
            onStreamFinished: {
                let pts = [];
                try {
                    let raw = JSON.parse(this.text).data[0];
                    // UPower writes 0 % / state 0 glitch entries around suspend: skip them
                    for (let i = 0; i < raw.length; i++) if (raw[i][2] !== 0) pts.push({ t: raw[i][0], v: raw[i][1], st: raw[i][2] });
                } catch (e) {}
                pts.sort((a, b) => a.t - b.t);
                root.historyNow = Date.now() / 1000;
                root.history = pts;
            }
        }
    }
    Timer { interval: 60000; repeat: true; running: root.visible; onTriggered: historyProc.running = true }

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
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.pad }
                spacing: root.gap

                // ── Header ────────────────────────────────────────────────────
                Item {
                    width: parent.width; height: root.headerH
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Battery"; color: ThemeBackend.text; font.pixelSize: root.s(15); font.weight: Font.Bold }
                        Text {
                            text: root.statusText
                            color: Qt.alpha(root.levelColor, 0.85)
                            font.pixelSize: root.s(10)
                        }
                    }
                }

                // ── Hero: ring + stats ────────────────────────────────────────
                Rectangle {
                    width: parent.width; height: root.heroH
                    radius: Math.min(ThemeBackend.borderRadius, root.s(20))
                    color: root.card
                    border.color: root.faint
                    clip: true

                    Item {
                        id: ringBox
                        width: root.heroH - root.s(20); height: width
                        anchors { left: parent.left; leftMargin: root.s(12); verticalCenter: parent.verticalCenter }

                        readonly property real cx: width / 2
                        readonly property real cy: height / 2
                        readonly property real thick: root.s(9)
                        readonly property real r: width / 2 - root.s(10) - thick / 2
                        // Open at the bottom: 70° gap
                        readonly property real start: 125
                        readonly property real sweep: 290
                        property real shown: root.pct
                        Behavior on shown { NumberAnimation { duration: Motion.ultraSlow * 2; easing.type: Motion.openEasing } }

                        // Soft glow in the level colour, breathing while charging
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            property real breathe: 0.55
                            opacity: root.charging ? breathe : 0.55
                            SequentialAnimation on breathe {
                                running: root.charging && root.visible && Motion.factor > 0; loops: Animation.Infinite
                                NumberAnimation { to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0.45; duration: 1400; easing.type: Easing.InOutSine }
                            }
                            ShapePath {
                                strokeColor: "transparent"
                                fillGradient: RadialGradient {
                                    centerX: ringBox.cx; centerY: ringBox.cy
                                    focalX: centerX; focalY: centerY
                                    centerRadius: ringBox.width / 2
                                    GradientStop { position: 0.0; color: Qt.alpha(root.levelColor, 0.22) }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                                PathAngleArc { centerX: ringBox.cx; centerY: ringBox.cy; radiusX: ringBox.width / 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
                            }
                        }

                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.08)
                                strokeWidth: ringBox.thick
                                capStyle: ShapePath.RoundCap
                                fillColor: "transparent"
                                PathAngleArc { centerX: ringBox.cx; centerY: ringBox.cy; radiusX: ringBox.r; radiusY: ringBox.r; startAngle: ringBox.start; sweepAngle: ringBox.sweep }
                            }
                            ShapePath {
                                strokeColor: root.levelColor
                                strokeWidth: ringBox.thick
                                capStyle: ShapePath.RoundCap
                                fillColor: "transparent"
                                PathAngleArc { centerX: ringBox.cx; centerY: ringBox.cy; radiusX: ringBox.r; radiusY: ringBox.r; startAngle: ringBox.start; sweepAngle: Math.max(0.5, ringBox.sweep * ringBox.shown) }
                            }
                        }

                        // Spark travelling along the filled part while charging
                        Rectangle {
                            id: spark
                            property real t: 0
                            readonly property real a: (ringBox.start + ringBox.sweep * Math.max(0.04, ringBox.shown) * t) * Math.PI / 180
                            visible: root.charging && Motion.factor > 0
                            width: root.s(7); height: width; radius: width / 2
                            x: ringBox.cx + ringBox.r * Math.cos(a) - width / 2
                            y: ringBox.cy + ringBox.r * Math.sin(a) - height / 2
                            color: "white"
                            opacity: 0.9 * Math.sin(Math.PI * t)
                            NumberAnimation on t {
                                running: root.charging && root.visible && Motion.factor > 0; loops: Animation.Infinite
                                from: 0; to: 1; duration: 2200; easing.type: Easing.InOutQuad
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: root.s(2)
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(root.pct * 100) + "%"
                                color: ThemeBackend.text
                                font.pixelSize: root.s(28); font.weight: Font.Bold
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.full ? "󰂄" : root.charging ? "󱐋" : "󰁹"
                                font.family: ThemeBackend.iconFont
                                color: root.levelColor
                                font.pixelSize: root.s(14)
                            }
                        }
                    }

                    Column {
                        anchors {
                            left: ringBox.right; leftMargin: root.s(12)
                            right: parent.right; rightMargin: root.s(14)
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: root.s(10)
                        Stat { icon: "󱐋"; label: root.charging ? "Charging at" : "Power draw"; value: root.watts > 0.05 ? root.watts.toFixed(1) + " W" : "—" }
                        Stat {
                            icon: "󰁹"; label: "Energy"
                            value: root.bat && root.bat.energyCapacity > 0 ? root.bat.energy.toFixed(1) + " / " + root.bat.energyCapacity.toFixed(1) + " Wh" : "—"
                        }
                        Stat {
                            icon: "󰣐"; label: "Health"
                            value: root.cell && root.cell.healthSupported ? Math.round(root.cell.healthPercentage) + " %" : "—"
                        }
                        Stat { icon: "󰑓"; label: "Cycles"; value: root.cycles > 0 ? root.cycles : "—" }
                    }
                }

                // ── 24 h graph ────────────────────────────────────────────────
                Item {
                    width: parent.width; height: root.labelH
                    Label { text: "LAST 24 HOURS"; anchors.left: parent.left; anchors.leftMargin: root.s(4) }
                    Label {
                        anchors.right: parent.right; anchors.rightMargin: root.s(4)
                        visible: graph.hoverIdx >= 0
                        text: graph.hoverText
                        color: ThemeBackend.text
                    }
                }
                Rectangle {
                    id: graphCard
                    width: parent.width; height: root.graphH
                    radius: Math.min(ThemeBackend.borderRadius, root.s(20))
                    color: root.card
                    border.color: root.faint
                    clip: true

                    Canvas {
                        id: graph
                        anchors { fill: parent; leftMargin: root.s(10); rightMargin: root.s(10); topMargin: root.s(10); bottomMargin: root.s(22) }
                        readonly property var pts: root.history
                        readonly property real t0: root.historyNow - root.span
                        property color c: root.levelColor
                        property color chg: ThemeBackend.green
                        property color grid: ThemeBackend.text
                        // Mouse position in the graph (-1 = outside) and the value there
                        property real mx: -1
                        readonly property int hoverIdx: {
                            if (mx < 0 || pts.length === 0) return -1;
                            let t = t0 + mx / width * root.span, idx = -1;
                            for (let i = 0; i < pts.length; i++) if (pts[i].t <= t) idx = i;
                            return idx;
                        }
                        readonly property string hoverText: {
                            if (hoverIdx < 0) return "";
                            let t = t0 + mx / width * root.span;
                            let d = new Date(t * 1000);
                            let p = pts[hoverIdx];
                            return Qt.formatTime(d, "hh:mm") + "  ·  " + Math.round(p.v) + "%" + (p.st === 1 ? "  ·  CHARGING" : "");
                        }
                        onPtsChanged: requestPaint()
                        onCChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onMxChanged: requestPaint()

                        function xOf(t) { return Math.max(0, Math.min(width, (t - t0) / root.span * width)); }
                        function yOf(v) { return 3 + (height - 4) * (1 - Math.max(0, Math.min(100, v)) / 100); }

                        onPaint: {
                            let ctx = getContext("2d");
                            ctx.reset();
                            let w = width, h = height;
                            // Grid: 25/50/75 %
                            ctx.strokeStyle = String(grid);
                            ctx.globalAlpha = 0.06;
                            ctx.lineWidth = 1;
                            for (let g = 1; g <= 3; g++) {
                                ctx.beginPath(); ctx.moveTo(0, Math.round(h * g / 4) + 0.5); ctx.lineTo(w, Math.round(h * g / 4) + 0.5); ctx.stroke();
                            }
                            if (pts.length === 0) return;

                            // Step line: UPower records a point when the value changes, it holds until the next one
                            let path = [];
                            let first = pts[0];
                            path.push([xOf(Math.max(first.t, t0)), yOf(first.v)]);
                            for (let i = 1; i < pts.length; i++) {
                                let x = xOf(pts[i].t);
                                path.push([x, yOf(pts[i - 1].v)]);
                                path.push([x, yOf(pts[i].v)]);
                            }
                            path.push([w, yOf(root.pct * 100)]);

                            // Charging periods as green bands
                            ctx.fillStyle = String(chg);
                            ctx.globalAlpha = 0.10;
                            for (let i = 0; i < pts.length; i++) {
                                if (pts[i].st !== 1) continue;
                                let x0 = xOf(pts[i].t), x1 = i + 1 < pts.length ? xOf(pts[i + 1].t) : w;
                                ctx.fillRect(x0, 0, Math.max(1, x1 - x0), h);
                            }

                            // Area under the line
                            let grad = ctx.createLinearGradient(0, 0, 0, h);
                            grad.addColorStop(0, String(Qt.alpha(c, 0.35)));
                            grad.addColorStop(1, String(Qt.alpha(c, 0.0)));
                            ctx.globalAlpha = 1;
                            ctx.fillStyle = grad;
                            ctx.beginPath();
                            ctx.moveTo(path[0][0], h);
                            for (let i = 0; i < path.length; i++) ctx.lineTo(path[i][0], path[i][1]);
                            ctx.lineTo(w, h);
                            ctx.closePath();
                            ctx.fill();

                            ctx.strokeStyle = String(c);
                            ctx.lineWidth = 2;
                            ctx.lineJoin = "round";
                            ctx.beginPath();
                            ctx.moveTo(path[0][0], path[0][1]);
                            for (let i = 1; i < path.length; i++) ctx.lineTo(path[i][0], path[i][1]);
                            ctx.stroke();

                            // Now
                            ctx.fillStyle = String(c);
                            ctx.beginPath(); ctx.arc(w - 1, yOf(root.pct * 100), 3.5, 0, 2 * Math.PI); ctx.fill();

                            // Hover cursor
                            if (hoverIdx >= 0) {
                                ctx.strokeStyle = String(grid);
                                ctx.globalAlpha = 0.35;
                                ctx.lineWidth = 1;
                                ctx.beginPath(); ctx.moveTo(Math.round(mx) + 0.5, 0); ctx.lineTo(Math.round(mx) + 0.5, h); ctx.stroke();
                                ctx.globalAlpha = 1;
                                ctx.fillStyle = String(grid);
                                ctx.beginPath(); ctx.arc(mx, yOf(pts[hoverIdx].v), 3, 0, 2 * Math.PI); ctx.fill();
                            }
                        }

                        HoverHandler {
                            onPointChanged: graph.mx = hovered ? Math.max(0, Math.min(graph.width, point.position.x)) : -1
                            onHoveredChanged: if (!hovered) graph.mx = -1
                        }
                    }

                    Text {
                        anchors.centerIn: graph
                        visible: root.history.length === 0
                        text: "No history yet"; font.pixelSize: root.s(11); color: root.dim
                    }

                    // Time axis
                    Repeater {
                        model: ["-24 h", "-18 h", "-12 h", "-6 h", "now"]
                        Text {
                            required property string modelData
                            required property int index
                            x: graph.x + graph.width * index / 4 - (index === 0 ? 0 : index === 4 ? implicitWidth : implicitWidth / 2)
                            anchors { bottom: parent.bottom; bottomMargin: root.s(5) }
                            text: modelData
                            font.pixelSize: root.s(8)
                            color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.3)
                        }
                    }
                }

                // ── Power profile ─────────────────────────────────────────────
                Item {
                    width: parent.width; height: root.labelH
                    Label { text: "POWER PROFILE"; anchors.left: parent.left; anchors.leftMargin: root.s(4) }
                }
                Rectangle {
                    id: seg
                    width: parent.width; height: root.segH
                    radius: Math.min(ThemeBackend.borderRadius, root.s(20))
                    color: root.card
                    border.color: root.faint

                    readonly property var options: {
                        let o = [
                            { key: PowerProfile.PowerSaver, icon: "󰌪", label: "Saver" },
                            { key: PowerProfile.Balanced, icon: "󰾅", label: "Balanced" }
                        ];
                        if (PowerProfiles.hasPerformanceProfile) o.push({ key: PowerProfile.Performance, icon: "󰓅", label: "Performance" });
                        return o;
                    }
                    readonly property int current: {
                        for (let i = 0; i < options.length; i++) if (options[i].key === PowerProfiles.profile) return i;
                        return 1;
                    }
                    readonly property real inset: root.s(4)
                    readonly property real slot: (width - inset * 2) / options.length

                    // Sliding highlight
                    Rectangle {
                        x: seg.inset + seg.current * seg.slot
                        y: seg.inset
                        width: seg.slot; height: seg.height - seg.inset * 2
                        radius: Math.max(0, seg.radius - seg.inset)
                        color: Qt.alpha(ThemeBackend.blue, 0.18)
                        border.color: Qt.alpha(ThemeBackend.blue, 0.45)
                        Behavior on x { NumberAnimation { duration: Motion.slow; easing.type: Motion.popEasing; easing.overshoot: 1.1 } }
                    }

                    Row {
                        x: seg.inset; anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: seg.options
                            delegate: Item {
                                id: opt
                                required property var modelData
                                required property int index
                                readonly property bool sel: index === seg.current
                                width: seg.slot; height: seg.height - seg.inset * 2
                                Column {
                                    anchors.centerIn: parent
                                    spacing: root.s(2)
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: opt.modelData.icon; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(16)
                                        color: opt.sel ? ThemeBackend.blue : root.dim
                                        Behavior on color { ColorAnimation { duration: Motion.normal } }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: opt.modelData.label; font.pixelSize: root.s(10); font.weight: Font.Medium
                                        color: opt.sel ? ThemeBackend.text : root.dim
                                    }
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: PowerProfiles.profile = opt.modelData.key }
                            }
                        }
                    }
                }

                Text {
                    // 0 = none; the enum itself is not exported to QML
                    visible: root.limited
                    text: "Performance is currently limited (heat or lap detection)"
                    font.pixelSize: root.s(10)
                    color: ThemeBackend.yellow
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

    component Stat: Row {
        id: stat
        property string icon
        property string label
        property string value
        spacing: root.s(8)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.s(16)
            text: stat.icon; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(13)
            color: root.dim
        }
        Column {
            Text { text: stat.label; font.pixelSize: root.s(9); color: root.dim }
            Text { text: stat.value; font.pixelSize: root.s(12); font.weight: Font.Medium; color: ThemeBackend.text }
        }
    }
}
