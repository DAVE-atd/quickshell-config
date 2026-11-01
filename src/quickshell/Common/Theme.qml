pragma Singleton
import QtQuick
import "../"

// DMS Theme tokens derived from Serpantinum's ThemeBackend.
QtObject {
    id: root

    readonly property bool isLightMode: false

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function _mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
    function snap(value, dpr) { const s = dpr || 1; return Math.round(value * s) / s }

    readonly property color _bg: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 1)

    readonly property color primary:     ThemeBackend.mauve
    readonly property color primaryText: _bg
    readonly property color secondary:   _mix(ThemeBackend.mauve, ThemeBackend.text, 0.45)
    readonly property color tertiary:    ThemeBackend.subtext0
    readonly property color error:       ThemeBackend.red
    readonly property color errorText:   _bg
    readonly property color success:     ThemeBackend.green
    readonly property color warning:     "#f9e2af"
    readonly property color info:        ThemeBackend.blue

    readonly property color surface:                 _bg
    readonly property color surfaceContainer:        _mix(_bg, ThemeBackend.text, 0.06)
    readonly property color surfaceContainerHigh:    _mix(_bg, ThemeBackend.text, 0.10)
    readonly property color surfaceContainerHighest: _mix(_bg, ThemeBackend.text, 0.15)
    readonly property color outline:                 withAlpha(ThemeBackend.text, 0.35)
    readonly property color surfaceText:             ThemeBackend.text
    readonly property color surfaceVariantText:      ThemeBackend.subtext0
    readonly property color widgetIconColor:         ThemeBackend.text

    readonly property real fontSizeSmall:  12
    readonly property real fontSizeMedium: 14
    readonly property real fontSizeLarge:  16
    readonly property real fontSizeXLarge: 20
    readonly property real spacingXS: 4
    readonly property real spacingS:  8
    readonly property real spacingM:  12
    readonly property real spacingL:  16
    readonly property real spacingXL: 24
    readonly property real cornerRadius: ThemeBackend.borderRadius
}
