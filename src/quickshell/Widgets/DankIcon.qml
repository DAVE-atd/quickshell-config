import QtQuick
import qs.Common

// Material Symbols Rounded ligature icon, as DMS's DIcon (variable font axes,
// no fill crossfade). The font comes from the material-symbols package.
Item {
    id: root

    property alias name: icon.text
    property alias size: icon.font.pixelSize
    property alias color: icon.color
    property bool filled: false
    property real fill: filled ? 1.0 : 0.0
    property int grade: Theme.isLightMode ? 0 : -25
    property int weight: filled ? 500 : 400
    property bool smoothTransform: false

    signal rotationCompleted

    implicitWidth: Math.round(size)
    implicitHeight: Math.round(size)

    Text {
        id: icon
        anchors.fill: parent
        font.family: "Material Symbols Rounded"
        font.pixelSize: Math.round(Theme.fontSizeMedium)
        font.weight: root.weight
        font.hintingPreference: Font.PreferNoHinting
        font.variableAxes: ({ "FILL": root.fill, "GRAD": root.grade, "opsz": 24, "wght": root.weight })
        color: Theme.surfaceText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: root.smoothTransform ? Text.QtRendering : Text.NativeRendering
    }

    Timer { id: rotationTimer; interval: 16; onTriggered: root.rotationCompleted() }
    onRotationChanged: rotationTimer.restart()
}
