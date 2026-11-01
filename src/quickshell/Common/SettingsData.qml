pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Plugin settings in ~/.config/serpantinum/plugin_settings.json
// ({ pluginId: { key: value } }), plus the few DMS settings plugins read.
QtObject {
    id: root

    property bool reduceMotion: false
    readonly property string pluginSettingsPath:
        (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/serpantinum/plugin_settings.json"
    property var pluginSettings: ({})
    signal pluginSettingsLoaded()

    function getPluginSettingsForPlugin(id) { return pluginSettings[id] || ({}) }

    function setPluginSetting(id, key, value) {
        const next = Object.assign({}, pluginSettings)
        next[id] = Object.assign({}, next[id] || {})
        next[id][key] = value
        pluginSettings = next
        _file.setText(JSON.stringify(next, null, 2))
    }

    property FileView _file: FileView {
        path: root.pluginSettingsPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            try { root.pluginSettings = JSON.parse(text() || "{}") } catch (e) { root.pluginSettings = {} }
            root.pluginSettingsLoaded()
        }
        onLoadFailed: root.pluginSettingsLoaded()
    }

    // DMS bar/OSD settings read by plugin pop-ups
    enum Position { Top, Bottom, Left, Right, TopCenter, BottomCenter, LeftCenter, RightCenter }
    property int osdPosition: SettingsData.Position.RightCenter
    property int dankBarSpacing: 4
    property var screenPreferences: ({})
    property var desktopWidgetInstances: []
    function getPrimaryBarConfig() { return { position: SettingsData.Position.Top } }
    function getFilteredScreens(kind) { return Quickshell.screens }
    function updateDesktopWidgetInstanceConfig(id, cfg) {}
}
