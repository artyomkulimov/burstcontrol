import SwiftUI
import AppKit

@MainActor final class AppModel: ObservableObject {
    @Published var saved: Settings?
    @Published var draft: Settings?
    @Published var busy = false
    @Published var saving = false
    @Published var status = "Connect your mouse, then refresh."
    @Published var error: String?
    @Published var lastRead: Date?
    @Published var hasBackup = FileManager.default.fileExists(atPath: MouseService.lastBackupURL.path)
    var dirty: Bool { saved != nil && draft != saved }
    @Published var connected = false
    @Published var telemetry: DeviceTelemetry?
    @Published var conflict: Settings?
    private let monitor = ConnectionMonitor()
    private var loop: Task<Void, Never>?
    private var generation = 0
    private var stageReadInFlight = false
    private var lastRefreshAttempt = Date.distantPast
    func start() {
        guard loop == nil else { return }
        monitor.changed = { [weak self] in Task { @MainActor in self?.presenceChanged() } }
        presenceChanged()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 75_000_000)
                guard !Task.isCancelled else { break }
                guard let self, NSApp.isActive else { continue }
                if Date().timeIntervalSince(self.lastRefreshAttempt) >= (self.connected ? 15 : 3) {
                    self.refresh()
                } else { self.refreshStage() }
            }
        }
    }
    func refreshStage() {
        guard connected, !busy, !stageReadInFlight, conflict == nil else { return }
        stageReadInFlight = true
        let token = generation
        Task {
            defer { stageReadInFlight = false }
            do {
                let update = try await MouseService.shared.activeStage()
                guard token == generation, !busy, conflict == nil else { return }
                guard saved?.profile == update.profile else { lastRead = nil; refresh(); return }
                saved?.sensor[1] = update.stage
                draft?.sensor[1] = update.stage
            } catch {
                // Slow, complete read distinguishes transient errors from disconnects.
                if token == generation, !busy { lastRead = nil; refresh() }
            }
        }
    }
    func presenceChanged() {
        generation += 1
        if !monitor.connected {
            connected = false; status = "Not connected"; error = nil
        } else { refresh() }
    }
    func refresh() {
        guard !busy, conflict == nil else { return }
        lastRefreshAttempt = Date()
        guard monitor.connected else { connected = false; status = "Not connected"; return }
        busy = true
        let token = generation
        if !connected { status = "Connecting…" }
        Task {
            defer {
                busy = false
                // A USB presence callback can arrive during the first read.
                // Retry that superseded read even when the window is inactive.
                if token != generation, monitor.connected { refresh() }
            }
            do {
                let (value, telemetry) = try await MouseService.shared.readLive()
                guard token == generation else { return }
                self.telemetry = telemetry
                if let saved, let draft, dirty {
                    if saved.profile != value.profile || !saved.sameConfiguration(as: value) {
                        conflict = value
                    } else {
                        self.draft = value.mergingEdits(from: draft, baseline: saved)
                        self.saved = value
                    }
                } else { saved = value; draft = value }
                connected = true; lastRead = Date(); status = "Connected"; error = nil
            } catch {
                if token == generation {
                    connected = false
                    let message = error.localizedDescription
                    if message.contains("Input Monitoring") {
                        status = "Permission needed"; self.error = message
                    } else { status = "Mouse not responding"; self.error = nil }
                }
            }
        }
    }
    func resolveConflict(keepEdits: Bool) {
        guard let latest = conflict else { return }
        if keepEdits, let saved, let draft, saved.profile == latest.profile {
            self.draft = latest.mergingEdits(from: draft, baseline: saved)
        } else { draft = latest }
        saved = latest; conflict = nil
    }
    func apply() {
        guard !busy, let desired = draft, let expected = saved else { return }
        busy = true; saving = true; error = nil; status = "Saving…"
        Task {
            do { let value = try await MouseService.shared.apply(desired, expected: expected); saved = value; draft = value; lastRead = Date(); status = "Connected" }
            catch { self.error = error.localizedDescription; status = "Check mouse settings" }
            hasBackup = FileManager.default.fileExists(atPath: MouseService.lastBackupURL.path)
            saving = false; busy = false
        }
    }
    func restore() {
        guard !busy, let current = saved else { return }
        busy = true; error = nil
        Task {
            do {
                let backup = try await MouseService.shared.backup()
                guard backup.device == "10f5:5004", backup.settings.profile == current.profile else { throw MouseError("Backup belongs to a different profile.") }
                // Copy only mapped fields onto the fresh baseline; preserve all other bytes.
                var value = current
                value.debounceMS = backup.settings.debounceMS
                value.pollingIndex = backup.settings.pollingIndex
                value.motionSyncEnabled = backup.settings.motionSyncEnabled
                value.angleSnapping = backup.settings.angleSnapping
                value.liftOffMode = backup.settings.liftOffMode
                for i in 0..<5 { value.setDPI(i, backup.settings.dpi(i)) }
                draft = value; status = "Previous settings loaded · review and apply"
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func binding(_ key: WritableKeyPath<Settings, Int>) -> Binding<Int> {
        Binding(get: { self.draft?[keyPath: key] ?? 0 }, set: { self.draft?[keyPath: key] = $0 })
    }
}

@main struct BurstControlApp: App {
    init() {
        if CommandLine.arguments.contains("--read") || CommandLine.arguments.contains("--verify-writes") || CommandLine.arguments.contains("--status") {
            do {
                let semaphore = DispatchSemaphore(value: 0)
                Task.detached {
                    do {
                        if CommandLine.arguments.contains("--status") {
                            let value = try await MouseService.shared.telemetry()
                            let data = try JSONEncoder().encode(value)
                            print(String(data: data, encoding: .utf8)!)
                            semaphore.signal(); return
                        }
                        let value = CommandLine.arguments.contains("--verify-writes") ? try await MouseService.shared.verifyWrites() : try await MouseService.shared.read(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(data: try encoder.encode(value), encoding: .utf8)!) }
                    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
                    semaphore.signal()
                }
                semaphore.wait(); exit(0)
            }
        }
    }
    var body: some Scene {
        WindowGroup("Burst Control") { ContentView() }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 860, height: 650)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
