// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation
import IOBluetooth

/// IOBluetooth can report a headset as disconnected while macOS plays audio
/// through it. CoreAudio publishes a Bluetooth route only for a device that is
/// connected to this Mac, so together they answer "connected here" without
/// paging anything.
enum BluetoothAudioRoutes {
    static func isConnected(_ device: IOBluetoothDevice, routes: Set<String>) -> Bool {
        if device.isConnected() { return true }
        guard let id = device.addressString else { return false }
        return routes.contains(id.lowercased())
    }

    /// Addresses in IOBluetooth's lowercase, dash-separated form.
    static func connectedAddresses() -> Set<String> {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return Set(devices.compactMap { device in
            var transport: UInt32 = 0
            guard read(device, kAudioDevicePropertyTransportType, &transport),
                  transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
            else { return nil }
            var uid: CFString = "" as CFString
            guard read(device, kAudioDevicePropertyDeviceUID, &uid) else { return nil }
            return self.address(fromUID: uid as String)
        })
    }

    /// Bluetooth audio device UIDs look like "BC-87-FA-97-BD-3C:output".
    static func address(fromUID uid: String) -> String? {
        let candidate = uid.prefix { $0 != ":" }
        let octets = candidate.split(separator: "-", omittingEmptySubsequences: false)
        guard octets.count == 6, octets.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else {
            return nil
        }
        return candidate.lowercased()
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer)) == noErr
        }
    }
}
