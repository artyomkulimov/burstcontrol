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
                value.motionSync = backup.settings.motionSync
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
    private let accent = Color(red: 0.65, green: 0.94, blue: 0.48)
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "computermouse.fill").font(.system(size: 34)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("BURST CONTROL").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(accent)
                    Text("Your mouse. Your settings.").font(.system(size: 26, weight: .semibold))
                    Text("Burst II Air  /  2.4 GHz USB").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.busy || model.dirty).keyboardShortcut("r")
            }.padding(28)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let settings = model.draft {
                        HStack(spacing: 14) {
                            metric("DEBOUNCE", "\(model.saved?.debounceMS ?? 0)", "ms")
                            metric("POLLING", "\([125,250,500,1000][model.saved?.pollingIndex ?? 0])", "Hz")
                            metric("PROFILE", "\(settings.profileIndex + 1)", "of \(settings.profile[1])")
                        }
                        GroupBox {
                            VStack(spacing: 18) {
                                setting("Debounce", detail: "Delay configured in the mouse firmware.") {
                                    Picker("Debounce", selection: model.binding(\.debounceMS)) {
                                        ForEach(0...10, id: \.self) { Text("\($0) ms").tag($0) }
                                    }.labelsHidden().frame(width: 125)
                                }
                                Divider()
                                setting("Polling rate", detail: "How frequently the mouse reports to your Mac.") {
                                    Picker("Polling rate", selection: model.binding(\.pollingIndex)) {
                                        ForEach(0..<4) { Text("\([125,250,500,1000][$0]) Hz").tag($0) }
                                    }.labelsHidden().frame(width: 125)
                                }
                            }.padding(14)
                        } label: { Text("RESPONSE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2) }
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Five DPI stages").font(.headline)
                                Text("50–26,000 DPI, in steps of 50. Your stage selection and enabled stages are preserved.").font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    ForEach(0..<5) { i in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("STAGE \(i + 1)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                                            TextField("DPI stage \(i + 1)", value: Binding(get: { model.draft?.dpi(i) ?? 800 }, set: { model.draft?.setDPI(i, $0) }), format: .number.grouping(.never))
                                                .textFieldStyle(.roundedBorder).accessibilityLabel("DPI stage \(i + 1)")
                                            Stepper("Adjust DPI stage \(i + 1)", value: Binding(get: { model.draft?.dpi(i) ?? 800 }, set: { model.draft?.setDPI(i, $0) }), in: 50...26000, step: 50).labelsHidden()
                                        }.frame(maxWidth: .infinity)
                                    }
                                }
                            }.padding(14)
                        } label: { Text("SENSITIVITY").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2) }
                        GroupBox {
                            VStack(spacing: 18) {
                                setting("Lift-off distance", detail: "Tracking cutoff when lifting the mouse.") {
                                    Picker("Lift-off distance", selection: model.binding(\.liftOffMode)) {
                                        Text("Very low").tag(0); Text("Low").tag(1)
                                        if settings.liftOffMode > 1 { Text("Custom (\(settings.liftOffMode))").tag(settings.liftOffMode) }
                                    }.labelsHidden().frame(width: 170)
                                }
                                Divider()
                                setting("Angle snapping", detail: "Straight-line correction applied by the sensor.") { binaryPicker("Angle snapping", key: \.angleSnapping, raw: settings.angleSnapping) }
                                Divider()
                                setting("Motion sync", detail: settings.motionSync > 1 ? "Firmware reports \(settings.motionSync); editing is unavailable until verified." : "Sensor synchronization preference.") { binaryPicker("Motion sync", key: \.motionSync, raw: settings.motionSync).disabled((model.saved?.motionSync ?? 255) > 1) }
                            }.padding(14)
                        } label: { Text("TRACKING").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2) }
                        Text("Settings are read on demand. No background service, input interception, or continuous USB polling. You can quit after applying.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 18) {
                            Image(systemName: "cable.connector").font(.system(size: 42)).foregroundStyle(.secondary)
                            Text("Connect your Burst II Air").font(.title2)
                            Text("Use the USB dongle and switch the mouse to 2.4 GHz.").foregroundStyle(.secondary)
                            Button("Read mouse settings") { model.refresh() }.disabled(model.busy)
                        }.frame(maxWidth: .infinity).padding(70)
                    }
                    if let error = model.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                }.padding(28).disabled(model.busy)
            }
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.dirty ? "Unapplied changes" : model.status).font(.system(size: 12, weight: .medium))
                    if let date = model.lastRead { Text("Last read \(date.formatted(date: .omitted, time: .standard))").font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                Menu("Backups") {
                    Button("Load previous settings") { model.restore() }.disabled(!model.hasBackup || model.busy || model.saved == nil)
                    Button("Show backup folder") { NSWorkspace.shared.open(MouseService.directory) }.disabled(!model.hasBackup)
                }.fixedSize()
                Button("Discard") { model.draft = model.saved }.disabled(!model.dirty || model.busy)
                Button("Apply to mouse") { model.apply() }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                    .disabled(!model.dirty || model.busy).keyboardShortcut(.return, modifiers: .command)
            }.padding(20)
        }
        .frame(minWidth: 740, idealWidth: 780, minHeight: 720, idealHeight: 850)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onAppear { model.refresh() }
    }
    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) { Text(value).font(.system(size: 34, weight: .medium, design: .rounded)); Text(unit).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
    private func setting<C: View>(_ name: String, detail: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) { Text(name).font(.system(size: 13, weight: .medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(); control()
        }
    }
    private func binaryPicker(_ title: String, key: WritableKeyPath<Settings, Int>, raw: Int) -> some View {
        Picker(title, selection: model.binding(key)) {
            Text("Off").tag(0); Text("On").tag(1)
            if raw > 1 { Text("Unknown (\(raw))").tag(raw) }
        }.labelsHidden().frame(width: 170)
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
            .windowStyle(.hiddenTitleBar)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
