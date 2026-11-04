import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import "../"
import "../reusables"

Item {
    id: root
    visible: false
    focus: true
    enabled: visible

    function s(val) {
        return Scaler.s(val);
    }

    readonly property string barPosition: {
        if (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.position !== undefined) {
            return Config.rawSettings.bar.position;
        }
        return "top";
    }


    readonly property bool isDesktop: UPower.displayDevice.ready ? !UPower.displayDevice.isLaptopBattery : SystemInfo.isDesktop

    readonly property real boxRadius: Math.min(ThemeBackend.borderRadius, root.s(20))
    readonly property real cardRadius: Math.min(ThemeBackend.borderRadius, root.s(14))

    readonly property color briColor: Qt.lighter(ThemeBackend.mauve, 1.1)
    readonly property color volColor: Qt.lighter(ThemeBackend.sapphire, 1.5)
    readonly property color profileColor: Qt.lighter(ThemeBackend.blue, 1.55)
    readonly property int batCapacity: UPower.displayDevice.ready ? Math.round(UPower.displayDevice.percentage * 100) : 0

    readonly property bool isCharging: UPower.displayDevice.ready && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)

    readonly property string batStatus: {
        if (!UPower.displayDevice.ready) return "Unknown";
        switch (UPower.displayDevice.state) {
            case UPowerDeviceState.FullyCharged: return "Fully Charged";
            case UPowerDeviceState.Charging: return "Charging";
            case UPowerDeviceState.Discharging: return "Discharging";
            default: return "Unknown";
        }
    }

    readonly property int batHours: {
        if (!UPower.displayDevice.ready) return 0;
        let secs = isCharging ? UPower.displayDevice.timeToFull : UPower.displayDevice.timeToEmpty;
        return Math.floor(secs / 3600);
    }

    readonly property int batMins: {
        if (!UPower.displayDevice.ready) return 0;
        let secs = isCharging ? UPower.displayDevice.timeToFull : UPower.displayDevice.timeToEmpty;
        return Math.round((secs % 3600) / 60);
    }

    readonly property string batTimeLabel: {
        if (!UPower.displayDevice.ready || (batHours === 0 && batMins === 0) || batCapacity === 100) return "";
        if (UPower.displayDevice.state === UPowerDeviceState.Charging) return I18n.t("syspanel.battery.until_full");
        if (UPower.displayDevice.state === UPowerDeviceState.Discharging) return I18n.t("syspanel.battery.remaining");
        return "";
    }

    readonly property string powerProfile: {
        switch (PowerProfiles.profile) {
            case PowerProfile.Performance: return "performance";
            case PowerProfile.PowerSaver: return "power-saver";
            default: return "balanced";
        }
    }

    readonly property real sysVolume: Audio.defaultSink && Audio.defaultSink.audio ? Math.round(Audio.defaultSink.audio.volume * 100) : 0
    readonly property bool sysMuted: Audio.defaultSink && Audio.defaultSink.audio ? Audio.defaultSink.audio.muted : false

    property real sysBrightness: 0

    property bool wifiRadioEnabled: Networking.wifiEnabled
    property bool btRadioEnabled: Boolean(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)

    Connections {
        target: Bluetooth
        ignoreUnknownSignals: true
        function onDefaultAdapterChanged() {
            root.btRadioEnabled = Boolean(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled);
        }
    }

    Connections {
        target: Bluetooth.defaultAdapter || null
        ignoreUnknownSignals: true
        function onEnabledChanged() {
            root.btRadioEnabled = Boolean(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled);
        }
    }

    property bool isDraggingVol: false
    property bool isDraggingBri: false
    property bool usesDdcBrightness: false

    property bool btStateBeforeAirplane: false
    property bool wifiStateBeforeAirplane: true

    readonly property color batColorFlat: {
        if (!UPower.displayDevice.ready) return ThemeBackend.blue;
        if (isCharging) return ThemeBackend.green;
        if (batCapacity <= 20) return ThemeBackend.red;
        return ThemeBackend.blue;
    }

    property real animCapacity: 0
    Behavior on animCapacity {
        enabled: root.visible
        NumberAnimation { duration: 1200; easing.type: Easing.OutQuint }
    }

    onBatCapacityChanged: {
        if (root.visible) {
            animCapacity = batCapacity;
        }
    }

    onSysVolumeChanged: {
        if (root.visible && slidersBox.volumeSlider && !root.isDraggingVol && slidersBox.volumeSlider.value !== sysVolume) {
            slidersBox.volumeSlider.value = sysVolume;
        }
    }

    onSysBrightnessChanged: {
        if (root.visible && slidersBox.brightnessSlider && !root.isDraggingBri && slidersBox.brightnessSlider.value !== sysBrightness) {
            slidersBox.brightnessSlider.value = sysBrightness;
        }
    }

    // Height of the drawer = its content (Main.qml reads drawerHeight)
    readonly property real drawerHeight: panelColumn.implicitHeight + root.s(16)

    onVisibleChanged: {
        if (visible) {
            forceActiveFocus();

            animCapacity = batCapacity;

            if (slidersBox.volumeSlider && !root.isDraggingVol) {
                slidersBox.volumeSlider.value = root.sysVolume;
            }

            if (slidersBox.brightnessSlider && !root.isDraggingBri) {
                slidersBox.brightnessSlider.value = root.sysBrightness;
            }

            if (quickActionsBox.nightLight) quickActionsBox.nightLight.updateState();
            if (quickActionsBox.coffee) quickActionsBox.coffee.updateState();

            briPollerTimer.interval = 150;
            briPollerTimer.restart();
        } else {
            briPollerTimer.stop();
            briPoller.running = false;
            closeSequence.stop();
        }
    }

    Component.onCompleted: {
        if (visible) {
            if (quickActionsBox.nightLight) quickActionsBox.nightLight.updateState();
            if (quickActionsBox.coffee) quickActionsBox.coffee.updateState();
            forceActiveFocus();
            briPollerTimer.interval = 150;
            briPollerTimer.restart();
            animCapacity = batCapacity;
        }
    }

    Component.onDestruction: {
        briPollerTimer.stop();
    }

    Timer {
        id: briPollerTimer
        interval: root.usesDdcBrightness ? 10000 : 1500
        repeat: false
        onTriggered: {
            if (root.visible) {
                briPoller.running = true;
                interval = root.usesDdcBrightness ? 10000 : 1500;
            }
        }
    }

    Process {
        id: briBackend
        command: ["bash", Caching.qsDir + "/../scripts/brightness.sh", "backend"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.usesDdcBrightness = this.text.trim() === "ddc"
        }
    }

    Process {
        id: briPoller
        command: ["bash", Caching.qsDir + "/../scripts/brightness.sh", "get"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text.trim();
                if (out !== "" && !root.isDraggingBri) {
                    root.sysBrightness = parseInt(out) || 0;
                }
                if (root.visible) briPollerTimer.start();
            }
        }
    }

    property alias closeAnim: closeSequence

    property var exitCallback: null

    function startExit(onFinished) {
        exitCallback = onFinished;
        closeSequence.restart();
    }

    SequentialAnimation {
        id: closeSequence
        // The drawer slides back in Main.qml (contentStage.tuck); wait for it
        PauseAnimation { duration: Motion.close }
        ScriptAction {
            script: {
                if (root.exitCallback) {
                    let cb = root.exitCallback;
                    root.exitCallback = null;
                    cb();
                } else {
                    Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "close"]);
                }
            }
        }
    }

    Keys.onEscapePressed: (event) => {
        if (typeof masterWindow !== "undefined" && masterWindow.switchWidget) {
            masterWindow.switchWidget("hidden", "");
        } else {
            closeSequence.restart();
        }
        event.accepted = true;
    }

    component BatteryContent : Item {
        id: bRoot
        property color contentTextColor: ThemeBackend.text
        property color iconColor: root.batColorFlat
        property bool glass: false

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.s(20)
            anchors.rightMargin: root.s(20)
            spacing: root.s(16)

            Text {
                font.family: ThemeBackend.iconFont
                font.pixelSize: root.s(32)
                color: bRoot.iconColor
                text: root.isCharging ? "󰂄" : (root.batCapacity > 20 ? "󰁹" : "󰂃")
                Behavior on color {
                    enabled: root.visible
                    ColorAnimation { duration: Motion.ultraSlow }
                }
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                spacing: root.s(2)
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                Text {
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Black
                    font.pixelSize: root.s(20)
                    color: bRoot.contentTextColor
                    text: Math.round(root.animCapacity) + "%"
                    Behavior on color {
                        enabled: root.visible
                        ColorAnimation { duration: Motion.ultraSlow }
                    }
                }

                Text {
                    property string timeString: {
                        if (root.batStatus === "Fully Charged") return I18n.t("syspanel.battery.fully_charged");
                        if (root.batStatus === "Charging") {
                            if (root.batHours === 0 && root.batMins === 0) return I18n.t("syspanel.battery.charging");
                            return I18n.t("syspanel.battery.charging_time", { hours: root.batHours, mins: root.batMins });
                        }
                        if (root.batHours === 0 && root.batMins === 0) return I18n.t("syspanel.battery.discharging");
                        return I18n.t("syspanel.battery.left_time", { hours: root.batHours, mins: root.batMins });
                    }

                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: root.s(10)
                    color: bRoot.glass ? Qt.alpha(bRoot.contentTextColor, 0.75) : (bRoot.contentTextColor === ThemeBackend.crust ? Qt.alpha(ThemeBackend.crust, 0.85) : (root.isCharging ? ThemeBackend.green : ThemeBackend.subtext0))
                    text: timeString
                    Behavior on color {
                        enabled: root.visible
                        ColorAnimation { duration: Motion.normal }
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    Rectangle {
        id: sidebarPanel
        anchors.fill: parent
        // Convex: solid like the frame it hangs from
        color: ConvexState.active ? ThemeBackend.base : Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
        radius: Math.min(ThemeBackend.borderRadius, root.s(28))
        topLeftRadius: ConvexState.tl(radius)
        bottomLeftRadius: ConvexState.bl(radius)
        topRightRadius: ConvexState.tr(radius)
        bottomRightRadius: ConvexState.br(radius)
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
            anchors.fill: parent

            ColumnLayout {
                id: panelColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.s(8)
                spacing: root.s(5)

                SystemPanelSliders {
                    id: slidersBox
                    panel: root
                }

                SystemPanelQuickActions {
                    id: quickActionsBox
                    panel: root
                }

                Rectangle {
                    id: batteryBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.isDesktop ? root.s(52) : root.s(72)
                    Layout.maximumHeight: Layout.preferredHeight
                    radius: root.isDesktop ? root.s(15) : root.boxRadius
                    color: (root.isDesktop || batteryGlass.active) ? "transparent" : ThemeBackend.faded(Qt.darker(ThemeBackend.surface0, 1.04))
                    clip: true

                    property real fillLevel: root.animCapacity / 100
                    property real maxWaveAmp: root.isCharging ? root.s(10) : root.s(6.5)
                    property real waveAmp: (fillLevel < 0.99 && fillLevel > 0.01) ? maxWaveAmp * Math.sin(fillLevel * Math.PI) : 0

                    GlassFill {
                        id: batteryGlass
                        anchors.fill: parent
                        allowed: !root.isDesktop
                        radius: parent.radius
                        tintColor: ThemeBackend.surface0
                        tintAmount: 0.3
                    }

                    FluidWave {
                        id: waveCanvas
                        anchors.fill: parent
                        visible: !batteryGlass.active && root.visible && !root.isDesktop && batteryBox.fillLevel > 0.001

                        property real wavePhase: 0.0
                        NumberAnimation on wavePhase {
                            running: root.visible && !root.isDesktop && batteryBox.fillLevel > 0.0 && batteryBox.fillLevel < 1.0
                            loops: Animation.Infinite
                            from: 0; to: Math.PI * 2; duration: root.isCharging ? 1200 : 2200
                        }

                        radius: batteryBox.radius
                        fillLevel: batteryBox.fillLevel
                        waveAmp: (batteryBox.fillLevel < 0.99 && batteryBox.waveAmp > 0) ? Math.min(batteryBox.waveAmp, Math.min(width * batteryBox.fillLevel, width * (1.0 - batteryBox.fillLevel))) : 0
                        phase: wavePhase
                        vertical: 0.0
                        color1: root.batColorFlat
                        color2: root.batColorFlat
                    }

                    LiquidFill {
                        anchors.fill: parent
                        visible: batteryGlass.active && root.visible && !root.isDesktop && batteryBox.fillLevel > 0.001
                        radius: batteryBox.radius
                        fillLevel: batteryBox.fillLevel
                        waveAmp: waveCanvas.waveAmp
                        phase: waveCanvas.wavePhase
                        color1: Qt.alpha(Qt.lighter(root.batColorFlat, 1.1), 0.6)
                        color2: Qt.alpha(root.batColorFlat, 0.6)
                        bodyAlpha: 0.18
                    }

                    BatteryContent {
                        anchors.fill: parent
                        contentTextColor: ThemeBackend.text
                        iconColor: root.batColorFlat
                        glass: batteryGlass.active
                        visible: !root.isDesktop
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        visible: !root.isDesktop

                        property real phaseOffset: Math.sin(waveCanvas.wavePhase) - Math.cos(waveCanvas.wavePhase)
                        property real centerOffset: batteryBox.fillLevel > 0.01 && batteryBox.fillLevel < 0.99 ? 0.375 * batteryBox.waveAmp * phaseOffset : 0

                        width: Math.max(0, Math.min(parent.width, (parent.width * batteryBox.fillLevel) + centerOffset))
                        clip: true

                        BatteryContent {
                            width: batteryBox.width
                            height: batteryBox.height
                            contentTextColor: batteryGlass.active ? ThemeBackend.text : ThemeBackend.crust
                            iconColor: batteryGlass.active ? ThemeBackend.text : ThemeBackend.crust
                            glass: batteryGlass.active
                        }
                    }

                    Item {
                        id: profileSwitchWrapper
                        anchors.fill: root.isDesktop ? parent : undefined
                        anchors.right: root.isDesktop ? undefined : parent.right
                        anchors.verticalCenter: root.isDesktop ? undefined : parent.verticalCenter
                        anchors.rightMargin: root.isDesktop ? 0 : root.s(12)
                        implicitWidth: root.isDesktop ? parent.width : profileSwitch.implicitWidth
                        implicitHeight: profileSwitch.implicitHeight

                        Rectangle {
                            id: profileSwitchShadow
                            visible: !root.isDesktop && !profileSwitch.glassActive
                            anchors.fill: parent
                            anchors.topMargin: root.s(1.5)
                            anchors.bottomMargin: -root.s(1.5)
                            radius: profileSwitch.cornerRadius
                            color: Qt.rgba(0, 0, 0, 0.25)
                        }

                        Switch {
                            id: profileSwitch
                            anchors.fill: parent
                            implicitWidth: root.isDesktop ? parent.width : (PowerProfiles.hasPerformanceProfile ? root.s(240) : root.s(162))
                            implicitHeight: root.isDesktop ? root.s(48) : root.s(52)
                            cornerRadius: root.s(15)
                            fontPixelSize: root.isDesktop ? root.s(14) : root.s(22)
                            options: {
                                if (root.isDesktop) {
                                    return PowerProfiles.hasPerformanceProfile
                                        ? ["󰌪 " + I18n.t("syspanel.profiles.power_saver"), "󰗑 " + I18n.t("syspanel.profiles.balanced"), "󰓅 " + I18n.t("syspanel.profiles.performance")]
                                        : ["󰌪 " + I18n.t("syspanel.profiles.power_saver"), "󰗑 " + I18n.t("syspanel.profiles.balanced")];
                                } else {
                                    return PowerProfiles.hasPerformanceProfile
                                        ? ["󰌪", "󰗑", "󰓅"]
                                        : ["󰌪", "󰗑"];
                                }
                            }
                            accentColor: root.profileColor
                            baseColor: ThemeBackend.surface1
                            textColor: ThemeBackend.text
                            activeTextColor: ThemeBackend.crust
                            currentIndex: {
                                if (PowerProfiles.hasPerformanceProfile) {
                                    if (root.powerProfile === "power-saver") return 0;
                                    if (root.powerProfile === "balanced") return 1;
                                    return 2;
                                } else {
                                    if (root.powerProfile === "power-saver") return 0;
                                    return 1;
                                }
                            }

                            onValueChanged: (idx, val) => {
                                if (PowerProfiles.hasPerformanceProfile) {
                                    if (idx === 0) PowerProfiles.profile = PowerProfile.PowerSaver;
                                    else if (idx === 1) PowerProfiles.profile = PowerProfile.Balanced;
                                    else PowerProfiles.profile = PowerProfile.Performance;
                                } else {
                                    if (idx === 0) PowerProfiles.profile = PowerProfile.PowerSaver;
                                    else PowerProfiles.profile = PowerProfile.Balanced;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
