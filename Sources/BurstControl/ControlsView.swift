import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        GlassControls {
            VStack(spacing: 0) {
                deviceHeader
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
                    .padding(.bottom, 26)

                if let settings = model.draft {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            dpiControls
                            HStack(alignment: .top, spacing: 24) {
                                responseControls
                                trackingControls(settings)
                            }
                            notices
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                    }
                    .disabled(model.saving)
                } else {
                    connectionPlaceholder
                    notices.padding(.horizontal, 28).padding(.bottom, 20)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.dirty { saveControls }
            }
        }
        .font(.system(size: 17))
        .controlSize(.large)
        .background { WindowBackdrop() }
        .background(ClickOutsideToEndEditing())
        .frame(minWidth: 760, idealWidth: 860, minHeight: 580, idealHeight: 650)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private var deviceHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "computermouse")
                .font(.system(size: 28, weight: .light))
                .frame(width: 58, height: 58)
                .controlGlass(in: RoundedRectangle(cornerRadius: 19))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Burst II Air")
                    .font(.system(size: 27, weight: .semibold))
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.connected ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(model.status).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 20)
            if model.connected, let telemetry = model.telemetry {
                VStack(alignment: .trailing, spacing: 5) {
                    if let percent = telemetry.batteryPercent {
                        Label("\(percent)%", systemImage: telemetry.batterySymbol)
                            .font(.system(size: 20, weight: .medium))
                            .monospacedDigit()
                            .help(telemetry.charging == true ? "Charging" : "Battery level reported by mouse")
                    } else {
                        Text("Battery unavailable").font(.system(size: 15))
                    }
                    Text(telemetry.transport)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 6)
            }
            Menu {
                Text(model.saved.map { "Onboard profile \($0.profileIndex + 1) of \($0.profile[1])" } ?? "Burst II Air")
                Button("Load previous settings") { model.restore() }
                    .disabled(!model.hasBackup || model.busy || !model.connected)
                Button("Show backup folder") { NSWorkspace.shared.open(MouseService.directory) }
                    .disabled(!model.hasBackup)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .controlGlass(in: Circle(), interactive: true)
            .accessibilityLabel("Device details")
            .help("Device details and backups")
        }
    }

    private var dpiControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("DPI speeds")
                Spacer()
                if model.connected, let saved = model.saved, let stage = saved.activeStage {
                    Text("\(saved.dpi(stage)) DPI active")
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
            }
            HStack(spacing: 8) {
                ForEach(0..<5) { stage in
                    DPIEditor(
                        value: Binding(
                            get: { model.draft?.dpi(stage) ?? 800 },
                            set: { model.draft?.setDPI(stage, $0) }
                        ),
                        stage: stage,
                        active: model.connected && model.saved?.activeStage == stage,
                        changed: model.saved?.dpi(stage) != model.draft?.dpi(stage)
                    )
                }
            }
            .padding(14)
            .controlGlass(in: RoundedRectangle(cornerRadius: 26))
        }
    }

    private var responseControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Response")
            VStack(spacing: 0) {
                settingRow("Debounce", height: 84) {
                    SettingMenu(
                        title: "Debounce",
                        selection: model.binding(\.debounceMS),
                        options: (0...10).map { ($0, "\($0) ms") }
                    )
                }
                rowDivider
                settingRow("Polling rate", height: 83) {
                    SettingMenu(
                        title: "Polling rate",
                        selection: model.binding(\.pollingIndex),
                        options: [125, 250, 500, 1000].enumerated().map { ($0.offset, "\($0.element) Hz") }
                    )
                }
            }
            .padding(.horizontal, 20)
            .controlGlass(in: RoundedRectangle(cornerRadius: 26))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func trackingControls(_ settings: Settings) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Tracking")
            VStack(spacing: 0) {
                settingRow("Lift-off distance", height: 56) {
                    SettingMenu(
                        title: "Lift-off distance",
                        selection: model.binding(\.liftOffMode),
                        options: [(0, "Very low"), (1, "Low")] + (settings.liftOffMode > 1 ? [(settings.liftOffMode, "Custom")] : [])
                    )
                }
                rowDivider
                settingRow("Angle snapping", height: 55) {
                    Toggle("Angle snapping", isOn: Binding(
                        get: { model.draft?.angleSnapping != 0 },
                        set: { model.draft?.angleSnapping = $0 ? 1 : 0 }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                    .help("Straightens small deviations when moving in a line.")
                }
                rowDivider
                settingRow("Motion sync", height: 55) {
                    Toggle("Motion sync", isOn: Binding(
                        get: { model.draft?.motionSyncEnabled ?? false },
                        set: { model.draft?.motionSyncEnabled = $0 }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                    .help("Synchronizes sensor sampling with USB reports.")
                }
            }
            .padding(.horizontal, 20)
            .controlGlass(in: RoundedRectangle(cornerRadius: 26))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 18, weight: .semibold))
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func settingRow<Control: View>(_ title: String, height: CGFloat, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title).font(.system(size: 16, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            control()
        }
        .frame(height: height)
    }

    private var rowDivider: some View {
        Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
            .accessibilityHidden(true)
    }

    private var connectionPlaceholder: some View {
        VStack(spacing: 18) {
            Image(systemName: "computermouse")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text(model.status == "Permission needed" ? "Allow access to your mouse" : "Connect your mouse")
                .font(.system(size: 23, weight: .semibold))
            Text("Use a USB cable, or plug in the receiver\nand switch the mouse to 2.4 GHz.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    @ViewBuilder private var notices: some View {
        if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let latest = model.conflict {
            VStack(alignment: .leading, spacing: 12) {
                Text("The mouse’s settings changed while you were editing.")
                HStack(spacing: 12) {
                    Button("Use mouse settings") { model.resolveConflict(keepEdits: false) }
                        .glassAction()
                    Button("Keep my edits") { model.resolveConflict(keepEdits: true) }
                        .glassAction(prominent: true)
                        .disabled(latest.profile != model.saved?.profile)
                }
            }
        }
    }

    private var saveControls: some View {
        HStack(spacing: 12) {
            Text(model.saving ? "Saving…" : "Unsaved changes")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button { model.draft = model.saved } label: {
                Text("Revert").frame(minWidth: 76, minHeight: 32)
            }
                .glassAction()
                .disabled(model.saving)
            Button { model.apply() } label: {
                Text("Apply").frame(minWidth: 76, minHeight: 32)
            }
                .glassAction(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(model.busy || !model.connected || model.conflict != nil)
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 22)
    }
}

private struct SettingMenu: View {
    let title: String
    @Binding var selection: Int
    let options: [(Int, String)]

    private var current: String { options.first { $0.0 == selection }?.1 ?? "Unknown" }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 10) {
                Text(current)
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 104, minHeight: 42)
            .padding(.horizontal, 8)
            .background(.primary.opacity(0.055), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(current)
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
            Text("\(stage + 1)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("DPI", text: $text)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 32, weight: active ? .semibold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(active ? Color(nsColor: .controlAccentColor) : .primary)
                .accessibilityLabel("DPI stage \(stage + 1)" + (active ? ", active" : ""))
                .focused($focused)
                .onChange(of: text) { _ in if let number = parsed { value = number } }
                .onChange(of: focused) { hasFocus in
                    if !hasFocus {
                        if let number = parsed { value = number }
                        text = String(value)
                    }
                }
                .onChange(of: value) { number in if !focused { text = String(number) } }
                .onAppear { text = String(value) }
                .onSubmit { focused = false }
                .help("50–26,000 DPI, in steps of 50. Invalid input reverts when leaving the field.")
            Capsule().fill(active ? Color.accentColor : Color.clear)
                .frame(width: 64, height: 3)
            Text(changed ? "Edited" : active ? "Active" : " ")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(changed ? Color.orange : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(active ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(focused ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1.5)
        }
    }
}
