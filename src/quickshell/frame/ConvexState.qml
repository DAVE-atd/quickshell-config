// Bar style "convex": geometry of the open popup, shared between Main.qml (writes) and the bar
// (bar/ConvexBulges.qml grows a bulge above it) and the popups (square corners on attached sides).
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // Set by Main.qml while a popup is attached to the frame
    property bool active: false
    property string screenName: ""
    property real x: 0
    property real y: 0
    property real w: 0
    property real h: 0
    property real opacity: 0

    // Width of each bar's centre bulge incl. padding, per screen name (bar/ConvexBulges.qml).
    // The OSD (popouts/Osd.qml) grows out of it and covers it while it shows.
    property var centerWidths: ({})
    function setCenterW(screen, w) {
        if (centerWidths[screen] === w) return;
        let m = Object.assign({}, centerWidths);
        m[screen] = w;
        centerWidths = m;
    }
    function centerW(screen) { return centerWidths[screen] || 0 }

    // Extents { x0, x1 } of each bar's bulges (left / center / right) per screen name
    // (bar/ConvexBulges.qml). Main.qml grows a dropdown out of the nearest one.
    property var sectionMap: ({})
    function setSections(screen, list) {
        // Only on real changes: every write re-evaluates Main.qml's morph bindings
        if (JSON.stringify(sectionMap[screen] || []) === JSON.stringify(list)) return;
        let m = Object.assign({}, sectionMap);
        m[screen] = list;
        sectionMap = m;
    }
    function sectionsFor(screen) { return sectionMap[screen] || [] }

    // Open tray menu (popouts/TrayBase.qml, own window): the bar grows a bulge of its width above it
    property string trayScreen: ""
    property real trayX: 0
    property real trayW: 0
    property real trayOpacity: 0

    // Sides of the popup that touch the bar or the frame
    property bool squareTop: false
    property bool squareBottom: false
    property bool squareLeft: false
    property bool squareRight: false

    // Corner radius for a popup background: 0 on sides that touch the frame
    function tl(r) { return active && (squareTop || squareLeft) ? 0 : r }
    function tr(r) { return active && (squareTop || squareRight) ? 0 : r }
    function bl(r) { return active && (squareBottom || squareLeft) ? 0 : r }
    function br(r) { return active && (squareBottom || squareRight) ? 0 : r }
    // Grow attached popups out of their edge instead of scaling from the center
    readonly property int origin: !active ? Item.Center
                                : squareTop && !squareBottom ? Item.Top
                                : squareBottom && !squareTop ? Item.Bottom
                                : squareLeft ? Item.Left
                                : squareRight ? Item.Right
                                : Item.Center
}
