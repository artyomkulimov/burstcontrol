import Foundation
import IOKit.hid

// USB presence notifications do not open a mouse or subscribe to its input reports.
final class ConnectionMonitor {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var changed: (() -> Void)?
    var connected: Bool {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return false }
        return !devices.isEmpty
    }
    init() {
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x10f5, kIOHIDProductIDKey: 0x5004] as CFDictionary)
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<ConnectionMonitor>.fromOpaque(context).takeUnretainedValue().changed?()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }
    deinit { IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) }
}
