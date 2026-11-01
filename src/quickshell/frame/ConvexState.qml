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
