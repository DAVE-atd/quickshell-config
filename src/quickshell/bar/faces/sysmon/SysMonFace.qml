import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "../../../reusables"
import "../../../"

Item {
    id: root

    property var module: null
    property var widget: module

    property string orientation: (activeTarget && activeTarget.orientation !== undefined) ? activeTarget.orientation : "horizontal"
    readonly property bool isVertical: orientation === "vertical"

    readonly property var activeTarget: widget || module
    readonly property bool isCompact: activeTarget ? activeTarget.isCompact : false
    readonly property var barWindow: activeTarget ? activeTarget.barWindow : null

    property int configRevision: 0

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() { root.configRevision++; }
        function onRawSettingsChanged() { root.configRevision++; }
    }

    property string rawStyle: {
        if (widget && widget !== root && widget.sysmonStyle !== undefined) return widget.sysmonStyle;
        if (module && module.sysmonStyle !== undefined) return module.sysmonStyle;
        let dummy = configRevision;
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) {
            let bs = Config.rawSettings.bar;
            if (bs.sysmonStyle) return bs.sysmonStyle;
            if (bs.sysmon && bs.sysmon.style) return bs.sysmon.style;
        }
        return "gauge";
    }

    // Aussehen nach SystemMonitorPlus (DMS-Plugin von Dadangdut33, MIT): "gauge" = Icon im
    // Tacho-Ring, "bar" = Icon über Fortschrittsbalken, "plain" = nur Icon + Wert.
    // Alte Werte ("wave", "circle") landen bei "gauge".
    readonly property string look: (rawStyle === "bar" || rawStyle === "plain") ? rawStyle : "gauge"

    property bool showText: {
        if (widget && widget !== root && widget.sysmonShowText !== undefined) return widget.sysmonShowText;
        if (module && module.sysmonShowText !== undefined) return module.sysmonShowText;
        let dummy = configRevision;
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) {
            let bs = Config.rawSettings.bar;
            if (bs.sysmonShowText !== undefined) return Boolean(bs.sysmonShowText);
        }
        return true;
    }

    property var activeStats: {
        if (widget && widget !== root && widget.sysmonStats !== undefined) return widget.sysmonStats;
        if (module && module.sysmonStats !== undefined) return module.sysmonStats;
        let dummy = configRevision;
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) {
            let bs = Config.rawSettings.bar;
            if (Array.isArray(bs.sysmonStats)) return bs.sysmonStats;
            if (bs.sysmon && Array.isArray(bs.sysmon.stats)) return bs.sysmon.stats;
            if (bs.sysmonShowCpu !== undefined || bs.sysmonShowRam !== undefined || bs.sysmonShowTemp !== undefined || bs.sysmonShowDisk !== undefined) {
                let stats = [];
                if (bs.sysmonShowCpu !== false) stats.push("cpu");
                if (bs.sysmonShowRam !== false) stats.push("ram");
                if (bs.sysmonShowTemp !== false) stats.push("temp");
                if (bs.sysmonShowDisk === true) stats.push("disk");
                return stats;
            }
        }
        return ["cpu", "ram", "temp"];
    }

    property bool showLayout: (!barWindow || (root.activeTarget && root.activeTarget.isPreview)) ? true : false
    property int circleSize: barWindow ? barWindow.cs(isCompact ? 22 : 28) : (isCompact ? 22 : 28)

    property bool isSysVisible: (!activeTarget || activeTarget.moduleActive) && showLayout
    property color basePrimary: (ThemeBackend.primary !== undefined && ThemeBackend.primary !== "") ? ThemeBackend.primary : ThemeBackend.mauve

    property bool isSubscribed: false

    function updateSubscription() {
        if (isSysVisible && !isSubscribed) {
            isSubscribed = true;
            SysData.subscribe();
        } else if (!isSysVisible && isSubscribed) {
            isSubscribed = false;
            SysData.unsubscribe();
        }
    }

    Component.onCompleted: updateSubscription()
    Component.onDestruction: {
        if (isSubscribed) {
            isSubscribed = false;
            SysData.unsubscribe();
        }
    }
    onIsSysVisibleChanged: updateSubscription()

    readonly property real layoutLength: isVertical ? sysLayout.implicitHeight : sysLayout.implicitWidth
    property real targetLength: ((!activeTarget || activeTarget.moduleActive) && layoutLength > 0) ? (layoutLength + (barWindow ? barWindow.cs(isCompact ? 8 : 10) : (isCompact ? 8 : 10))) : 0
    property bool isFaceVisible: showLayout && targetLength > 0

    function syncImplicitSize() {
        let cross = module ? module.thickness : (parent ? (isVertical ? parent.width : parent.height) : 0);
        implicitWidth = isVertical ? cross : targetLength;
        implicitHeight = isVertical ? targetLength : cross;
    }

    onTargetLengthChanged: syncImplicitSize()
    onIsVerticalChanged: syncImplicitSize()
    onModuleChanged: syncImplicitSize()
    onParentChanged: syncImplicitSize()

    Timer {
        running: true
        interval: 0
        onTriggered: root.syncImplicitSize()
    }

    Timer {
        running: (!activeTarget || activeTarget.moduleActive) && barWindow && barWindow.isStartupReady && barWindow.isDataReady && !root.showLayout
        interval: 100
        onTriggered: root.showLayout = true
    }

    transform: Translate {
        x: (root.isVertical || root.showLayout) ? 0 : (barWindow ? barWindow.cs(60) : 60)
        y: (!root.isVertical || root.showLayout) ? 0 : (barWindow ? barWindow.cs(60) : 60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
        Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    function cs(v) { return barWindow ? barWindow.cs(v) : v; }

    // Schwellen wie im Plugin: [Warnung, Gefahr]
    readonly property var thresholds: ({ "cpu": [60, 80], "ram": [75, 90], "temp": [70, 85], "disk": [80, 90] })

    FontMetrics {
        id: valueMetrics
        font.pixelSize: Math.round(root.cs(root.isCompact ? 9 : 10.5))
        font.family: (ThemeBackend.fontFamily !== undefined && ThemeBackend.fontFamily !== "") ? ThemeBackend.fontFamily : "sans-serif"
    }

    component SysMonMetric: Row {
        id: metric
        property string statType: ""
        property real value: 0
        property string icon: ""
        property bool initAnimTrigger: (!barWindow || !!(root.activeTarget && root.activeTarget.isPreview))

        readonly property real safeValue: isNaN(value) ? 0 : value
        readonly property color accentColor: {
            let t = root.thresholds[statType];
            if (t && safeValue >= t[1]) return ThemeBackend.red;
            if (t && safeValue >= t[0]) return ThemeBackend.yellow;
            return root.basePrimary;
        }
        readonly property color trackColor: Qt.alpha(accentColor, 0.18)

        property real fillRatio: initAnimTrigger ? Math.max(0, Math.min(1, safeValue / 100)) : 0
        Behavior on fillRatio { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

        spacing: root.cs(root.isCompact ? 3 : 4)

        Timer {
            running: (!activeTarget || activeTarget.moduleActive) && root.showLayout && !initAnimTrigger
            interval: 150
            onTriggered: initAnimTrigger = true
        }

        opacity: initAnimTrigger ? 1.0 : 0.0
        transform: Translate {
            x: (!root.isVertical || initAnimTrigger) ? 0 : root.cs(15)
            y: (root.isVertical || initAnimTrigger) ? 0 : root.cs(15)
            Behavior on x { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } }
            Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } }
        }
        Behavior on opacity { NumberAnimation { duration: Motion.ultraSlow; easing.type: Easing.OutCubic } }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: root.look === "gauge" ? root.circleSize : visual.implicitWidth
            implicitHeight: root.circleSize

            // Tacho-Ring: 270 Grad, unten offen
            Shape {
                id: gauge
                visible: root.look === "gauge"
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                readonly property real stroke: root.cs(2.4)
                readonly property real r: Math.max(1, Math.min(width, height) / 2 - stroke / 2)

                ShapePath {
                    strokeColor: metric.trackColor
                    strokeWidth: gauge.stroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: gauge.width / 2; centerY: gauge.height / 2
                        radiusX: gauge.r; radiusY: gauge.r
                        startAngle: 135; sweepAngle: 270
                    }
                }
                ShapePath {
                    strokeColor: metric.fillRatio > 0.005 ? metric.accentColor : "transparent"
                    strokeWidth: gauge.stroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: gauge.width / 2; centerY: gauge.height / 2
                        radiusX: gauge.r; radiusY: gauge.r
                        startAngle: 135; sweepAngle: 270 * metric.fillRatio
                    }
                }
            }

            Column {
                id: visual
                anchors.centerIn: parent
                spacing: root.cs(2)

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: metric.icon
                    font.pixelSize: Math.round(root.cs(root.look === "gauge" ? (root.isCompact ? 10 : 12) : (root.isCompact ? 12 : 14)))
                    font.family: ThemeBackend.iconFont
                    color: metric.accentColor
                }

                Rectangle {
                    visible: root.look === "bar"
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: root.cs(root.isCompact ? 18 : 22)
                    implicitHeight: root.cs(root.isCompact ? 4 : 5)
                    radius: height / 2
                    color: metric.trackColor
                    clip: true

                    Rectangle {
                        width: parent.width * metric.fillRatio
                        height: parent.height
                        radius: parent.radius
                        color: metric.accentColor
                    }
                }
            }
        }

        Text {
            visible: root.showText && !root.isVertical
            anchors.verticalCenter: parent.verticalCenter
            // feste Breite, sonst wandert die Leiste bei jedem Ziffernwechsel
            width: Math.ceil(valueMetrics.advanceWidth(metric.statType === "temp" ? "100°" : "100%"))
            text: Math.round(metric.safeValue) + (metric.statType === "temp" ? "°" : "%")
            font: valueMetrics.font
            color: (ThemeBackend.text !== undefined && ThemeBackend.text !== "") ? ThemeBackend.text : "#ffffff"
        }
    }

    AxisFlow {
        id: sysLayout
        vertical: root.isVertical
        anchors.centerIn: parent
        spacing: root.cs(root.isCompact ? 6 : 8)

        Repeater {
            model: root.activeStats

            SysMonMetric {
                statType: modelData
                value: {
                    if (statType === "cpu") return SysData.cpu;
                    if (statType === "ram") return SysData.ramPercent;
                    if (statType === "temp") return SysData.temp;
                    if (statType === "disk") return SysData.diskPercent;
                    return 0;
                }
                icon: {
                    if (statType === "cpu") return String.fromCodePoint(0xF035B);
                    if (statType === "ram") return String.fromCodePoint(0xF035C);
                    if (statType === "temp") return String.fromCodePoint(0xF050F);
                    if (statType === "disk") return String.fromCodePoint(0xF0A0);
                    return "";
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: !(root.activeTarget && root.activeTarget.isPreview)
        onClicked: {
            FloatingController.showSystemUsage(root.barWindow ? root.barWindow.screen : null);
        }
    }
}
