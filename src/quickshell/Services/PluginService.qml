pragma Singleton
import QtQuick
import qs.Common

// Minimal DMS plugin host: saved plugin data (SettingsData), shared global
// variables and the daemon instances a plugin's views look up.
QtObject {
    id: root

    signal pluginDataChanged(string pluginId)
    signal globalVarChanged(string pluginId, string varName)

    property var globalVars: ({})
    property var pluginDaemonInstances: ({})
    // Other DMS plugins Orbit integrates with; none here
    property var availablePlugins: ({})

    function registerDaemon(id, instance) {
        const next = Object.assign({}, pluginDaemonInstances)
        next[id] = instance
        pluginDaemonInstances = next
    }

    function setGlobalVar(id, name, value) {
        const next = Object.assign({}, globalVars)
        next[id] = Object.assign({}, next[id] || {})
        next[id][name] = value
        globalVars = next
        globalVarChanged(id, name)
    }
    function getGlobalVar(id, name, def) {
        const v = (globalVars[id] || {})[name]
        return v === undefined ? def : v
    }

    function savePluginData(id, key, value) {
        SettingsData.setPluginSetting(id, key, value)
        pluginDataChanged(id)
        return true
    }
    function loadPluginData(id, key, def) {
        const v = SettingsData.getPluginSettingsForPlugin(id)[key]
        return v === undefined ? def : v
    }

    // Vendored plugins are not installed DMS plugins: no path, so Orbit's
    // UninstallSweep never mistakes a reload for an uninstall
    function getPluginPath(id) { return "" }

    property Connections _loaded: Connections {
        target: SettingsData
        function onPluginSettingsLoaded() {
            for (const id in SettingsData.pluginSettings) root.pluginDataChanged(id)
        }
    }
}
