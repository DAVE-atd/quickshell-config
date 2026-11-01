pragma Singleton
import QtQuick

// DMS asks its own volume OSD to stay quiet with these; Serpantinum has no
// such hook, so they do nothing.
QtObject {
    property bool suppressOSD: false
    function suppressOSDTemporarily() {}
}
