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
    @Published var conflict: Settings?
    private let monitor = ConnectionMonitor()
    private var loop: Task<Void, Never>?
    private var generation = 0
    func start() {
        guard loop == nil else { return }
        monitor.changed = { [weak self] in Task { @MainActor in self?.presenceChanged() } }
        presenceChanged()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                if NSApp.isActive { self?.refresh() }
            }
        }
    }
    func presenceChanged() {
        generation += 1
        if !monitor.connected {
            connected = false; status = "Receiver unplugged"; error = nil
        } else { refresh() }
    }
    func refresh() {
        guard !busy, conflict == nil else { return }
        guard monitor.connected else { connected = false; status = "Receiver unplugged"; return }
        busy = true
        let token = generation
        if !connected { status = "Connecting…" }
        Task {
            do {
                let value = try await MouseService.shared.read()
                guard token == generation else { busy = false; return }
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
            busy = false
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

struct ContentView: View {
    @StateObject private var model = AppModel()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Burst II Air").font(.system(size: 22, weight: .semibold))
                    Label(model.status, systemImage: model.connected ? "circle.fill" : "circle")
                        .font(.system(size: 15)).foregroundStyle(model.connected ? .green : .secondary)
                }
                Spacer()
                Menu {
                    Text(model.saved.map { "Onboard profile \($0.profileIndex + 1) of \($0.profile[1])" } ?? "Burst II Air")
                    Button("Load previous settings") { model.restore() }.disabled(!model.hasBackup || model.busy || !model.connected)
                    Button("Show backup folder") { NSWorkspace.shared.open(MouseService.directory) }.disabled(!model.hasBackup)
                } label: { Image(systemName: "ellipsis.circle").font(.title2) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Device details")
            }.padding(20)
            Divider()
            if let settings = model.draft {
                Form {
                    Section("Response") {
                        Picker("Debounce", selection: model.binding(\.debounceMS)) {
                            ForEach(0...10, id: \.self) { Text("\($0) ms").tag($0) }
                        }
                        Picker("Polling rate", selection: model.binding(\.pollingIndex)) {
                            ForEach(0..<4) { Text("\([125,250,500,1000][$0]) Hz").tag($0) }
                        }
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Text("DPI speeds").font(.system(size: 16, weight: .semibold))
                                Spacer()
                                if model.connected, let saved = model.saved, let stage = saved.activeStage {
                                    Text("\(saved.dpi(stage)) DPI active").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.accentColor)
                                }
                            }
                            HStack(spacing: 14) {
                                ForEach(0..<5) { i in
                                    DPIEditor(value: Binding(get: { model.draft?.dpi(i) ?? 800 }, set: { model.draft?.setDPI(i, $0) }), stage: i, active: model.connected && model.saved?.activeStage == i, changed: model.saved?.dpi(i) != model.draft?.dpi(i))
                                }
                            }
                            Text("Click a value to edit. Switch speeds with the mouse’s DPI button.")
                                .font(.system(size: 14)).foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                    }
                    Section("Tracking") {
                        Picker("Lift-off distance", selection: model.binding(\.liftOffMode)) {
                            Text("Very low").tag(0); Text("Low").tag(1)
                            if settings.liftOffMode > 1 { Text("Custom").tag(settings.liftOffMode) }
                        }
                        Toggle("Angle snapping", isOn: Binding(get: { model.draft?.angleSnapping != 0 }, set: { model.draft?.angleSnapping = $0 ? 1 : 0 }))
                            .help("Straightens small deviations when moving in a line.")
                        Toggle("Motion sync", isOn: Binding(get: { model.draft?.motionSyncEnabled ?? false }, set: { model.draft?.motionSyncEnabled = $0 }))
                            .help("Synchronizes sensor sampling with USB reports.")
                    }
                }.formStyle(.grouped).disabled(model.saving)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cable.connector").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Connect your mouse").font(.headline)
                    Text("Plug in the USB receiver and switch the mouse to 2.4 GHz.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("Settings will appear automatically.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            if let latest = model.conflict {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The mouse’s settings changed while you were editing.")
                    HStack {
                        Button("Use mouse settings") { model.resolveConflict(keepEdits: false) }
                        Button("Keep my edits") { model.resolveConflict(keepEdits: true) }
                            .disabled(latest.profile != model.saved?.profile)
                    }
                }.padding(20)
            }
            if model.dirty {
                Divider()
                HStack {
                    Text("Unsaved changes").foregroundStyle(.secondary)
                    Spacer()
                    Button("Revert") { model.draft = model.saved }.disabled(model.saving)
                    Button("Apply") { model.apply() }.keyboardShortcut(.defaultAction)
                        .disabled(model.busy || !model.connected || model.conflict != nil)
                }.padding(20)
            }
        }
        .font(.system(size: 16)).controlSize(.large)
        .frame(minWidth: 700, idealWidth: 760, minHeight: 640, idealHeight: 700)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
}

private struct DPIEditor: View {
    @Binding var value: Int
    let stage: Int
    let active: Bool
    let changed: Bool
    @State private var text = ""
    @FocusState private var focused: Bool
    private var parsed: Int? {
        guard let number = Int(text), (50...26000).contains(number), number % 50 == 0 else { return nil }
        return number
    }
    var body: some View {
        VStack(spacing: 8) {
            Text("\(stage + 1)").font(.system(size: 13)).foregroundStyle(.secondary)
            TextField("DPI", text: $text)
                .labelsHidden()
                .textFieldStyle(.plain).multilineTextAlignment(.center)
                .font(.system(size: 25, weight: active ? .semibold : .regular, design: .rounded))
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .accessibilityLabel("DPI stage \(stage + 1)")
                .focused($focused)
                .onChange(of: text) { _ in if let number = parsed { value = number } }
                .onChange(of: focused) { active in if !active { text = String(value) } }
                .onChange(of: value) { number in if !focused { text = String(number) } }
                .onAppear { text = String(value) }
                .help("50–26,000 DPI, in steps of 50. Invalid input reverts when leaving the field.")
            Capsule().fill(active ? Color.accentColor : Color.clear).frame(height: 3)
            Text(changed ? "Edited" : active ? "Active" : " ")
                .font(.system(size: 13)).foregroundStyle(changed ? Color.orange : Color.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 6)
    }
}

@main struct BurstControlApp: App {
    init() {
        if CommandLine.arguments.contains("--read") || CommandLine.arguments.contains("--verify-writes") {
            do {
                let semaphore = DispatchSemaphore(value: 0)
                Task.detached {
                    do { let value = CommandLine.arguments.contains("--verify-writes") ? try await MouseService.shared.verifyWrites() : try await MouseService.shared.read(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(data: try encoder.encode(value), encoding: .utf8)!) }
                    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
                    semaphore.signal()
                }
                semaphore.wait(); exit(0)
            }
        }
    }
    var body: some Scene {
        WindowGroup("Burst Control") { ContentView() }
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
