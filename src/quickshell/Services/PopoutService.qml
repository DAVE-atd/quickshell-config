pragma Singleton
import QtQuick

// No DMS pop-out manager: no pairing modal, no "island" OSD router
QtObject {
    property var dankIslandRouter: null
    function ensureBluetoothPairingModal() { return null }
}
