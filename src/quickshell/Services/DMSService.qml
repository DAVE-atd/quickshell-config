pragma Singleton
import QtQuick

// No DMS backend (dms server); its signals are never emitted
QtObject {
    readonly property bool isConnected: false
    readonly property bool dmsAvailable: false
    readonly property int apiVersion: 0
    readonly property var capabilities: []
    signal bluetoothPairingRequest(var data)
}
