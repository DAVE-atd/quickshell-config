pragma Singleton
import QtQuick
import Quickshell.Bluetooth

// The DMS BluetoothService subset plugins use, on Quickshell.Bluetooth.
// Like DMS without its backend: no bluez agent, so pairing works for
// devices that need no passcode (headphones, speakers, most mice).
QtObject {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: (adapter && adapter.enabled) ?? false
    readonly property bool discovering: (adapter && adapter.discovering) ?? false
    readonly property var devices: adapter ? adapter.devices : null

    readonly property QtObject log: QtObject {
        function info(...a) { console.info("[BluetoothService]", ...a) }
        function warn(...a) { console.warn("[BluetoothService]", ...a) }
        function debug(...a) {}
    }

    function setBluetoothEnabled(on) { if (adapter) adapter.enabled = on }
    function toggleBluetooth() { if (adapter) adapter.enabled = !adapter.enabled }

    function connectDeviceWithTrust(device) {
        if (!device) return
        device.trusted = true
        device.connect()
    }

    function pairDevice(device, callback) {
        if (!device) { if (callback) callback({ error: "Invalid device" }); return }
        device.trusted = true
        device.connect()
        if (callback) callback({ success: true })
    }
}
