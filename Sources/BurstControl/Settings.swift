import Foundation

struct Settings: Codable, Equatable, Sendable {
    var profile: [UInt8]
    var sensor: [UInt8]
    var debounce: [UInt8]
    var liftOff: [UInt8]
    var wireless: [UInt8]
    var profileIndex: Int { Int(profile[0]) }
    var pollingIndex: Int {
        get { Int(sensor[38]) }
        set { sensor[38] = UInt8(newValue) }
    }
    var motionSync: Int {
        get { Int(sensor[39]) }
        set { sensor[39] = UInt8(newValue) }
    }
    // Swarm II reads byte 39 with cmp 0 / setne (0x180146297).
    // Preserve noncanonical true values until explicitly edited.
    var motionSyncEnabled: Bool {
        get { motionSync != 0 }
        set { motionSync = newValue ? 1 : 0 }
    }
    var angleSnapping: Int {
        get { Int(sensor[37]) }
        set { sensor[37] = UInt8(newValue) }
    }
    var debounceMS: Int {
        get { Int(debounce[0]) }
        set { debounce[0] = UInt8(newValue) }
    }
    var liftOffMode: Int {
        get { Int(liftOff[0]) }
        set { liftOff[0] = UInt8(newValue) }
    }
    func dpi(_ index: Int) -> Int { (Int(sensor[2 + index * 2]) | (Int(sensor[3 + index * 2]) << 8)) * 50 + 50 }
    mutating func setDPI(_ index: Int, _ value: Int) {
        guard (0..<5).contains(index), (50...26000).contains(value), value % 50 == 0 else { return }
        let encoded = (value / 50) - 1
        sensor[2 + index * 2] = UInt8(encoded & 255)
        sensor[3 + index * 2] = UInt8(encoded >> 8)
    }
    func validate(against original: Settings) throws {
        guard profile == original.profile, sensor.count == 40, debounce.count == 1,
              liftOff.count == 4, wireless == original.wireless,
              debounceMS <= 10, (0...3).contains(pollingIndex) else { throw MouseError("Invalid settings") }
        guard (0...1).contains(motionSync) || motionSync == original.motionSync,
              (0...1).contains(angleSnapping) || angleSnapping == original.angleSnapping,
              (0...1).contains(liftOffMode) || liftOffMode == original.liftOffMode else { throw MouseError("Unsupported setting value") }
        for index in 0..<5 { guard (50...26000).contains(dpi(index)) else { throw MouseError("DPI must be 50–26000") } }
        let editable = Set(Array(2...11) + [37, 38, 39])
        for i in sensor.indices where !editable.contains(i) {
            guard sensor[i] == original.sensor[i] else { throw MouseError("Attempt to alter an unmapped sensor field") }
        }
        guard Array(liftOff.dropFirst()) == Array(original.liftOff.dropFirst()) else { throw MouseError("Unmapped lift-off bytes changed") }
    }
}

struct Backup: Codable {
    let created: Date
    let device: String
    let settings: Settings
}

actor MouseService {
    static let shared = MouseService()
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Burst Control")
    static var lastBackupURL: URL { directory.appendingPathComponent("last-backup.json") }
    private func snapshot(_ connection: HIDConnection) throws -> Settings {
        let profile = try connection.read(kind: 1, size: 2)
        guard profile.count == 2, profile[1] > 0, profile[1] <= 5, profile[0] < profile[1] else { throw MouseError("Unexpected mouse profile") }
        let settings = Settings(profile: profile,
            sensor: try connection.read(kind: 2, profile: profile[0], sub: 1, size: 40),
            debounce: try connection.read(kind: 6, size: 1),
            liftOff: try connection.read(kind: 7, size: 4),
            wireless: try connection.read(kind: 11, size: 2))
        guard settings.debounceMS <= 10, settings.pollingIndex <= 3 else { throw MouseError("Unrecognized mouse settings format") }
        guard try connection.read(kind: 1, size: 2) == profile else { throw MouseError("Profile changed while reading. Refresh again.") }
        return settings
    }
    func read() throws -> Settings { try snapshot(HIDConnection()) }
    func verifyWrites() throws -> Settings {
        let connection = try HIDConnection()
        let before = try snapshot(connection)
        try connection.write(kind: 2, profile: before.profile[0], sub: 1, data: before.sensor)
        guard try snapshot(connection) == before else { throw MouseError("Sensor round-trip changed data") }
        try connection.write(kind: 6, data: before.debounce)
        guard try snapshot(connection) == before else { throw MouseError("Debounce round-trip changed data") }
        try connection.write(kind: 7, data: [before.liftOff[0]])
        let after = try snapshot(connection)
        guard after == before else { throw MouseError("Lift-off round-trip changed data") }
        return after
    }
    func backup() throws -> Backup {
        let result = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: Self.lastBackupURL))
        let s = result.settings
        guard s.profile.count == 2, s.sensor.count == 40, s.debounce.count == 1,
              s.liftOff.count == 4, s.wireless.count == 2 else { throw MouseError("Backup has invalid field lengths") }
        try s.validate(against: s)
        return result
    }
    func apply(_ desired: Settings, expected: Settings) throws -> Settings {
        try desired.validate(against: expected)
        let connection = try HIDConnection()
        let current = try snapshot(connection)
        guard current == expected else { throw MouseError("The mouse changed since your last refresh. Refresh to load its current settings before applying.") }
        guard desired != current else { return current }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let backup = Backup(created: Date(), device: "10f5:5004", settings: current)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        try data.write(to: Self.directory.appendingPathComponent("backup-\(UUID().uuidString).json"), options: .atomic)
        try data.write(to: Self.lastBackupURL, options: .atomic)
        do {
            if desired.sensor != current.sensor {
                try connection.write(kind: 2, profile: current.profile[0], sub: 1, data: desired.sensor)
                guard try connection.read(kind: 2, profile: current.profile[0], sub: 1, size: 40) == desired.sensor else { throw MouseError("Sensor settings read-back mismatch") }
            }
            if desired.debounce != current.debounce {
                try connection.write(kind: 6, data: desired.debounce)
                guard try connection.read(kind: 6, size: 1) == desired.debounce else { throw MouseError("Debounce read-back mismatch") }
            }
            if desired.liftOff != current.liftOff {
                try connection.write(kind: 7, data: [desired.liftOff[0]])
                guard try connection.read(kind: 7, size: 4) == desired.liftOff else { throw MouseError("Lift-off read-back mismatch") }
            }
            let result = try snapshot(connection)
            guard result == desired else { throw MouseError("Final read-back differs from requested settings") }
            return result
        } catch {
            throw MouseError("\(error.localizedDescription) Some changes may have applied. Refresh to inspect; the previous values are saved in Backups.")
        }
    }
}
