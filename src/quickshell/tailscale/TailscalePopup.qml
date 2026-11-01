// Tailscale popup: on/off, this device, exit node picker and the tailnet's devices.
// Ported from DAVE-atd/Brain_Shell (src/popups/TailscaleTab.qml), AGPL-3.0 like Serpantinum.
// Opened from the bar module "tailscale" (bar/faces/tailscale) via qs_manager.sh toggle tailscale.
// State lives in TailscaleService; clicking a device copies its IP.
import QtQuick
import Quickshell
import "../"
import "../reusables"

Item {
    id: root
    visible: false
    focus: true

    function s(val) { return Scaler.s(val) }

    readonly property var ts: TailscaleService
    readonly property color card: Qt.alpha(ThemeBackend.surface0, 0.55)
    readonly property color cardHover: Qt.alpha(ThemeBackend.surface1, 0.65)
    readonly property color dim: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.45)
    readonly property color faint: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.06)

    // Main.qml calls startExit(cb) before hiding the popup
    property real intro: 0
    property var exitCallback: null
    function startExit(onFinished) {
        introAnim.stop()
        exitCallback = onFinished
        exitAnim.restart()
    }
    onVisibleChanged: {
        // Poll faster while the popup is open
        ts.fastPoll = visible
        if (visible) { ts.refresh(); forceActiveFocus(); intro = 0; introAnim.restart() }
        else { introAnim.stop(); exitAnim.stop(); intro = 0 }
    }
    NumberAnimation { id: introAnim; target: root; property: "intro"; to: 1; duration: 260; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: exitAnim
        NumberAnimation { target: root; property: "intro"; to: 0; duration: 160; easing.type: Easing.InCubic }
        ScriptAction { script: { if (root.exitCallback) { let cb = root.exitCallback; root.exitCallback = null; cb() } } }
    }

    Keys.onEscapePressed: Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close", "tailscale"])

    function osIcon(os) {
        switch (os) {
            case "linux":   return "󰌽"
            case "windows": return "󰍲"
            case "macOS":   return "󰀵"
            case "android": return "󰀲"
            case "iOS":     return "󰀷"
            default:        return "󰒋"
        }
    }

    function ago(iso) {
        if (!iso || iso.indexOf("0001") === 0) return ""
        var d = (Date.now() - new Date(iso).getTime()) / 1000
        if (d < 3600)  return Math.max(1, Math.round(d / 60)) + " min ago"
        if (d < 86400) return Math.round(d / 3600) + " h ago"
        return Math.round(d / 86400) + " d ago"
    }

    readonly property string statusText: !ts.available ? "tailscaled not reachable"
                                       : ts.busy ? ts.busyLabel
                                       : ts.running ? ts.tailnet + "  ·  " + ts.onlineCount + " online"
                                       : ts.backendState === "NeedsLogin" ? "Not logged in"
                                       : "Off"

    Item {
        anchors.fill: parent
        scale: 0.95 + 0.05 * root.intro
        transformOrigin: ConvexState.origin
        opacity: root.intro
        transform: Translate { y: root.s(20) * (1 - root.intro) }

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
                    spacing: root.s(10)

                    // ── Header + switch ───────────────────────────────────────────────────
                    Item {
                        width: parent.width; height: root.s(34)
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: "Tailscale"; color: ThemeBackend.text; font.pixelSize: root.s(15); font.weight: Font.Bold }
                            Text {
                                text: root.statusText
                                color: ts.running ? Qt.alpha(ThemeBackend.blue, 0.85) : root.dim
                                font.pixelSize: root.s(10)
                            }
                        }
                        Switch {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            checked: ts.running
                            enabled: ts.available && !ts.busy
                            onToggled: ts.toggle()
                        }
                    }

                    // ── This device ───────────────────────────────────────────────────────
                    Rectangle {
                        width: parent.width; height: root.s(62)
                        radius: root.s(ThemeBackend.borderRadius)
                        color: ts.running ? Qt.alpha(ThemeBackend.blue, 0.10) : root.card
                        border.color: ts.running ? Qt.alpha(ThemeBackend.blue, 0.25) : root.faint
                        Behavior on color { ColorAnimation { duration: 200 } }

                        Row {
                            anchors { left: parent.left; leftMargin: root.s(14); verticalCenter: parent.verticalCenter }
                            spacing: root.s(14)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰖂"; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(24)
                                color: ts.running ? ThemeBackend.blue : root.dim
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; spacing: root.s(3)
                                Text { text: ts.selfName || "—"; font.pixelSize: root.s(13); font.weight: Font.Medium; color: ThemeBackend.text }
                                Text {
                                    text: ts.running ? ts.selfIp : "Disconnected"
                                    font.pixelSize: root.s(10); font.family: "JetBrains Mono"
                                    color: ts.running ? ThemeBackend.blue : root.dim
                                }
                            }
                        }

                        CopyHint {
                            anchors { right: parent.right; rightMargin: root.s(14); verticalCenter: parent.verticalCenter }
                            visible: ts.running; value: ts.selfIp
                        }
                    }

                    // ── Exit node ─────────────────────────────────────────────────────────
                    Label { text: "EXIT NODE"; visible: ts.running && ts.exitNodes.length > 0 }

                    Flow {
                        width: parent.width; spacing: root.s(6)
                        visible: ts.running && ts.exitNodes.length > 0

                        ExitChip { label: "None"; icon: "󰅖"; selected: ts.exitNode === ""; ip: ""; usable: true }
                        Repeater {
                            model: ts.exitNodes
                            delegate: ExitChip {
                                required property var modelData
                                label: modelData.name; icon: "󰈀"; ip: modelData.ip
                                selected: modelData.exitNode; usable: modelData.online
                            }
                        }
                    }

                    // ── Devices ───────────────────────────────────────────────────────────
                    Label { text: "DEVICES"; visible: ts.running && ts.peers.length > 0 }

                    Rectangle {
                        width: parent.width
                        height: peerCol.implicitHeight + root.s(8)
                        visible: ts.running && ts.peers.length > 0
                        radius: root.s(ThemeBackend.borderRadius)
                        color: root.card

                        Column {
                            id: peerCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.s(4) }
                            Repeater {
                                model: ts.running ? ts.peers : []
                                delegate: PeerRow {
                                    required property var modelData
                                    width: peerCol.width; peer: modelData
                                }
                            }
                        }
                    }

                    // ── Off / not reachable ───────────────────────────────────────────────
                    Item {
                        width: parent.width; height: root.s(180)
                        visible: !ts.running
                        Column {
                            anchors.centerIn: parent; spacing: root.s(10)
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰖂"; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(40)
                                color: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.15)
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: !ts.available ? "Tailscale is not running"
                                    : ts.backendState === "NeedsLogin" ? "Log in with: tailscale up"
                                    : "Tailscale is off"
                                font.pixelSize: root.s(12)
                                color: root.dim
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

    // Copy glyph that briefly turns into a check after copying `value`
    component CopyHint: Text {
        id: ch
        property string value: ""
        property bool done: false
        text: done ? "󰄬" : "󰆏"
        font.family: ThemeBackend.iconFont
        font.pixelSize: root.s(14)
        color: done ? ThemeBackend.blue : chH.hovered ? ThemeBackend.text : root.dim
        Behavior on color { ColorAnimation { duration: 150 } }
        Timer { id: chT; interval: 1200; onTriggered: ch.done = false }
        HoverHandler { id: chH; cursorShape: Qt.PointingHandCursor }
        MouseArea {
            anchors.fill: parent; anchors.margins: -root.s(6)
            onClicked: { ts.copy(ch.value); ch.done = true; chT.restart() }
        }
    }

    component ExitChip: Rectangle {
        id: chip
        property string label
        property string icon
        property string ip
        property bool selected
        property bool usable
        height: root.s(28); radius: height / 2
        width: chipRow.implicitWidth + root.s(20)
        opacity: usable ? 1 : 0.4
        color: selected ? Qt.alpha(ThemeBackend.blue, 0.20)
             : cH.hovered ? root.cardHover
             : root.card
        border.color: selected ? Qt.alpha(ThemeBackend.blue, 0.45) : root.faint
        Behavior on color { ColorAnimation { duration: 150 } }

        Row {
            id: chipRow; anchors.centerIn: parent; spacing: root.s(6)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(12)
                color: chip.selected ? ThemeBackend.blue : root.dim
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label; font.pixelSize: root.s(11); font.weight: Font.Medium
                color: chip.selected ? ThemeBackend.blue : ThemeBackend.text
            }
        }

        HoverHandler { id: cH; cursorShape: chip.usable && !chip.selected ? Qt.PointingHandCursor : Qt.ArrowCursor }
        MouseArea {
            anchors.fill: parent
            enabled: chip.usable && !chip.selected && !ts.busy
            onClicked: ts.setExitNode(chip.ip, chip.label)
        }
    }

    component PeerRow: Rectangle {
        id: pRow
        required property var peer
        height: root.s(44)
        radius: root.s(ThemeBackend.borderRadius) - root.s(4)
        color: pH.hovered ? root.cardHover : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }

        Row {
            anchors { left: parent.left; leftMargin: root.s(10); verticalCenter: parent.verticalCenter }
            spacing: root.s(12)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: root.s(18)
                text: root.osIcon(pRow.peer.os); font.family: ThemeBackend.iconFont; font.pixelSize: root.s(16)
                color: pRow.peer.online ? ThemeBackend.text : root.dim
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter; spacing: root.s(2)
                Text {
                    text: pRow.peer.name + (pRow.peer.exitNode ? "  · exit node" : "")
                    width: pRow.width - root.s(100); elide: Text.ElideRight
                    font.pixelSize: root.s(12)
                    color: pRow.peer.online ? ThemeBackend.text : root.dim
                }
                Text {
                    text: pRow.peer.ip + (pRow.peer.online ? "" : "  ·  " + root.ago(pRow.peer.lastSeen))
                    font.pixelSize: root.s(9); font.family: "JetBrains Mono"
                    color: root.dim
                }
            }
        }

        Row {
            anchors { right: parent.right; rightMargin: root.s(12); verticalCenter: parent.verticalCenter }
            spacing: root.s(12)
            CopyHint {
                anchors.verticalCenter: parent.verticalCenter
                value: pRow.peer.ip
                opacity: pH.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: root.s(8); height: width; radius: width / 2
                color: pRow.peer.online ? ThemeBackend.green : Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.18)
            }
        }

        HoverHandler { id: pH }
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
        opacity: !enabled ? 0.6 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            id: knob
            width: root.s(18); height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? sw.width - width - root.s(3) : root.s(3)
            color: "white"
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
            // Pulse while tailscale up/down runs
            SequentialAnimation on opacity {
                running: ts.busy; loops: Animation.Infinite
                onRunningChanged: if (!running) knob.opacity = 1
                NumberAnimation { to: 0.3; duration: 500 }
                NumberAnimation { to: 1.0; duration: 500 }
            }
        }
        HoverHandler { id: swHov; cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; enabled: sw.enabled; onClicked: sw.toggled() }
    }
}
