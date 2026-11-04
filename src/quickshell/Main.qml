import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import "WindowRegistry.js" as Registry
import "notifications" as Notifs

PanelWindow {
    id: masterWindow
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: masterWindow.isVisible && !masterWindow.isClosing
        onActivated: switchWidget("hidden", "")
    }

    function resolveTargetScreen() {
        try {
            if (typeof Hyprland !== "undefined" && Hyprland.focusedMonitor) {
                let monName = Hyprland.focusedMonitor.name;
                let screens = Quickshell.screens || [];
                let len = screens.length !== undefined ? screens.length : (screens.count !== undefined ? screens.count : 0);
                for (let i = 0; i < len; i++) {
                    let s = screens[i] !== undefined ? screens[i] : screens.get(i);
                    if (s && s.name === monName) return s;
                }
            }
        } catch (e) {}

        try {
            if (typeof ToplevelManager !== "undefined" && ToplevelManager.activeToplevel && ToplevelManager.activeToplevel.screens && ToplevelManager.activeToplevel.screens.length > 0) {
                return ToplevelManager.activeToplevel.screens[0];
            }
        } catch (e) {}

        if (masterWindow.screen) return masterWindow.screen;
        return (Quickshell.screens && (Quickshell.screens.length > 0 || Quickshell.screens.count > 0))
            ? (Quickshell.screens[0] || Quickshell.screens.get(0))
            : null;
    }

    function reportWidgetState() {
        if (typeof Caching === "undefined" || !Caching.runDir) return;
        let sName = (masterWindow.currentActive === "hidden" || !masterWindow.screen) ? "" : (masterWindow.screen.name || "");
        let payload = JSON.stringify({
            widget: masterWindow.currentActive,
            screen: sName
        });
        Quickshell.execDetached(["bash", "-c", "echo '" + payload + "' > " + Caching.runDir + "/current_widget"]);
    }

    Process {
        id: startupResetProcess
        command: ["bash", "-c", `[ -n "${Caching.runDir}" ] && echo '{"widget":"hidden","screen":""}' > "${Caching.runDir}/current_widget"`]
        running: true
    }

    Connections {
        target: (typeof Caching !== "undefined") ? Caching : null
        function onRunDirChanged() {
            masterWindow.reportWidgetState();
        }
    }

    IpcHandler {
        target: "main"

        function forceReload(): void {
            Quickshell.reload(true);
        }

        function clearNotifications(): void {
            NotificationManager.clearNotifications();
        }

        // Game Mode (singletons/system/GameMode.qml): toggle / on / off
        function gameMode(action: string): void {
            if (action === "on") GameMode.enable();
            else if (action === "off") GameMode.disable();
            else GameMode.toggle();
        }

        function embeddedSettings(action: string, tab: string): void {
            masterWindow.handleEmbeddedSettings(action || "toggle", tab || "");
        }

        function handleCommand(cmd: string, targetWidget: string, arg: string): void {
            cmd = cmd || "";
            targetWidget = targetWidget || "";
            arg = arg || "";

            if (cmd === "clearNotifications" || cmd === "clear_notifications" || cmd === "clearNotifs") {
                NotificationManager.clearNotifications();
                return;
            }

            let isSettingsCmd = cmd === "settings" || targetWidget === "settings";
            let isGuideCmd = cmd === "guide" || targetWidget === "guide";
            if (isSettingsCmd || isGuideCmd) {
                if (isGuideCmd) {
                    console.warn("'guide' is deprecated, use 'settings' instead");
                }
                let settingsAction = cmd === "close" ? "close" : (cmd === "open" ? "open" : "toggle");
                let settingsTab = (cmd === "settings" || cmd === "guide") ? targetWidget : arg;
                if (settingsTab === "settings" || settingsTab === "guide") settingsTab = "";
                if (masterWindow.settingsSeparateWindow && masterWindow.targetActive !== "guide") {
                    Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/settings.sh", "--window", settingsAction, settingsTab]);
                } else {
                    masterWindow.handleEmbeddedSettings(settingsAction, settingsTab);
                }
                return;
            }

            if (cmd === "clipboard" || targetWidget === "clipboard" || cmd === "clip" || targetWidget === "clip") {
                if (cmd === "close") {
                    ClipboardController.hide();
                } else if (cmd === "open") {
                    ClipboardController.show();
                } else {
                    ClipboardController.toggle();
                }
                return;
            }

            if (cmd === "airplane" || targetWidget === "airplane" || cmd === "flight" || targetWidget === "flight") {
                let isAirplane = !Networking.wifiEnabled && !(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled);
                if (isAirplane) {
                    Networking.wifiEnabled = true;
                    if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = true;
                } else {
                    Networking.wifiEnabled = false;
                    if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = false;
                }
                return;
            }

            if (cmd === "autohide" || targetWidget === "autohide") {
                let bar = Config.getSetting("bar", {});
                bar.autohide = !bar.autohide;
                Config.setSetting("bar", bar);
                return;
            }

            let effectivelyActive = masterWindow.targetActive;

            if (cmd === "close") {
                switchWidget("hidden", "");
            } else if (cmd === "toggle" || cmd === "open") {
                if (targetWidget === effectivelyActive) {
                    let currentItem = widgetCache[targetWidget] || widgetStack.currentItem;

                    if (arg !== "" && arg !== masterWindow.activeArg) {
                        masterWindow.activeArg = arg;
                        if (currentItem && currentItem.activeMode !== undefined) {
                            currentItem.activeMode = arg;
                        }
                        if (currentItem && currentItem.gotoTab !== undefined) {
                            currentItem.gotoTab(arg);
                        }
                    } else if (cmd === "toggle") {
                        switchWidget("hidden", "");
                    }
                } else if (getLayout(targetWidget)) {
                    switchWidget(targetWidget, arg);
                }
            } else if (getLayout(cmd)) {
                let legacyArg = targetWidget;

                if (cmd === effectivelyActive) {
                    let currentItem = widgetCache[cmd] || widgetStack.currentItem;
                    if (legacyArg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== legacyArg) {
                        currentItem.activeMode = legacyArg;
                    } else if (legacyArg !== "" && currentItem && currentItem.gotoTab !== undefined) {
                        currentItem.gotoTab(legacyArg);
                    } else {
                        switchWidget("hidden", "");
                    }
                } else {
                    switchWidget(cmd, legacyArg);
                }
            }
        }
    }

    WlrLayershell.namespace: "qs-master"
    WlrLayershell.layer: WlrLayer.Overlay

    exclusionMode: ExclusionMode.Ignore
    focusable: true

    implicitWidth: masterWindow.screen ? masterWindow.screen.width : 0
    implicitHeight: masterWindow.screen ? masterWindow.screen.height : 0

    visible: isVisible

    mask: Region {
        item: masterWindow.isCurrentDraggable ? maskContent : topBarHole
        intersection: masterWindow.isCurrentDraggable ? Intersection.Combine : Intersection.Xor
    }

    property var rawBarSettings: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.bar) ? Config.rawSettings.bar : ({})
    property string barPosition: (rawBarSettings && rawBarSettings.position !== undefined) ? rawBarSettings.position : "top"
    property bool barAutohide: (rawBarSettings && rawBarSettings.autohide !== undefined) ? Boolean(rawBarSettings.autohide) : false
    readonly property bool settingsSeparateWindow: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.general) ? Boolean(Config.rawSettings.general.settingsSeparateWindow) : false

    function handleEmbeddedSettings(action, tab) {
        let isOpen = masterWindow.targetActive === "guide";
        if (action === "close") {
            if (isOpen) switchWidget("hidden", "");
            return;
        }
        if (!isOpen) {
            let t = getLayout("guide");
            if (t) switchWidget("guide", tab);
            return;
        }
        let item = widgetCache["guide"] || widgetStack.currentItem;
        if (tab !== "" && (action === "open" || tab !== masterWindow.activeArg)) {
            masterWindow.activeArg = tab;
            if (item && item.gotoTab !== undefined) item.gotoTab(tab);
        } else if (action === "toggle") {
            switchWidget("hidden", "");
        }
    }

    readonly property bool isFullscreenActive: {
        try {
            if (typeof Hyprland !== "undefined" && Hyprland.focusedWorkspace) {
                return Boolean(Hyprland.focusedWorkspace.hasFullscreen || (Hyprland.activeToplevel && Hyprland.activeToplevel.fullscreen));
            }
        } catch (e) {}
        return false;
    }

    readonly property bool isBarEffectivelyHidden: barAutohide || isFullscreenActive

    // Bar style "convex": dropdowns hang from the bar, side panels from the screen frame.
    // Geometry goes to ConvexState (bar/ConvexBulges.qml draws the bar side, popups square their corners).
    readonly property bool isConvex: rawBarSettings.style === "convex" && (barPosition === "top" || barPosition === "bottom") && !isBarEffectivelyHidden
    readonly property var convexDropdowns: ["network", "bluetooth", "tailscale", "security", "volume", "music", "battery"]
    readonly property int convexFrame: Math.round(Scaler.s(7))   // bar/Bar.qml convexFrame
    readonly property int convexRadius: Math.round(Scaler.s(12)) // bar/Bar.qml cornerRadius
    readonly property int convexBarH: {
        let v = (rawBarSettings && rawBarSettings.height !== undefined) ? Number(rawBarSettings.height) : 40;
        if (isNaN(v)) v = 40;
        return Math.round(Scaler.s(Math.max(28, Math.min(48, v))));
    }
    // Side drawers come out of the right frame edge, the power menu out of the bottom edge
    readonly property var convexSideDrawers: ["system", "notifications"]
    readonly property var convexBottomDrawers: ["power"]
    function isConvexAttached(name) {
        return isConvex && (convexDropdowns.indexOf(name) !== -1 || convexSideDrawers.indexOf(name) !== -1 || convexBottomDrawers.indexOf(name) !== -1);
    }
    // Bar section { x0, x1 } a dropdown belongs to: the one nearest to its registry position
    // (not the animated one, which depends on this)
    function convexOriginFor(name) {
        if (!isConvex || convexDropdowns.indexOf(name) === -1) return null;
        let r = Registry.getLayout(name, 0, 0, masterWindow.width, masterWindow.height, masterWindow.globalUiScale, barPosition);
        if (!r) return null;
        let secs = ConvexState.sectionsFor(masterWindow.screen ? (masterWindow.screen.name || "") : "");
        let cx = r.rx + r.w / 2, best = null, bestD = 1e9;
        for (let i = 0; i < secs.length; i++) {
            let d = Math.abs((secs[i].x0 + secs[i].x1) / 2 - cx);
            if (d < bestD) { bestD = d; best = secs[i]; }
        }
        return best;
    }
    // Position (and width) of an attached popup of size w x h (also used when the popup changes its own size).
    // Dropdowns are at least as wide as their bar section and flush with it, like the bar part pulled down.
    function convexPlace(name, w, h, mw, mh, fallbackX) {
        let t = convexFrame, bh = convexBarH, top = barPosition === "top";
        if (convexSideDrawers.indexOf(name) !== -1) {
            let y0 = top ? bh : t, y1 = mh - (top ? t : bh);
            return { x: mw - t - w, y: Math.round(y0 + Math.max(0, (y1 - y0 - h) / 2)), w: w };
        }
        if (convexBottomDrawers.indexOf(name) !== -1) {
            return { x: Math.round((mw - w) / 2), y: mh - (top ? t : bh) - h, w: w };
        }
        let x = fallbackX;
        let o = convexOriginFor(name);
        if (o) {
            w = Math.max(w, o.x1 - o.x0);
            let atLeft = o.x0 <= t + 0.5, atRight = o.x1 >= mw - t - 0.5;
            x = atRight ? o.x1 - w : (atLeft ? o.x0 : Math.round((o.x0 + o.x1 - w) / 2));
        }
        return { x: Math.max(t, Math.min(mw - t - w, x)), y: top ? bh : (mh - bh - h), w: w };
    }
    function convexLayout(name, r, mw, mh) {
        let p = convexPlace(name, r.w, r.h, mw, mh, r.rx);
        return { w: p.w, h: r.h, rx: p.x, ry: p.y, comp: r.comp, draggable: r.draggable };
    }

    readonly property var convexInfo: {
        if (!isConvexAttached(currentActive) || !screenReady) return null;
        let t = convexFrame, bh = convexBarH, top = barPosition === "top", e = 0.5;
        // Dropdowns: the shape that grows out of the bar (morphClip), not the final rect
        let x = _animX, y = _animY, w = _animW, h = _animH;
        if (contentStage.isMorph) {
            x = animContainer.x + morphClip.x; y = animContainer.y + morphClip.y;
            w = morphClip.width; h = morphClip.height;
        }
        return {
            x: x, y: y, w: w, h: h,
            top: y <= (top ? bh : t) + e,
            bottom: y + h >= masterWindow.height - (top ? t : bh) - e,
            left: x <= t + e,
            right: x + w >= masterWindow.width - t - e
        };
    }
    onConvexInfoChanged: {
        let c = convexInfo;
        ConvexState.active = !!c;
        if (!c) return;
        ConvexState.screenName = masterWindow.screen ? (masterWindow.screen.name || "") : "";
        ConvexState.x = c.x; ConvexState.y = c.y; ConvexState.w = c.w; ConvexState.h = c.h;
        ConvexState.squareTop = c.top; ConvexState.squareBottom = c.bottom;
        ConvexState.squareLeft = c.left; ConvexState.squareRight = c.right;
    }
    // Bar section the open dropdown grows out of (like minflair's centre bulge)
    readonly property var convexOrigin: convexOriginFor(currentActive)
    readonly property bool screenReady: masterWindow.width >= 100 && masterWindow.height >= 100
    readonly property bool isCurrentDraggable: {
        let t = getLayout(masterWindow.currentActive);
        return Boolean(t && t.draggable);
    }

    Item {
        id: maskContent
        x: masterWindow._animX
        y: masterWindow._animY
        width: masterWindow._animW
        height: masterWindow._animH
    }

    // Convex: concave joins where the popup meets the screen frame (the bar side is drawn by the bar)
    Repeater {
        model: {
            let c = masterWindow.convexInfo;
            if (!c) return [];
            let t = masterWindow.convexFrame, r = masterWindow.convexRadius;
            let W = masterWindow.width, H = masterWindow.height;
            let barTop = masterWindow.barPosition === "top";
            let x0 = c.x, x1 = c.x + c.w, y0 = c.y, y1 = c.y + c.h;
            let out = [];
            // ax/ay = point where popup and frame edge meet, edge = frame edge of the join,
            // c = filled corner of the quad: 0 TL, 1 TR, 2 BL, 3 BR
            if (c.left) {
                if (!c.bottom) out.push({ ax: t, ay: y1, c: 0, edge: "left" });
                if (!c.top) out.push({ ax: t, ay: y0, c: 2, edge: "left" });
            }
            if (c.right) {
                if (!c.bottom) out.push({ ax: W - t, ay: y1, c: 1, edge: "right" });
                if (!c.top) out.push({ ax: W - t, ay: y0, c: 3, edge: "right" });
            }
            if (c.bottom && barTop) {
                if (!c.left) out.push({ ax: x0, ay: H - t, c: 3, edge: "bottom" });
                if (!c.right) out.push({ ax: x1, ay: H - t, c: 2, edge: "bottom" });
            }
            if (c.top && !barTop) {
                if (!c.left) out.push({ ax: x0, ay: t, c: 1, edge: "top" });
                if (!c.right) out.push({ ax: x1, ay: t, c: 0, edge: "top" });
            }
            return out;
        }
        delegate: ShaderEffect {
            required property var modelData
            // Like minflair: a join on the edge the drawer slides out of is part of the drawer and
            // grows with it (at most 35 % of the part that is out); other joins fade with the slide
            readonly property bool grows: contentStage.isDrawer && modelData.edge === contentStage.tuckEdge
            readonly property real outExtent: (1 - contentStage.tuck) * (contentStage.isSideDrawer ? contentStage.width : contentStage.height)
            readonly property real size: grows ? Math.min(masterWindow.convexRadius, outExtent * 0.35) : masterWindow.convexRadius
            x: (modelData.c === 1 || modelData.c === 3) ? modelData.ax - size : modelData.ax
            y: (modelData.c === 2 || modelData.c === 3) ? modelData.ay - size : modelData.ay
            width: size; height: size
            visible: size >= 0.5
            opacity: (contentStage.isDrawer && !grows) ? contentStage.opacity * Math.max(0, 1 - 4 * contentStage.tuck) : contentStage.opacity
            property real cornerIndex: modelData.c
            property vector2d itemSize: Qt.vector2d(width, height)
            property color color: ThemeBackend.base
            fragmentShader: "file://" + Caching.serpantinumDir + "/assets/shaders/ui/corner_cutout.frag.qsb"
        }
    }

    Item {
        id: topBarHole

        property real thicknessRatio: {
            let h = (masterWindow.rawBarSettings && masterWindow.rawBarSettings.height !== undefined) ? Number(masterWindow.rawBarSettings.height) : 40;
            if (isNaN(h)) h = 40;
            return Math.max(28, Math.min(48, h)) / 40;
        }
        property int barThickness: Math.round(48 * thicknessRatio)
        property string bp: masterWindow.barPosition
        property bool activeBar: !masterWindow.isBarEffectivelyHidden

        property bool overlapTopLeft: masterWindow.currentActive !== "hidden" && masterWindow._animX < 10 && masterWindow._animY < barThickness
        property bool overlapTopRight: masterWindow.currentActive !== "hidden" && (masterWindow._animX + masterWindow._animW) > (masterWindow.width - 10) && masterWindow._animY < barThickness
        property bool overlapBottomLeft: masterWindow.currentActive !== "hidden" && masterWindow._animX < 10 && (masterWindow._animY + masterWindow._animH) > (masterWindow.height - barThickness)
        property bool overlapBottomRight: masterWindow.currentActive !== "hidden" && (masterWindow._animX + masterWindow._animW) > (masterWindow.width - 10) && (masterWindow._animY + masterWindow._animH) > (masterWindow.height - barThickness)

        x: {
            if (!activeBar) return 0;
            if (bp === "left") return 0;
            if (bp === "right") return masterWindow.width - barThickness;
            if (overlapTopLeft && bp === "top") return masterWindow._animW;
            if (overlapBottomLeft && bp === "bottom") return masterWindow._animW;
            return 0;
        }

        y: {
            if (!activeBar) return 0;
            if (bp === "top") return 0;
            if (bp === "bottom") return masterWindow.height - barThickness;
            if (overlapTopLeft && bp === "left") return masterWindow._animH;
            if (overlapTopRight && bp === "right") return masterWindow._animH;
            return 0;
        }

        width: {
            if (!activeBar) return 0;
            if (bp === "left" || bp === "right") return barThickness;
            let w = masterWindow.width;
            if (overlapTopLeft && bp === "top") w -= masterWindow._animW;
            if (overlapTopRight && bp === "top") w -= masterWindow._animW;
            if (overlapBottomLeft && bp === "bottom") w -= masterWindow._animW;
            if (overlapBottomRight && bp === "bottom") w -= masterWindow._animW;
            return Math.max(0, w);
        }

        height: {
            if (!activeBar) return 0;
            if (bp === "top" || bp === "bottom") return barThickness;
            let h = masterWindow.height;
            if (overlapTopLeft && bp === "left") h -= masterWindow._animH;
            if (overlapBottomLeft && bp === "left") h -= masterWindow._animH;
            if (overlapTopRight && bp === "right") h -= masterWindow._animH;
            if (overlapBottomRight && bp === "right") h -= masterWindow._animH;
            return Math.max(0, h);
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: masterWindow.isVisible && !masterWindow.isCurrentDraggable && !masterWindow.isClosing
        onClicked: switchWidget("hidden", "")
    }

    Item {
        id: preloaderContainer
        visible: false
    }

    property var widgetCache: ({})
    property var componentCache: ({})

    function widgetNameForItem(item) {
        for (let name in widgetCache) {
            if (widgetCache[name] === item) return name;
        }
        return null;
    }

    function ensureWidgetItem(name, t) {
        let cached = widgetCache[name];
        if (cached) return cached;

        let comp = componentCache[name];
        if (!comp) {
            comp = typeof t.comp === "string" ? Qt.createComponent(t.comp) : t.comp;
            if (comp) componentCache[name] = comp;
        }
        if (!comp) return null;

        if (comp.status === Component.Loading) return null;
        if (comp.status === Component.Error) {
            console.warn("Widget component failed to load:", name, comp.errorString());
            return null;
        }

        let item = comp.createObject(preloaderContainer);
        if (item) {
            item.visible = false;
            widgetCache[name] = item;
        }
        return item;
    }

    Component.onCompleted: {
        applyConfigSettings();
        reportWidgetState();
        Qt.callLater(function() {
            if (masterWindow.currentActive === "hidden") {
                if (!masterWindow.settingsSeparateWindow) {
                    let t = masterWindow.getLayout("guide");
                    if (t) masterWindow.ensureWidgetItem("guide", t);
                }
                let w = masterWindow.getLayout("wallpaper");
                if (w) masterWindow.ensureWidgetItem("wallpaper", w);
            }
        });
    }

    Component.onDestruction: {
        if (typeof Caching !== "undefined" && Caching.runDir) {
            Quickshell.execDetached(["bash", "-c", "echo '{\"widget\":\"hidden\",\"screen\":\"\"}' > " + Caching.runDir + "/current_widget"]);
        }
    }

    property string targetActive: "hidden"
    property string currentActive: "hidden"

    onCurrentActiveChanged: {
        reportWidgetState();
    }

    onScreenChanged: {
        applyConfigSettings();
        if (currentActive !== "hidden") {
            reportWidgetState();
        }
    }

    property bool isVisible: false
    property bool isClosing: false
    property string activeArg: ""
    property bool disableMorph: true
    property int switchGeneration: 0
    property bool userMoved: false

    property int morphDuration:       Motion.resize
    property int morphDurationSwitch: Motion.resize
    property int exitDuration:        Motion.close

    property real _animW: 1
    property real _animH: 1
    property real _animX: 0
    property real _animY: 0

    property real _stageW: 1
    property real _stageH: 1

    property real globalUiScale: 1.0

    Notifs.NotificationPopups {
        id: osdPopups
    }

    function applyConfigSettings() {
        let parsed = (typeof Config !== "undefined" && Config.rawSettings) ? Config.rawSettings : {};
        let sVal = undefined;

        if (parsed.general && parsed.general.uiScale !== undefined) {
            sVal = parsed.general.uiScale;
        } else if (parsed.uiScale !== undefined) {
            sVal = parsed.uiScale;
        }

        let targetScale = (sVal !== undefined && typeof sVal === "number" && !isNaN(sVal) && sVal > 0) ? sVal : 1.0;
        if (masterWindow.globalUiScale !== targetScale) {
            masterWindow.globalUiScale = targetScale;
        }

        let b = parsed.bar || {};
        masterWindow.rawBarSettings = b;
        if (b.position !== undefined) masterWindow.barPosition = b.position;
        if (b.autohide !== undefined) masterWindow.barAutohide = Boolean(b.autohide);
    }

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() {
            masterWindow.applyConfigSettings();
        }
    }

    function getLayout(name) {
        let bp = masterWindow.barPosition;
        let effHidden = masterWindow.isBarEffectivelyHidden;
        let scrW = masterWindow.screen ? masterWindow.screen.width : masterWindow.width;
        let scrH = masterWindow.screen ? masterWindow.screen.height : masterWindow.height;

        let result = Registry.getLayout(name, 0, 0, scrW, scrH, masterWindow.globalUiScale, bp);
        if (!result) return null;

        if (masterWindow.isConvexAttached(name)) return masterWindow.convexLayout(name, result, scrW, scrH);

        let scale = masterWindow.globalUiScale || 1.0;
        let isFixed = (name === "guide" || name === "wallpaper" || name === "notifications" || name === "system" || name === "power" || name === "hidden");

        if (effHidden && !isFixed) {
            let offsetAdjustment = Math.round(46 * scale);
            let adjusted = {
                w: result.w,
                h: result.h,
                rx: result.rx,
                ry: result.ry,
                comp: result.comp,
                draggable: result.draggable
            };

            if (bp === "top") {
                adjusted.ry = Math.max(Math.round(6 * scale), result.ry - offsetAdjustment);
            } else if (bp === "bottom") {
                adjusted.ry = Math.min(masterWindow.height - result.h - Math.round(6 * scale), result.ry + offsetAdjustment);
            } else if (bp === "left" && name !== "calendar") {
                adjusted.rx = Math.max(Math.round(6 * scale), result.rx - offsetAdjustment);
            } else if (bp === "right" && name !== "calendar") {
                adjusted.rx = Math.min(masterWindow.width - result.w - Math.round(6 * scale), result.rx + offsetAdjustment);
            }

            return adjusted;
        }

        return result;
    }

    function recenterX(t, dynW) {
        let originalCenterX = t.rx + Math.floor(t.w / 2);
        return Math.floor(originalCenterX - (dynW / 2));
    }

    readonly property var targetLayout: {
        if (currentActive === "hidden" || currentActive === "") return null;
        if (!screenReady) return null;

        let t = getLayout(currentActive);
        if (!t || !t.w || !t.h || t.w < 10 || t.h < 10) return null;

        if (t.rx < -t.w - 50 || t.ry < -t.h - 50 ||
            t.rx > masterWindow.width + 50 || t.ry > masterWindow.height + 50) {
            return null;
        }

        let item = widgetCache[currentActive];
        let tw = t.w, th = t.h;
        if (item) {
            if (typeof item.targetMasterWidth === "number" && !isNaN(item.targetMasterWidth) && item.targetMasterWidth >= 50) {
                tw = item.targetMasterWidth;
            }
            if (typeof item.targetMasterHeight === "number" && !isNaN(item.targetMasterHeight) && item.targetMasterHeight >= 50) {
                th = item.targetMasterHeight;
            }
            // Drawers that size themselves to their content (binding, never written by Main)
            if (typeof item.drawerHeight === "number" && !isNaN(item.drawerHeight) && item.drawerHeight >= 50) {
                th = item.drawerHeight;
            }
        }

        let x = (tw !== t.w) ? recenterX(t, tw) : t.rx;
        let y = t.ry;
        if (isConvexAttached(currentActive)) {
            let p = convexPlace(currentActive, tw, th, masterWindow.width, masterWindow.height, x);
            x = p.x; y = p.y; tw = p.w;
        }
        return { x: x, y: y, w: tw, h: th };
    }

    onTargetLayoutChanged: {
        if (!targetLayout || masterWindow.currentActive === "hidden" || !masterWindow.isVisible) return;
        // When the layer window is mapped again it briefly reports width 0: a layout computed from that
        // (x at the left edge) would otherwise fly to the real place once the morph is enabled
        if (masterWindow.width < 10 || masterWindow.height < 10) return;
        if (!masterWindow.userMoved || !masterWindow.isCurrentDraggable) {
            masterWindow._animX = targetLayout.x;
            masterWindow._animY = targetLayout.y;
        }
        masterWindow._animW = targetLayout.w;
        masterWindow._animH = targetLayout.h;
        masterWindow._stageW = targetLayout.w;
        masterWindow._stageH = targetLayout.h;
    }

    onIsVisibleChanged: {
        if (isVisible) {
            widgetStack.forceActiveFocus();
        } else if (currentActive === "hidden" && !delayedClear.running) {
            for (let k in widgetCache) {
                let it = widgetCache[k];
                if (it) it.visible = false;
            }
        }
    }

    Item {
        id: animContainer
        x: masterWindow._animX
        y: masterWindow._animY
        width: masterWindow._animW
        height: masterWindow._animH
        clip: !contentStage.isMorph

        DragHandler {
            id: windowDragHandler
            target: null
            acceptedButtons: Qt.LeftButton
            enabled: masterWindow.isCurrentDraggable

            property real startX: 0
            property real startY: 0

            onActiveChanged: {
                if (active) {
                    masterWindow.disableMorph = true;
                    startX = masterWindow._animX;
                    startY = masterWindow._animY;
                } else {
                    masterWindow.disableMorph = false;
                }
            }

            onTranslationChanged: {
                if (active) {
                    masterWindow.userMoved = true;
                    masterWindow._animX = startX + translation.x;
                    masterWindow._animY = startY + translation.y;
                }
            }
        }

        // Convex dropdowns: the visible shape grows out of the bar section (minflair's morph);
        // otherwise it simply fills animContainer
        Item {
            id: morphClip
            readonly property real p: 1 - contentStage.tuck
            readonly property var origin: masterWindow.convexOrigin
            readonly property real ox: origin ? origin.x0 - animContainer.x : 0
            readonly property real ow: origin ? origin.x1 - origin.x0 : animContainer.width
            readonly property bool atBottom: masterWindow.barPosition === "bottom"
            x: contentStage.isMorph ? ox * (1 - p) : 0
            width: contentStage.isMorph ? ow + (animContainer.width - ow) * p : animContainer.width
            height: contentStage.isMorph ? animContainer.height * p : animContainer.height
            y: (contentStage.isMorph && atBottom) ? animContainer.height - height : 0
            clip: contentStage.isMorph

            // The growing shape itself, solid in the bar colour like minflair's; the content fades in on it
            Rectangle {
                anchors.fill: parent
                visible: contentStage.isMorph
                color: ThemeBackend.base
                readonly property real r: masterWindow.convexRadius + (Math.min(ThemeBackend.borderRadius, Scaler.s(28)) - masterWindow.convexRadius) * morphClip.p
                topLeftRadius: morphClip.atBottom ? r : 0
                topRightRadius: morphClip.atBottom ? r : 0
                bottomLeftRadius: morphClip.atBottom ? 0 : r
                bottomRightRadius: morphClip.atBottom ? 0 : r
            }

            Item {
                id: contentStage
                width: masterWindow._stageW
                height: masterWindow._stageH
                // Fixed on screen while morphClip grows around it
                x: (animContainer.width - width) / 2 - morphClip.x
                y: (animContainer.height - height) / 2 - morphClip.y
                transformOrigin: isMorph ? (morphClip.atBottom ? Item.Bottom : Item.Top) : ConvexState.origin

                // Convex: dropdowns slide out of the bar like a drawer (clipped by animContainer),
                // System/Notifications out of the right frame edge, the power menu out of the bottom edge.
                // tuck 0 = out, 1 = pulled into the edge; starts closing as soon as isClosing is set.
                readonly property bool isSideDrawer: masterWindow.isConvex && masterWindow.convexSideDrawers.indexOf(masterWindow.currentActive) !== -1
                readonly property bool isDrawer: masterWindow.isConvexAttached(masterWindow.currentActive)
                readonly property bool tucksDown: masterWindow.convexBottomDrawers.indexOf(masterWindow.currentActive) !== -1 || masterWindow.barPosition === "bottom"
                // Frame edge the drawer slides out of
                readonly property string tuckEdge: isSideDrawer ? "right" : (tucksDown ? "bottom" : "top")
                readonly property bool shown: masterWindow.isVisible && !masterWindow.isClosing
                // Bar dropdowns morph out of their bar section instead of sliding
                readonly property bool isMorph: isDrawer && !isSideDrawer && masterWindow.convexBottomDrawers.indexOf(masterWindow.currentActive) === -1 && masterWindow.convexOrigin !== null
                // minflair ConvexCenterPanel: content fades in from 20 % (out below 40 % when closing)
                readonly property real morphFade: shown ? Math.min(1, Math.max(0, (morphClip.p - 0.2) / 0.8))
                                                        : Math.min(1, Math.max(0, (morphClip.p - 0.4) / 0.6))
                property real tuck: shown ? 0 : 1
                Behavior on tuck {
                    NumberAnimation {
                        duration: contentStage.shown ? Motion.open : Motion.close
                        easing.type: contentStage.shown ? Motion.openEasing : Motion.closeEasing
                    }
                }
                transform: Translate {
                    x: contentStage.isSideDrawer ? contentStage.tuck * contentStage.width : 0
                    y: (contentStage.isDrawer && !contentStage.isSideDrawer && !contentStage.isMorph) ? contentStage.tuck * (contentStage.tucksDown ? contentStage.height : -contentStage.height) : 0
                }
                // The bar's bulge above the popup is there as long as the drawer is out at all
                readonly property real convexOpacity: (contentStage.isDrawer && tuck >= 0.999) ? 0 : (isMorph ? 1 : opacity)
                onConvexOpacityChanged: ConvexState.opacity = convexOpacity

                scale: isMorph ? 0.94 + 0.06 * Math.min(1, Math.max(0, (morphClip.p - (shown ? 0.15 : 0.3)) / (shown ? 0.85 : 0.7)))
                     : ((masterWindow.isVisible || contentStage.isDrawer) ? 1.0 : 0.96)
                Behavior on scale {
                    enabled: !contentStage.isMorph
                    NumberAnimation {
                        duration: masterWindow.isVisible ? Motion.open : Motion.close
                        easing.type: masterWindow.isVisible ? Motion.openEasing : Motion.closeEasing
                    }
                }

                opacity: isMorph ? morphFade : (masterWindow.isVisible ? 1.0 : 0.0)
                visible: masterWindow.isVisible || opacity > 0
                Behavior on opacity {
                    enabled: !contentStage.isMorph
                    NumberAnimation {
                        // A drawer opens solid (it slides in from under the bar instead) and stays solid while it
                        // slides back, otherwise it would vanish halfway
                        duration: contentStage.isDrawer ? (masterWindow.isVisible ? 0 : Motion.close) : (masterWindow.isVisible ? Motion.normal : Motion.fast)
                        easing.type: Easing.OutCubic
                    }
                }

                MouseArea { anchors.fill: parent }

                SequentialAnimation {
                    id: switchFade
                    PropertyAction { target: widgetStack; property: "opacity"; value: 0 }
                    PauseAnimation { duration: 40 }
                    NumberAnimation { target: widgetStack; property: "opacity"; to: 1; duration: Motion.fast; easing.type: Easing.OutCubic }
                }

                StackView {
                    id: widgetStack
                    anchors.fill: parent
                    focus: true

                    replaceEnter: null
                    replaceExit: null
                    pushEnter: null
                    pushExit: null
                    popEnter: null
                    popExit: null

                    Keys.onEscapePressed: (event) => {
                        switchWidget("hidden", "");
                        event.accepted = true;
                    }

                    onCurrentItemChanged: {
                        if (currentItem) currentItem.forceActiveFocus();
                    }
                }
            }
        }

        Behavior on x {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Motion.resizeEasing }
        }
        Behavior on y {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Motion.resizeEasing }
        }
        Behavior on width {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Motion.resizeEasing }
        }
        Behavior on height {
            enabled: !masterWindow.disableMorph
            NumberAnimation { duration: masterWindow.morphDuration; easing.type: Motion.resizeEasing }
        }
    }

    function switchWidget(newWidget, arg) {
        if (newWidget === "hidden" && masterWindow.isClosing) return;

        masterWindow.switchGeneration++;
        let gen = masterWindow.switchGeneration;
        masterWindow.targetActive = newWidget;

        if (newWidget !== "guide") {
            masterWindow.userMoved = false;
        }

        if (delayedClear.running) {
            delayedClear.stop();
        }
        if (exitSafetyTimer.running) {
            exitSafetyTimer.stop();
        }

        if (newWidget === "hidden") {
            if (currentActive !== "hidden" && !masterWindow.isClosing) {
                let closingGen = gen;
                masterWindow.isClosing = true;
                masterWindow.targetActive = "hidden";

                let activeItem = widgetCache[currentActive] || widgetStack.currentItem;

                let finalizeClose = function() {
                    if (closingGen !== masterWindow.switchGeneration) return;
                    masterWindow.isClosing = false;
                    masterWindow.currentActive = "hidden";
                    masterWindow.morphDuration = masterWindow.exitDuration;
                    masterWindow.disableMorph = true;
                    masterWindow.isVisible = false;

                    for (let k in widgetCache) {
                        let it = widgetCache[k];
                        if (it) it.visible = false;
                    }
                    reportWidgetState();
                };

                if (activeItem && typeof activeItem.startExit === "function") {
                    exitSafetyTimer.scheduledGeneration = closingGen;
                    exitSafetyTimer.restart();
                    activeItem.startExit(finalizeClose);
                } else {
                    finalizeClose();
                }
            }
        } else {
            masterWindow.isClosing = false;
            let targetScreen = resolveTargetScreen();
            if (targetScreen && masterWindow.screen !== targetScreen) {
                masterWindow.screen = targetScreen;
            }
            executeSwitch(newWidget, arg, gen);
        }
    }

    function executeSwitch(newWidget, arg, gen) {
        if (gen !== masterWindow.switchGeneration || newWidget === "hidden") return;

        let targetScreen = resolveTargetScreen();
        if (targetScreen && masterWindow.screen !== targetScreen) {
            masterWindow.screen = targetScreen;
        }

        let t = getLayout(newWidget);
        if (!t || !t.w || !t.h || t.w < 10 || t.h < 10) {
            Qt.callLater(function() {
                if (gen === masterWindow.switchGeneration) {
                    executeSwitch(newWidget, arg, gen);
                }
            });
            return;
        }

        let cachedItem = ensureWidgetItem(newWidget, t);
        if (!cachedItem) {
            Qt.callLater(function() {
                if (gen === masterWindow.switchGeneration) {
                    executeSwitch(newWidget, arg, gen);
                }
            });
            return;
        }

        if (gen !== masterWindow.switchGeneration) return;

        if (cachedItem.targetMasterWidth !== undefined)  cachedItem.targetMasterWidth  = t.w;
        if (cachedItem.targetMasterHeight !== undefined) cachedItem.targetMasterHeight = t.h;

        let isComingFromHidden = (!masterWindow.isVisible || widgetStack.currentItem === null || masterWindow.currentActive === "hidden");

        masterWindow.currentActive = newWidget;
        masterWindow.activeArg = arg;

        let finalW = (typeof cachedItem.targetMasterWidth === "number" && cachedItem.targetMasterWidth >= 50) ? cachedItem.targetMasterWidth : t.w;
        let finalH = (typeof cachedItem.targetMasterHeight === "number" && cachedItem.targetMasterHeight >= 50) ? cachedItem.targetMasterHeight : t.h;
        if (typeof cachedItem.drawerHeight === "number" && cachedItem.drawerHeight >= 50) finalH = cachedItem.drawerHeight;
        let finalX = (finalW !== t.w) ? recenterX(t, finalW) : t.rx;
        let finalY = t.ry;
        if (isConvexAttached(newWidget)) {
            let p = convexPlace(newWidget, finalW, finalH, masterWindow.width, masterWindow.height, finalX);
            finalX = p.x; finalY = p.y; finalW = p.w;
        }

        if (!masterWindow.userMoved || !masterWindow.isCurrentDraggable) {
            masterWindow._animX = finalX;
            masterWindow._animY = finalY;
        }
        masterWindow._animW = finalW;
        masterWindow._animH = finalH;
        masterWindow._stageW = finalW;
        masterWindow._stageH = finalH;

        if (isComingFromHidden) {
            masterWindow.disableMorph = true;
        } else {
            masterWindow.morphDuration = masterWindow.morphDurationSwitch;
            masterWindow.disableMorph = false;
            // Like minflair: the new content fades in while the size morphs
            if (widgetStack.currentItem !== cachedItem) switchFade.restart();
        }

        if (newWidget === "wallpaper" && cachedItem.widgetArg !== undefined) cachedItem.widgetArg = arg;
        if (newWidget === "wallpaper" && cachedItem.refreshForDisplay !== undefined) cachedItem.refreshForDisplay();
        if (arg !== "" && cachedItem.activeMode !== undefined) cachedItem.activeMode = arg;
        if (arg !== "" && cachedItem.gotoTab !== undefined) cachedItem.gotoTab(arg);

        if (widgetStack.currentItem !== cachedItem) {
            widgetStack.replace(cachedItem, {}, StackView.Immediate);
        }

        for (let k in widgetCache) {
            let it = widgetCache[k];
            if (it && it !== cachedItem) {
                it.visible = false;
            }
        }
        cachedItem.visible = true;

        masterWindow.isVisible = true;

        if (isComingFromHidden) {
            Qt.callLater(function() {
                if (gen === masterWindow.switchGeneration && masterWindow.isVisible && masterWindow.currentActive === newWidget) {
                    masterWindow.disableMorph = false;
                }
            });
        }
    }

    Timer {
        id: exitSafetyTimer
        interval: Motion.close + 200
        property int scheduledGeneration: -1
        onTriggered: {
            if (scheduledGeneration === masterWindow.switchGeneration && masterWindow.isClosing) {
                masterWindow.isClosing = false;
                masterWindow.currentActive = "hidden";
                masterWindow.morphDuration = masterWindow.exitDuration;
                masterWindow.disableMorph = true;
                masterWindow.isVisible = false;
                for (let k in widgetCache) {
                    let it = widgetCache[k];
                    if (it) it.visible = false;
                }
                reportWidgetState();
            }
        }
    }

    Timer {
        id: delayedClear
        interval: 200
        property int scheduledGeneration: -1
        onTriggered: {
            if (masterWindow.currentActive === "hidden" && scheduledGeneration === masterWindow.switchGeneration) {
                masterWindow.disableMorph = true;
                for (let k in widgetCache) {
                    let it = widgetCache[k];
                    if (it) it.visible = false;
                }
            }
        }
    }
}
