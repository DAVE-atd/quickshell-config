// Wireframe of a tiling layout (HyprLayout.layouts[i].rects); the main window is drawn solid.
import QtQuick

Item {
    id: root
    property var rects: []
    property color color: "white"
    property real gap: 2
    property real cornerRadius: 2

    Repeater {
        model: root.rects
        Rectangle {
            x: Math.round(modelData[0] * root.width + root.gap / 2)
            y: Math.round(modelData[1] * root.height + root.gap / 2)
            width: Math.round(modelData[2] * root.width - root.gap)
            height: Math.round(modelData[3] * root.height - root.gap)
            radius: root.cornerRadius
            color: root.color
            opacity: index === 0 ? 1 : 0.45
        }
    }
}
