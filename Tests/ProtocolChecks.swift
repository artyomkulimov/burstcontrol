import Foundation

@main struct ProtocolChecks {
    static func main() throws {
        // Captured packets from the successful hardware transaction.
        let acquire = try HIDConnection.packet(0x80, [])
        precondition(Array(acquire.prefix(6)) == [3, 0x81, 0x80, 0, 0, 1])
        let read = try HIDConnection.packet(0x82, [64, 0, 6, 0, 0, 0, 0, 1, 0, 0])
        precondition(Array(read.prefix(16)) == [3, 0xd4, 0x82, 10, 0, 1, 64, 0, 6, 0, 0, 0, 0, 1, 0, 0])
        do { _ = try HIDConnection.packet(0x82, Array(repeating: 0, count: 59)); fatalError("Oversize packet accepted") } catch is MouseError {}
        let fixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/settings.json"))
        let original = try JSONDecoder().decode(Settings.self, from: fixture)
        precondition((0..<5).map { original.dpi($0) } == [400, 800, 1200, 1600, 3200])
        precondition(original.motionSync == 255 && original.motionSyncEnabled)
        var motion = original
        motion.motionSyncEnabled = false
        precondition(motion.motionSync == 0)
        try motion.validate(against: original)
        motion.motionSyncEnabled = true
        precondition(motion.motionSync == 1)
        precondition(motion.sensor.dropLast() == original.sensor.dropLast())
        try motion.validate(against: original)
        precondition(original.activeStage == 3)
        var switched = original; switched.sensor[1] = 4
        precondition(switched.activeStage == 4 && switched.sameConfiguration(as: original))
        var edits = original; edits.setDPI(0, 650); edits.debounceMS = 2
        let merged = switched.mergingEdits(from: edits, baseline: original)
        precondition(merged.activeStage == 4 && merged.dpi(0) == 650 && merged.debounceMS == 2)
        try merged.validate(against: switched)
        var external = switched; external.pollingIndex = 3
        precondition(!external.sameConfiguration(as: original))
        let kept = external.mergingEdits(from: edits, baseline: original)
        precondition(kept.pollingIndex == 3 && kept.dpi(0) == 650)
        var invalid = original; invalid.sensor[1] = 255
        precondition(invalid.activeStage == nil)
        var changed = original
        changed.setDPI(4, 26000)
        precondition(changed.dpi(4) == 26000)
        precondition(changed.sensor.enumerated().allSatisfy { [10,11].contains($0.offset) || $0.element == original.sensor[$0.offset] })
        try changed.validate(against: original)
        changed.sensor[20] ^= 1
        do { try changed.validate(against: original); fatalError("Unmapped byte mutation accepted") } catch is MouseError {}
        changed = original; changed.profile[0] = 4
        do { try changed.validate(against: original); fatalError("Unexpected profile accepted") } catch is MouseError {}
        changed = original; changed.pollingIndex = 4
        do { try changed.validate(against: original); fatalError("Unsupported polling rate accepted") } catch is MouseError {}
        print("Protocol fixture, DPI encoding, bounds, and preservation checks passed.")
    }
}
