pragma Singleton
import QtQuick
import Quickshell

QtObject {
    readonly property string _home: Quickshell.env("HOME")
    readonly property url config:   "file://" + (Quickshell.env("XDG_CONFIG_HOME") || _home + "/.config") + "/serpantinum"
    readonly property url state:    "file://" + (Quickshell.env("XDG_STATE_HOME") || _home + "/.local/state") + "/serpantinum"
    readonly property url xdgCache: "file://" + (Quickshell.env("XDG_CACHE_HOME") || _home + "/.cache")

    // Same as DMS: decode, drop the scheme
    function strip(u) { return decodeURIComponent(String(u)).replace("file://", "") }
    function expandTilde(p) { return String(p).replace(/^~(?=\/|$)/, _home) }
}
