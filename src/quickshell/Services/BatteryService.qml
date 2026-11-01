pragma Singleton
import QtQuick
import Quickshell.Services.UPower

QtObject {
    readonly property bool batteryAvailable: !!(UPower.displayDevice && UPower.displayDevice.isLaptopBattery)
}
