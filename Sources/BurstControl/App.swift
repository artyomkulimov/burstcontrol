import SwiftUI
import AppKit

@MainActor final class AppModel: ObservableObject {
    @Published var saved: Settings?
    @Published var draft: Settings?
    @Published var busy = false
    @Published var status = "Connect your mouse, then refresh."
    @Published var error: String?
    @Published var lastRead: Date?
    @Published var hasBackup = FileManager.default.fileExists(atPath: MouseService.lastBackupURL.path)
    var dirty: Bool { saved != nil && draft != saved }
    func refresh() {
        guard !busy else { return }; busy = true; error = nil; status = "Reading mouse…"
        Task {
            do { let value = try await MouseService.shared.read(); saved = value; draft = value; lastRead = Date(); status = "Read from mouse · ready" }
            catch { self.error = error.localizedDescription; status = "Unable to read mouse" }
            busy = false
        }
    }
    func apply() {
        guard !busy, let desired = draft, let expected = saved else { return }
        busy = true; error = nil; status = "Saving and verifying…"
        Task {
            do { let value = try await MouseService.shared.apply(desired, expected: expected); saved = value; draft = value; lastRead = Date(); status = "Saved to mouse · read-back verified" }
            catch { self.error = error.localizedDescription; status = "Check mouse settings" }
            hasBackup = FileManager.default.fileExists(atPath: MouseService.lastBackupURL.path)
            busy = false
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
                    Text("Burst II Air").font(.headline)
                    Text(model.saved.map { "2.4 GHz · Profile \($0.profileIndex + 1) of \($0.profile[1])" } ?? "2.4 GHz USB receiver")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Read settings from mouse").accessibilityLabel("Refresh")
                    .disabled(model.busy || model.dirty).keyboardShortcut("r")
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
                        ForEach(0..<5) { i in
                            LabeledContent("Stage \(i + 1)") {
                                DPIEditor(value: Binding(get: { model.draft?.dpi(i) ?? 800 }, set: { model.draft?.setDPI(i, $0) }))
                            }
                        }
                    } header: { Text("DPI stages") } footer: {
                        Text("50–26,000 DPI in steps of 50. Switch stages with the mouse’s DPI button.")
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
                }.formStyle(.grouped).disabled(model.busy)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cable.connector").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Connect your mouse").font(.headline)
                    Text("Plug in the USB receiver and switch the mouse to 2.4 GHz.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Read settings") { model.refresh() }.disabled(model.busy)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            Divider()
            HStack(spacing: 10) {
                Text(model.dirty ? "Unsaved changes" : model.status)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Menu {
                    Button("Load previous settings") { model.restore() }.disabled(!model.hasBackup || model.busy || model.saved == nil)
                    Button("Show backup folder") { NSWorkspace.shared.open(MouseService.directory) }.disabled(!model.hasBackup)
                } label: { Image(systemName: "clock.arrow.circlepath") }
                    .menuStyle(.borderlessButton).fixedSize().help("Backups").accessibilityLabel("Backups")
                Button("Revert") { model.draft = model.saved }.disabled(!model.dirty || model.busy)
                Button("Apply") { model.apply() }.keyboardShortcut(.defaultAction)
                    .disabled(!model.dirty || model.busy)
            }.padding(16)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 690, idealHeight: 740)
        .onAppear { model.refresh() }
    }
}

private struct DPIEditor: View {
    @Binding var value: Int
    @State private var text = ""
    @FocusState private var focused: Bool
    private var parsed: Int? {
        guard let number = Int(text), (50...26000).contains(number), number % 50 == 0 else { return nil }
        return number
    }
    var body: some View {
        HStack(spacing: 8) {
            TextField("DPI", text: $text)
                .multilineTextAlignment(.trailing).frame(width: 75)
                .focused($focused)
                .onChange(of: text) { _ in if let number = parsed { value = number } }
                .onChange(of: focused) { active in if !active { text = String(value) } }
                .onChange(of: value) { number in if !focused { text = String(number) } }
                .onAppear { text = String(value) }
                .help("Enter a multiple of 50 between 50 and 26,000. Invalid input is reverted when leaving the field.")
            Text("DPI").foregroundStyle(.secondary)
            Stepper("Adjust DPI", value: $value, in: 50...26000, step: 50).labelsHidden()
        }
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
