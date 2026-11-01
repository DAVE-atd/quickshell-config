import QtQuick
import qs.Common

// DMS StyledText defaults (wrap, elide, plain text, theme color)
Text {
    property bool isMonospace: false
    color: Theme.surfaceText
    font.pixelSize: Theme.fontSizeMedium
    font.family: isMonospace ? "JetBrains Mono" : "Inter"
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
