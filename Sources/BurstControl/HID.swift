import Foundation
import IOKit.hid

struct MouseError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

final class HIDConnection {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private var opened = false
    init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x10f5, kIOHIDProductIDKey: 0x5004,
                                   kIOHIDDeviceUsagePageKey: 0xff00, kIOHIDDeviceUsageKey: 1]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, set.count == 1,
              let found = set.first else {
            throw MouseError("Connect one Burst II Air USB dongle and turn the mouse on. This build supports the 2.4 GHz dongle connection.")
        }
        device = found
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnNotPermitted {
            throw MouseError("macOS requires Input Monitoring permission to open this mouse interface. Enable the installed Burst Control app in System Settings → Privacy & Security → Input Monitoring, then quit and reopen it. If it is already enabled after a rebuild, remove its old entry and add the current app again. Burst Control does not capture input events.")
        }
        guard result == kIOReturnSuccess else { throw MouseError("Cannot open mouse HID interface (\(result)).") }
        opened = true
    }
    deinit { if opened { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) } }

    static func packet(_ command: UInt8, _ payload: [UInt8]) throws -> [UInt8] {
        guard payload.count <= 58 else { throw MouseError("Packet too large") }
        var bytes = [UInt8](repeating: 0, count: 64)
        bytes[0] = 3; bytes[2] = command; bytes[3] = UInt8(payload.count); bytes[5] = 1
        bytes.replaceSubrange(6..<(6 + payload.count), with: payload)
        bytes[1] = bytes[2...].reduce(0, &+)
        return bytes
    }
    func exchange(_ command: UInt8, _ payload: [UInt8] = []) throws -> [UInt8] {
        let packet = try Self.packet(command, payload)
        let sent = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 3, $0.baseAddress!, $0.count)
        }
        guard sent == kIOReturnSuccess else { throw MouseError("USB send failed (\(sent)). Reconnect the dongle and refresh.") }
        // Vendor transaction needs time to cross the wireless link. This sleeps only the worker.
        Thread.sleep(forTimeInterval: 0.05)
        var reply = [UInt8](repeating: 0, count: 64)
        reply[0] = 3
        var length = reply.count
        let received = reply.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 3, $0.baseAddress!, &length)
        }
        guard received == kIOReturnSuccess else { throw MouseError("USB read failed (\(received)). Wake the mouse and refresh.") }
        guard length >= 5, reply[0] == 3, reply[1] == command, reply[2] == 0,
              length >= 5 + Int(reply[3]) else { throw MouseError("Mouse returned an unexpected response; no further commands sent.") }
        let body = Array(reply[5..<(5 + Int(reply[3]))])
        guard body != [0xc0, 2] else { throw MouseError("Mouse is busy or rejected the command.") }
        return body
    }
    private func transaction<T>(_ work: () throws -> T) throws -> T {
        _ = try exchange(0x80)
        do {
            let value = try work()
            _ = try exchange(0x81)
            return value
        } catch {
            _ = try? exchange(0x81)
            throw error
        }
    }
    func read(kind: UInt8, profile: UInt8 = 0, sub: UInt8 = 0, size: Int) throws -> [UInt8] {
        guard (1...128).contains(size) else { throw MouseError("Invalid read size") }
        return try transaction {
            let request: [UInt8] = [64, 0, kind, profile, sub, 0, 0, UInt8(size), 0, 0]
            let header = try exchange(0x82, request)
            guard header.count == 11, Array(header.prefix(9)) == Array(request.prefix(9)),
                  header[10] > 0, header[10] <= 57 else { throw MouseError("Unexpected settings header") }
            var result: [UInt8] = []
            for sequence in 1...8 {
                let chunk = try exchange(0x82, [0x80 | UInt8(sequence)] + Array(repeating: 0, count: 57))
                guard chunk.count > 1, chunk[0] == 0x80 | UInt8(sequence),
                      result.count + chunk.count - 1 <= size else { throw MouseError("Invalid settings chunk") }
                result.append(contentsOf: chunk.dropFirst())
                if result.count == size { break }
            }
            guard result.count == size, result.reduce(0, &+) == header[9] else { throw MouseError("Settings checksum mismatch") }
            return result
        }
    }
    func write(kind: UInt8, profile: UInt8 = 0, sub: UInt8 = 0, data: [UInt8]) throws {
        guard !data.isEmpty, data.count <= 40, [UInt8(1), 2, 6, 7, 11].contains(kind) else { throw MouseError("Unsupported write") }
        try transaction {
            let request: [UInt8] = [64, 1, kind, profile, sub, 0, 0, UInt8(data.count), 0, data.reduce(0, &+)]
            let header = try exchange(0x82, request)
            guard header.count == 11, Array(header.prefix(10)) == request, header[10] > 0,
                  header[10] <= 57 else { throw MouseError("Unexpected write header") }
            let chunkSize = Int(header[10])
            for (index, offset) in stride(from: 0, to: data.count, by: chunkSize).enumerated() {
                _ = try exchange(0x82, [0x81 + UInt8(index)] + data[offset..<min(offset + chunkSize, data.count)])
            }
            guard try exchange(0x82, [0xc0]) == [0xc0, 0] else {
                throw MouseError("Write was not acknowledged. Refresh before retrying.")
            }
        }
    }
}
