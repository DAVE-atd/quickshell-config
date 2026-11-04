// Security popup: ClamAV real-time protection, system scan, detections and known CVEs (vulnix).
// Ported from DAVE-atd/Brain_Shell (src/popups/ClamavPopup.qml), AGPL-3.0 like Serpantinum.
// Opened from the bar module "security" (bar/faces/security) via qs_manager.sh toggle security.
import QtQuick
import QtQuick.Shapes
import Quickshell
import "../"
import "../reusables"

Item {
    id: root
    visible: false
    focus: true

    function s(val) { return Scaler.s(val) }

    readonly property color card: Qt.alpha(ThemeBackend.surface0, 0.55)
    readonly property color cardHover: Qt.alpha(ThemeBackend.surface1, 0.65)

    // Main.qml calls startExit(cb) before hiding the popup
    property real intro: 0
    property var exitCallback: null
    function startExit(onFinished) {
        introAnim.stop()
        exitCallback = onFinished
        exitAnim.restart()
    }
    onVisibleChanged: {
        // Opening the popup counts as having seen new detections (bar icon back to normal)
        if (visible) { ClamavService.unseen = false; forceActiveFocus(); intro = 0; introAnim.restart() }
        else { introAnim.stop(); exitAnim.stop(); intro = 0 }
    }
    NumberAnimation { id: introAnim; target: root; property: "intro"; to: 1; duration: Motion.open; easing.type: Motion.openEasing }
    SequentialAnimation {
        id: exitAnim
        NumberAnimation { target: root; property: "intro"; to: 0; duration: Motion.close; easing.type: Motion.closeEasing }
        ScriptAction { script: { if (root.exitCallback) { let cb = root.exitCallback; root.exitCallback = null; cb() } } }
    }

    Keys.onEscapePressed: Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close", "security"])

    readonly property var cs: ClamavService
    readonly property var vx: VulnixService

    function sevColor(score) {
        return score >= 9 ? ThemeBackend.red : score >= 7 ? ThemeBackend.peach : score >= 4 ? ThemeBackend.yellow : ThemeBackend.subtext0
    }
    readonly property color protColor: !cs.enabled ? ThemeBackend.subtext0
                                     : (cs.unseen || cs.scanState === "infected") ? ThemeBackend.red
                                     : ThemeBackend.blue

    // Clock for "x min ago" and the scan timer
    property real now: Date.now()
    Timer { interval: 1000; repeat: true; running: root.visible; triggeredOnStart: true; onTriggered: root.now = Date.now() }

    function ago(ms) {
        if (!ms) return "—"
        var d = Math.max(0, (now - ms) / 1000)
        if (d < 60)    return "just now"
        if (d < 3600)  return Math.floor(d / 60) + " min ago"
        if (d < 86400) return Math.floor(d / 3600) + " h ago"
        return Math.floor(d / 86400) + " d ago"
    }
    function clock(ms) {
        var t = Math.max(0, Math.floor(ms / 1000))
        var h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), sec = t % 60
        var mm = (m < 10 && h > 0 ? "0" : "") + m, ss = (sec < 10 ? "0" : "") + sec
        return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
    }

    readonly property string statusText: {
        if (cs.busy)     return cs.enabled ? "Switching on…" : "Switching off…"
        if (!cs.enabled) return "Real-time protection is off"
        if (cs.unseen)   return "Threat detected"
        if (cs.scanning) return "Scanning your files…"
        return cs.monitoring ? "Watching ~/Downloads" : "Starting…"
    }


    Item {
        anchors.fill: parent
        scale: ConvexState.active ? 1 : 0.95 + 0.05 * root.intro   // convex: Main.qml slides it out of the bar
        transformOrigin: ConvexState.origin
        opacity: ConvexState.active ? 1 : root.intro
        transform: Translate { y: ConvexState.active ? 0 : root.s(20) * (1 - root.intro) }

        Rectangle {
            anchors.fill: parent
            radius: ThemeBackend.borderRadius
            // Convex bar style: square corners on sides attached to the bar or frame
            topLeftRadius: ConvexState.tl(radius)
            topRightRadius: ConvexState.tr(radius)
            bottomLeftRadius: ConvexState.bl(radius)
            bottomRightRadius: ConvexState.br(radius)
            color: Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
            clip: true

            WallpaperBlur {
                z: -1
                anchors.fill: parent
                topLeftRadius: parent.topLeftRadius
                topRightRadius: parent.topRightRadius
                bottomLeftRadius: parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius
            }

            Flickable {
                id: flick
                anchors { fill: parent; margins: root.s(16) }
                contentHeight: content.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: content
                    width: flick.width
                    spacing: s(10)

                    // ── Header + switch ───────────────────────────────────────────────────
                    Item {
                        width: parent.width; height: s(34)
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: "ClamAV"; color: ThemeBackend.text; font.pixelSize: s(15); font.weight: Font.Bold }
                            Text {
                                text: root.statusText
                                color: Qt.rgba(root.protColor.r, root.protColor.g, root.protColor.b, 0.85)
                                font.pixelSize: s(10)
                            }
                        }
                        Switch {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            checked: cs.enabled
                            onToggled: { cs.setEnabled(!cs.enabled) }
                        }
                    }

                    // ── Hero: shield + stats ──────────────────────────────────────────────
                    Rectangle {
                        width: parent.width; height: s(150)
                        radius: s(ThemeBackend.borderRadius)
                        color: root.card
                        border.color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)
                        clip: true

                        Item {
                            id: emblem
                            width: s(126); height: width
                            anchors { left: parent.left; leftMargin: s(14); verticalCenter: parent.verticalCenter }

                            // Soft glow in the status colour, pulsing while active
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                opacity: cs.enabled ? glow.v : 0.25
                                ShapePath {
                                    strokeColor: "transparent"
                                    fillGradient: RadialGradient {
                                        centerX: emblem.width / 2; centerY: emblem.height / 2
                                        focalX: centerX; focalY: centerY
                                        centerRadius: emblem.width / 2
                                        GradientStop { position: 0.0; color: Qt.rgba(root.protColor.r, root.protColor.g, root.protColor.b, 0.28) }
                                        GradientStop { position: 1.0; color: "transparent" }
                                    }
                                    PathAngleArc { centerX: emblem.width / 2; centerY: emblem.height / 2; radiusX: emblem.width / 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
                                }
                            }
                            QtObject {
                                id: glow
                                property real v: 0.6
                                property var anim: SequentialAnimation {
                                    running: cs.enabled && root.visible; loops: Animation.Infinite
                                    NumberAnimation { target: glow; property: "v"; to: 1.0;  duration: 1800; easing.type: Easing.InOutSine }
                                    NumberAnimation { target: glow; property: "v"; to: 0.5; duration: 1800; easing.type: Easing.InOutSine }
                                }
                            }

                            // Thin ring; a radar sweep runs around it during a scan
                            Rectangle {
                                anchors.fill: parent; anchors.margins: s(10)
                                radius: width / 2
                                color: "transparent"
                                border.width: s(2)
                                border.color: Qt.rgba(root.protColor.r, root.protColor.g, root.protColor.b, cs.enabled ? 0.35 : 0.15)
                            }
                            Shape {
                                id: sweep
                                anchors.fill: parent; anchors.margins: s(10)
                                preferredRendererType: Shape.CurveRenderer
                                visible: cs.scanning
                                RotationAnimation on rotation { running: cs.scanning && root.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 1600 }
                                ShapePath {
                                    strokeColor: root.protColor; strokeWidth: s(3); capStyle: ShapePath.RoundCap
                                    fillColor: "transparent"
                                    PathAngleArc { centerX: sweep.width / 2; centerY: sweep.height / 2; radiusX: sweep.width / 2 - s(1); radiusY: radiusX; startAngle: -90; sweepAngle: 70 }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: !cs.enabled ? "󰦞" : (cs.unseen || cs.scanState === "infected") ? "󰻌" : cs.scanning ? "󰶚" : "󰕥"
                                color: root.protColor
                                font.pixelSize: s(46)
                                Behavior on color { ColorAnimation { duration: Motion.normal } }
                            }
                        }

                        Column {
                            anchors { left: emblem.right; leftMargin: s(14); right: parent.right; rightMargin: s(14); verticalCenter: parent.verticalCenter }
                            spacing: s(9)
                            Stat { icon: "󰉍"; label: "Real-time"; value: !cs.enabled ? "Off" : cs.monitoring ? "~/Downloads" : "Starting…" }
                            Stat { icon: "󰪩"; label: "Signatures"; value: cs.sigVersion !== "" ? "daily " + cs.sigVersion : "—" }
                            Stat { icon: "󰚰"; label: "Updated"; value: root.ago(cs.sigDate) }
                            Stat {
                                icon: "󰅐"; label: "Last scan"
                                value: cs.scanning ? "running" : !cs.scanEnded ? "never (this session)"
                                     : root.ago(cs.scanEnded) + (cs.scanState === "infected" ? " · threats" : cs.scanState === "clean" ? " · clean" : "")
                            }
                        }
                    }

                    // ── System scan ───────────────────────────────────────────────────────
                    Label { text: "SYSTEM SCAN" }

                    Rectangle {
                        width: parent.width; height: s(84)
                        radius: s(ThemeBackend.borderRadius)
                        color: root.card

                        Column {
                            anchors { left: parent.left; leftMargin: s(14); right: scanBtn.left; rightMargin: s(12); verticalCenter: parent.verticalCenter }
                            spacing: s(4)
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                font.pixelSize: s(12); font.weight: Font.Medium; color: ThemeBackend.text
                                text: cs.scanning ? "Scanning · " + root.clock(root.now - cs.scanStarted)
                                    : cs.scanState === "infected" ? cs.scanFound.length + " threat" + (cs.scanFound.length > 1 ? "s" : "") + " found"
                                    : cs.scanState === "clean" ? "No threats found · " + root.clock(cs.scanEnded - cs.scanStarted)
                                    : cs.scanState === "cancelled" ? "Scan cancelled"
                                    : cs.scanState === "error" ? "Scan failed"
                                    : "Home, /share and /data"
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                font.pixelSize: s(10); color: ThemeBackend.subtext0
                                text: cs.scanning ? (cs.scanFound.length > 0 ? cs.scanFound.length + " found so far" : "/home · /share · /data")
                                    : cs.scanErrors > 0 && cs.scanState !== "" ? cs.scanErrors + " files could not be read"
                                    : cs.enabled ? "Fast, multi-threaded via clamd" : "clamd is off: slower single scan"
                            }
                            // Indeterminate progress while scanning
                            Item {
                                width: parent.width; height: s(4)
                                visible: cs.scanning
                                clip: true
                                Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.08) }
                                Rectangle {
                                    id: bar
                                    width: parent.width * 0.35; height: parent.height; radius: height / 2
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: "transparent" }
                                        GradientStop { position: 1; color: root.protColor }
                                    }
                                    NumberAnimation on x {
                                        running: cs.scanning && root.visible; loops: Animation.Infinite
                                        from: -bar.width; to: bar.parent.width; duration: 1400; easing.type: Easing.InOutQuad
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: scanBtn
                            anchors { right: parent.right; rightMargin: s(14); verticalCenter: parent.verticalCenter }
                            width: s(118); height: s(40); radius: height / 2
                            color: cs.scanning ? (scanHov.hovered ? root.cardHover : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)) : "transparent"
                            gradient: cs.scanning ? null : grad
                            Gradient {
                                id: grad
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Qt.darker(ThemeBackend.blue, 1.6) }
                                GradientStop { position: 1; color: ThemeBackend.blue }
                            }
                            scale: scanHov.pressed ? 0.96 : 1
                            Behavior on scale { NumberAnimation { duration: Motion.fast } }
                            Row {
                                anchors.centerIn: parent; spacing: s(7)
                                Text {
                                    text: cs.scanning ? "󰜺" : "󱉶"
                                    font.pixelSize: s(15); anchors.verticalCenter: parent.verticalCenter
                                    color: cs.scanning ? ThemeBackend.text : ThemeBackend.base
                                }
                                Text {
                                    text: cs.scanning ? "Cancel" : "Scan now"
                                    font.pixelSize: s(12); font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter
                                    color: cs.scanning ? ThemeBackend.text : ThemeBackend.base
                                }
                            }
                            HoverHandler { id: scanHov; cursorShape: Qt.PointingHandCursor; property bool pressed: scanMa.pressed }
                            MouseArea {
                                id: scanMa
                                anchors.fill: parent
                                onClicked: { cs.scanning ? cs.cancelScan() : cs.startScan() }
                            }
                        }
                    }

                    // ── Detections ────────────────────────────────────────────────────────
                    Label { text: "DETECTIONS" }

                    Rectangle {
                        width: parent.width
                        height: cs.detections.length === 0 ? s(52) : detList.implicitHeight + s(12)
                        radius: s(ThemeBackend.borderRadius)
                        color: root.card

                        Row {
                            visible: cs.detections.length === 0
                            anchors.centerIn: parent; spacing: s(8)
                            Text { text: "󰄬"; font.pixelSize: s(14); color: ThemeBackend.blue; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "No threats detected"; font.pixelSize: s(11); color: ThemeBackend.subtext0; anchors.verticalCenter: parent.verticalCenter }
                        }

                        Column {
                            id: detList
                            visible: cs.detections.length > 0
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: s(6) }
                            Repeater {
                                model: cs.detections.slice(0, 4)
                                delegate: Item {
                                    required property var modelData
                                    width: detList.width; height: s(44)
                                    Rectangle {
                                        id: dot
                                        width: s(28); height: width; radius: width / 2
                                        anchors { left: parent.left; leftMargin: s(6); verticalCenter: parent.verticalCenter }
                                        color: Qt.rgba(ThemeBackend.red.r, ThemeBackend.red.g, ThemeBackend.red.b, 0.15)
                                        Text { anchors.centerIn: parent; text: "󱎶"; font.pixelSize: s(14); color: ThemeBackend.red }
                                    }
                                    Column {
                                        anchors { left: dot.right; leftMargin: s(10); right: when.left; rightMargin: s(8); verticalCenter: parent.verticalCenter }
                                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; font.pixelSize: s(12); font.weight: Font.Medium; color: ThemeBackend.text }
                                        Text { width: parent.width; elide: Text.ElideMiddle; text: modelData.path; font.pixelSize: s(10); color: ThemeBackend.subtext0 }
                                    }
                                    Column {
                                        id: when
                                        anchors { right: parent.right; rightMargin: s(6); verticalCenter: parent.verticalCenter }
                                        Text { anchors.right: parent.right; text: root.ago(modelData.time); font.pixelSize: s(10); color: ThemeBackend.subtext0 }
                                        Text { anchors.right: parent.right; text: modelData.source; font.pixelSize: s(9); color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.3) }
                                    }
                                }
                            }
                        }
                    }

                    // ── Vulnerabilities (vulnix) ──────────────────────────────────────────
                    Item {
                        width: parent.width; height: vulnLabel.implicitHeight
                        visible: vx.available
                        Label { id: vulnLabel; text: "VULNERABILITIES" }
                        Row {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: s(6)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: s(9); color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.35)
                                text: vx.running ? "checking…" : vx.failed ? "check failed" : vx.checkedAt ? "checked " + root.ago(vx.checkedAt) : ""
                            }
                            Text {
                                id: recheck
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰑐"; font.pixelSize: s(12)
                                color: recheckHov.hovered ? ThemeBackend.blue : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.45)
                                RotationAnimation on rotation {
                                    running: vx.running && root.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 1200
                                    onRunningChanged: if (!running) recheck.rotation = 0
                                }
                                HoverHandler { id: recheckHov; cursorShape: Qt.PointingHandCursor }
                                MouseArea { anchors.fill: parent; anchors.margins: -s(4); onClicked: { vx.check() } }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        visible: vx.available
                        height: vulnCol.implicitHeight + s(16)
                        radius: s(ThemeBackend.borderRadius)
                        color: root.card

                        Column {
                            id: vulnCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: s(8) }
                            spacing: s(4)

                            // Summary: count + severity chips
                            Item {
                                width: parent.width; height: s(40)
                                Text {
                                    id: vulnCount
                                    anchors { left: parent.left; leftMargin: s(6); verticalCenter: parent.verticalCenter }
                                    text: vx.packages.length === 0 && !vx.running ? "󰄬" : vx.packages.length
                                    font.pixelSize: s(24); font.weight: Font.Bold
                                    color: vx.packages.length === 0 ? ThemeBackend.blue : vx.critical > 0 ? ThemeBackend.red : ThemeBackend.text
                                }
                                Column {
                                    anchors { left: vulnCount.right; leftMargin: s(10); right: chips.left; rightMargin: s(8); verticalCenter: parent.verticalCenter }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        font.pixelSize: s(12); font.weight: Font.Medium; color: ThemeBackend.text
                                        text: vx.packages.length === 0
                                            ? (vx.running && !vx.checkedAt ? "Checking system packages…" : "No known vulnerabilities")
                                            : "package" + (vx.packages.length > 1 ? "s" : "") + " with known CVEs"
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        font.pixelSize: s(10); color: ThemeBackend.subtext0
                                        text: "In the running system · may include false alarms"
                                    }
                                }
                                Row {
                                    id: chips
                                    anchors { right: parent.right; rightMargin: s(4); verticalCenter: parent.verticalCenter }
                                    spacing: s(5)
                                    Chip { visible: vx.critical > 0; text: vx.critical + " critical"; tint: ThemeBackend.red }
                                    Chip { visible: vx.high > 0; text: vx.high + " high"; tint: root.sevColor(7) }
                                }
                            }

                            ListView {
                                id: vulnList
                                width: parent.width
                                visible: count > 0
                                readonly property int rowH: s(40)
                                property bool expanded: false
                                model: vx.packages.slice(0, expanded ? vx.packages.length : 3)
                                height: Math.min(count, expanded ? 7 : 3) * rowH
                                interactive: expanded
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                delegate: Rectangle {
                                    required property var modelData
                                    width: vulnList.width; height: vulnList.rowH
                                    radius: s(8)
                                    color: rowHov.hovered ? root.cardHover : "transparent"
                                    Rectangle {
                                        id: badge
                                        width: s(34); height: s(22); radius: height / 2
                                        anchors { left: parent.left; leftMargin: s(4); verticalCenter: parent.verticalCenter }
                                        readonly property color c: root.sevColor(modelData.score)
                                        color: Qt.rgba(c.r, c.g, c.b, 0.16)
                                        Text { anchors.centerIn: parent; text: modelData.score ? modelData.score.toFixed(1) : "?"; font.pixelSize: s(10); font.weight: Font.Bold; color: badge.c }
                                    }
                                    Column {
                                        anchors { left: badge.right; leftMargin: s(10); right: ignoreBtn.left; rightMargin: s(6); verticalCenter: parent.verticalCenter }
                                        Text {
                                            width: parent.width; elide: Text.ElideRight; font.pixelSize: s(12); font.weight: Font.Medium; color: ThemeBackend.text
                                            text: modelData.pname + "  " + modelData.versions.join(", ")
                                        }
                                        Text {
                                            width: parent.width; elide: Text.ElideRight; font.pixelSize: s(10); color: ThemeBackend.subtext0
                                            text: modelData.cves.length + " CVE" + (modelData.cves.length > 1 ? "s" : "") + " · " + modelData.top
                                        }
                                    }
                                    Text {
                                        id: ignoreBtn
                                        anchors { right: parent.right; rightMargin: s(8); verticalCenter: parent.verticalCenter }
                                        visible: rowHov.hovered
                                        text: "󰈉"; font.pixelSize: s(14)
                                        color: ignHov.hovered ? ThemeBackend.text : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.4)
                                        HoverHandler { id: ignHov; cursorShape: Qt.PointingHandCursor }
                                        MouseArea { anchors.fill: parent; anchors.margins: -s(4); z: 1; onClicked: { vx.ignore(modelData.pname) } }
                                    }
                                    HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }
                                    // Click: details of the worst CVE on nvd.nist.gov
                                    MouseArea { anchors { fill: parent; rightMargin: s(30) } onClicked: { vx.openCve(modelData.top) } }
                                }
                            }

                            Text {
                                visible: vx.packages.length > 3
                                anchors.horizontalCenter: parent.horizontalCenter
                                topPadding: s(2); bottomPadding: s(2)
                                text: vulnList.expanded ? "Show less" : "Show all " + vx.packages.length
                                font.pixelSize: s(10); font.weight: Font.Medium
                                color: moreHov.hovered ? ThemeBackend.blue : ThemeBackend.subtext0
                                HoverHandler { id: moreHov; cursorShape: Qt.PointingHandCursor }
                                MouseArea { anchors.fill: parent; onClicked: { vulnList.expanded = !vulnList.expanded } }
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
        property alias text: chipText.text
        property color tint: ThemeBackend.text
        width: chipText.implicitWidth + root.s(14); height: root.s(20); radius: height / 2
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.15)
        Text { id: chipText; anchors.centerIn: parent; font.pixelSize: root.s(9); font.weight: Font.Bold; color: parent.tint }
    }

    component Stat: Row {
        property string icon
        property string label
        property string value
        spacing: root.s(8)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.s(16)
            text: parent.icon; font.pixelSize: root.s(13)
            color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.45)
        }
        Column {
            Text { text: parent.parent.label; font.pixelSize: root.s(9); color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.45) }
            Text { text: parent.parent.value; font.pixelSize: root.s(12); font.weight: Font.Medium; color: ThemeBackend.text }
        }
    }

    component Switch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled()
        width: root.s(44); height: root.s(24); radius: height / 2
        color: checked ? (swHov.hovered ? Qt.lighter(ThemeBackend.blue, 1.1) : ThemeBackend.blue)
                       : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, swHov.hovered ? 0.15 : 0.1)
        border.color: checked ? Qt.darker(ThemeBackend.blue, 1.2) : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.2)
        border.width: 1
        opacity: cs.busy ? 0.75 : 1
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Rectangle {
            width: root.s(18); height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? sw.width - width - root.s(3) : root.s(3)
            color: "white"
            Behavior on x { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack } }
        }
        HoverHandler { id: swHov; cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; onClicked: sw.toggled() }
    }
}
