pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property string hostname: ""
    property FileView _host: FileView {
        path: "/etc/hostname"
        blockLoading: true
        printErrors: false
        onLoaded: root.hostname = text().trim()
    }
}
