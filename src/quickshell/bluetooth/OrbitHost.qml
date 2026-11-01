/*
 * Brain Shell
 * Copyright (C) 2026 Venkat Saahit Kamu (Brainitech)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import QtQuick
import qs.Services
import "../vendor/orbitBluetooth/components/common"
import "../vendor/orbitBluetooth/components/delay"
import "../vendor/orbitBluetooth/components/noise"
import "../vendor/orbitBluetooth/components/pairing"
import "../vendor/orbitBluetooth/components/together"
import "../vendor/orbitBluetooth/components/volume"
import "../vendor/orbitBluetooth/components/wear"

// Background half of Orbit Bluetooth (vendor/orbitBluetooth), modelled on its
// OrbitBluetoothDaemon.qml. The orbit view (BluetoothPopup) finds it through
// PluginService.pluginDaemonInstances and reads what it publishes from
// PluginService.globalVars.
//
// Left out on purpose:
//   VolumeOverlay / VolumeKeys — Orbit's own volume OSD and key binding;
//                                Serpantinum has its OSD (and keys are niri-only)
//   DMS pairing modal          — needs the DMS backend's bluez agent
//   UninstallSweep / reports   — DMS plugin manager features
Item {
    id: root

    readonly property string pluginId: "orbitBluetooth"

    Prefs { id: prefs }

    readonly property alias anc: ancService
    AncService {
        id: ancService
        active: prefs.ancEnabled
        engine: prefs.ancEngine
        chatOffOnDisconnect: prefs.ancChatOff
        wearPause: prefs.wearPause
        publish: map => root._publish("anc", map)
    }

    WearPause {
        id: wearPause
        ancService: ancService
        together: audioRoute.together
        active: prefs.wearPause
    }

    readonly property alias pictureLookup: pictureService
    PictureService {
        id: pictureService
        active: prefs.realPictures
        clearToken: prefs.picturesClear
        publish: map => root._publish("pictures", map)
    }

    readonly property alias route: audioRoute
    AudioRoute {
        id: audioRoute
        prefs: prefs
        publish: map => root._publish("route", map)
    }

    HabitLog {
        session: audioRoute.together
        prefs: prefs
    }

    readonly property alias newDevices: newDeviceWatch
    NewDeviceWatch {
        id: newDeviceWatch
        prefs: prefs
        pictureLookup: pictureService
        anc: ancService
        onShownChanged: root._publish("sheetShown", shown)
    }

    DisconnectDelays {
        publish: value => root._publish("disconnectDelays", value)
    }

    DeviceLog {
        publish: (name, value) => root._publish(name, value)
    }

    function _publish(name, value) {
        PluginService.setGlobalVar(pluginId, name, value)
    }

    Component.onCompleted: PluginService.registerDaemon(pluginId, root)
}
