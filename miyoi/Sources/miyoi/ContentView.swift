import MiyoiKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: DeviceManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingReveal = false

    var body: some View {
        NavigationStack {
            Group {
                switch manager.connectionState {
                case .disconnected:
                    ConnectionView(
                        title: "Connect your mouse",
                        message: "Connect a supported Attack Shark mouse by cable or receiver, then scan for it",
                        isLoading: false,
                        action: manager.connect
                    )
                case .connecting:
                    ConnectionView(
                        title: "Connecting",
                        message: "Reading device information and the active profile...",
                        isLoading: true,
                        action: nil
                    )
                case .error(let message):
                    ConnectionView(
                        title: "Connection failed",
                        message: message,
                        isLoading: false,
                        action: manager.connect
                    )
                case .connected:
                    if let snapshot = manager.snapshot, let model = manager.model {
                        DeviceDashboard(snapshot: snapshot, model: model)
                            .transition(.opacity)

                    /* i rly dont know how to do this better but since its here
                     * i hope oss community do this better than me :(
                    if let snapshot = manager.snapshot, let model = manager.model {
                        if showingReveal {
                            MouseRevealScreen(model: model) {
                                showingReveal = false
                            }
                            .transition(.opacity)
                        } else {
                            DeviceDashboard(snapshot: snapshot, model: model)
                                .transition(.opacity)
                        }
                    */
                    } else {
                        ConnectionView(
                            title: "Device data unavailable",
                            message: "Reconnect the device to load its settings",
                            isLoading: false,
                            action: manager.connect
                        )
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: showingReveal)
        .frame(minWidth: 760, minHeight: 680)
        .background(AppBackground())
        .task {
            if manager.connectionState == .disconnected { manager.connect() }
        }
        .onChange(of: manager.connectionState) { _, state in
            showingReveal = state.isConnected && manager.model != nil
        }
    }
}

private struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [Color.accentColor.opacity(0.16), .clear],
                center: UnitPoint(x: 0.2, y: 0.08),
                startRadius: 20,
                endRadius: 460
            )

            RadialGradient(
                colors: [Color.blue.opacity(0.08), .clear],
                center: UnitPoint(x: 0.9, y: 0.92),
                startRadius: 40,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

private struct ConnectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let message: String
    let isLoading: Bool
    let action: (() -> Void)?

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 108, height: 108)
                    .scaleEffect(pulse ? 1.08 : 1.0)
                    .animation(
                        isLoading && !reduceMotion
                            ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                            : nil,
                        value: pulse
                    )
                Image(systemName: "computermouse")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.tint)
            }
            .accessibilityHidden(true)
            .onAppear { pulse = isLoading && !reduceMotion }
            .onChange(of: isLoading) { _, loading in
                pulse = loading && !reduceMotion
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                pulse = isLoading && !shouldReduceMotion
            }

            VStack(spacing: 8) {
                Text(title).font(.title2.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if isLoading {
                ProgressView().controlSize(.large)
            } else if let action {
                Button("Scan for Devices", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DeviceDashboard: View {
    @EnvironmentObject private var manager: DeviceManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let snapshot: DeviceSnapshot
    let model: DeviceModel

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = manager.lastError {
                        ErrorBanner(message: error) { manager.lastError = nil }
                    }
                    movementCard
                    sensorCard
                    ButtonBindingsCard(
                        bindings: snapshot.bindings,
                        buttonIndices: model.buttonIndices.map(Int.init).sorted(),
                        dpiMax: snapshot.dpiMax
                    )
                }
                .padding(24)
                .frame(maxWidth: 1_080)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: manager.isLoading || manager.isSaving
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { manager.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(manager.isLoading || manager.isSaving)
                .help("Refresh device data")

                Button(role: .destructive, action: manager.disconnect) {
                    Label("Disconnect", systemImage: "eject")
                }
                .help("Disconnect the current mouse")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 54, height: 54)
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.name).font(.title2.bold())
                Text("Firmware \(manager.firmwareVersion ?? "Unknown")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if manager.isLoading || manager.isSaving {
                StatusPill(text: manager.isSaving ? "Saving..." : "Refreshing...")
                    .transition(.opacity)
            }

            BatteryBadge(percent: snapshot.battery)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: 1_080)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .zIndex(1)
    }

    private var movementCard: some View {
        SettingsCard(title: "Movement", systemImage: "scope") {
            VStack(alignment: .leading, spacing: 12) {
                SettingRow("Polling rate") {
                    Picker("Polling rate", selection: Binding(
                        get: { snapshot.pollingHz },
                        set: { manager.setPolling($0) }
                    )) {
                        ForEach(snapshot.pollingRates, id: \.self) { rate in
                            Text("\(rate) Hz").tag(rate)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 100)
                } info: {
                    PollingRateInfoButton()
                }

                SettingRow("Lift-off distance") {
                    Picker("Lift-off distance", selection: Binding(
                        get: { snapshot.lod },
                        set: { manager.setLOD($0) }
                    )) {
                        ForEach(model.lodValues, id: \.self) { value in
                            Text(value.formatted(.number.precision(.fractionLength(1))) + " mm").tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                Divider()

                DPIStagesEditor(
                    stages: snapshot.stages,
                    activeStage: snapshot.activeStage,
                    maximum: min(snapshot.dpiMax, model.maxDPIX, model.maxDPIY),
                    maximumStageCount: model.maxStageCount
                )

                Divider()

                let sleepLabels: [(String, Int)] = [
                    ("Never", 0), ("1 min", 60), ("3 min", 180),
                    ("5 min", 300), ("10 min", 600), ("20 min", 1_200),
                ]
                SettingRow("Sleep timer") {
                    Picker("Sleep timer", selection: Binding(
                        get: { snapshot.sleepSeconds },
                        set: { manager.setSleep($0) }
                    )) {
                        ForEach(sleepLabels, id: \.1) { label, seconds in
                            Text(label).tag(seconds)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            }
            .disabled(manager.isLoading || manager.isSaving)
        }
    }

    private var sensorCard: some View {
        SettingsCard(title: "Sensor", systemImage: "sensor.tag.radiowaves.forward") {
            VStack(spacing: 8) {
                if model.supportsMotionSync {
                    SettingRow("Motion Sync") {
                        Toggle("", isOn: Binding(get: { snapshot.motionSync }, set: { manager.setMotionSync($0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
                if model.supportsAngular {
                    SettingRow("Angle Snapping") {
                        Toggle("", isOn: Binding(get: { snapshot.angleSnap }, set: { manager.setAngleSnap($0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
                if model.supportsRipple {
                    SettingRow("Ripple Control") {
                        Toggle("", isOn: Binding(get: { snapshot.ripple }, set: { manager.setRipple($0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
                if model.supportsTracking {
                    SettingRow("Tracking Mode") {
                        Toggle("", isOn: Binding(get: { snapshot.tracking }, set: { manager.setTracking($0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
            }
        }
    }
}

private struct StatusPill: View {
    let text: String

    var body: some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

private struct BatteryBadge: View {
    let percent: Int

    private var symbol: String {
        switch percent {
        case 0...10: return "battery.0percent"
        case 11...35: return "battery.25percent"
        case 36...60: return "battery.50percent"
        case 61...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var tint: Color {
        percent <= 15 ? .red : .primary
    }

    var body: some View {
        Label("\(percent)%", systemImage: symbol)
            .font(.headline)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .accessibilityLabel("Battery \(percent) percent")
    }
}

private struct PollingRateInfoButton: View {
    @State private var isPresented = false

    private let message = "Higher rates improve responsiveness but use more power."

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(message)
        .accessibilityLabel("Polling rate information")
        .accessibilityHint(message)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(message)
                .font(.callout)
                .frame(width: 240, alignment: .leading)
                .padding(14)
        }
    }
}

private struct DPIStagesEditor: View {
    @EnvironmentObject private var manager: DeviceManager
    let stages: [DPIStage]
    let activeStage: Int
    let maximum: Int
    let maximumStageCount: Int
    @State private var draft: [DraftDPIStage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DPI Stages")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Maximum \(maximum) DPI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(Array($draft.enumerated()), id: \.element.id) { index, $stage in
                    DPIStageChip(
                        index: index,
                        value: $stage.value,
                        isActive: index == activeStage,
                        canActivate: index < stages.count,
                        activate: { manager.setActiveStage(index) }
                    )
                }

                Spacer()

                VStack(spacing: 6) {
                    Button {
                        let value = draft.last?.value ?? min(800, maximum)
                        draft.append(DraftDPIStage(value: value))
                    } label: {
                        Label("Add stage", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(draft.count >= maximumStageCount)
                    .help("Add DPI stage")

                    Button {
                        draft.removeLast()
                    } label: {
                        Label("Remove stage", systemImage: "minus")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(draft.count <= 1)
                    .help("Remove the last DPI stage")
                }
            }

            HStack {
                Text("\(draft.count) of \(maximumStageCount) stages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply DPI Stages", action: applyStages)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draftValues == stages || manager.isLoading || manager.isSaving)
            }
        }
        .task(id: stages) {
            draft = stages.map { DraftDPIStage(value: $0.x) }
        }
    }

    private var draftValues: [DPIStage] {
        draft.map { DPIStage(x: $0.value, y: $0.value) }
    }

    private func applyStages() {
        let sanitized = draft.map {
            let value = min(max($0.value, 50), maximum)
            return DPIStage(x: value, y: value)
        }
        draft = sanitized.map { DraftDPIStage(value: $0.x) }
        manager.setStages(sanitized)
    }
}

private struct DraftDPIStage: Identifiable {
    let id = UUID()
    var value: Int
}

private struct DPIStageChip: View {
    let index: Int
    @Binding var value: Int
    let isActive: Bool
    let canActivate: Bool
    let activate: () -> Void

    private var stageNumber: String { String(index + 1) }
    private var activeState: String { isActive ? "Active" : "Inactive" }
    private var borderColor: Color {
        isActive ? .accentColor : Color(nsColor: .separatorColor).opacity(0.8)
    }
    private var borderWidth: CGFloat { isActive ? 1.5 : 0.75 }

    var body: some View {
        VStack(spacing: 7) {
            Button(action: activate) {
                Text(stageNumber)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .disabled(!canActivate || isActive)
            .accessibilityLabel("DPI stage " + stageNumber)
            .accessibilityValue(activeState)
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityHint(isActive ? "" : "Activates this DPI stage")

            TextField("DPI", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(minWidth: 68, maxWidth: 92)
                .accessibilityLabel("DPI stage " + stageNumber + " value")
        }
        .padding(8)
        .background(
            .quaternary.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control
    var info: (() -> any View)?

    init(_ title: String,
         @ViewBuilder control: @escaping () -> Control,
         @ViewBuilder info: @escaping () -> some View
    ) {
        self.title = title
        self.control = control
        self.info = info
    }

    init(_ title: String, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.control = control
        self.info = nil
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(title).font(.body)
                if let info { AnyView(info()) }
            }
            Spacer()
            control()
        }
    }
}

private struct ButtonBindingsCard: View {
    @EnvironmentObject private var manager: DeviceManager
    let bindings: [Int: ButtonBinding]
    let buttonIndices: [Int]
    let dpiMax: Int
    @State private var editingIndex: Int?

    var body: some View {
        SettingsCard(title: "Buttons", systemImage: "cursorarrow.click.2") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                ForEach(buttonIndices, id: \.self) { index in
                    Button {
                        editingIndex = index
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(buttonName(index)).font(.caption).foregroundStyle(.secondary)
                                Text(bindings[index]?.describe() ?? "Unavailable")
                                    .lineLimit(2)
                                    .fontWeight(.medium)
                            }
                            Spacer()
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.separator.opacity(0.8), lineWidth: 0.75)
                    )
                    .disabled(bindings[index] == nil || manager.isLoading || manager.isSaving)
                    .accessibilityLabel("\(buttonName(index)), \(bindings[index]?.describe() ?? "unavailable")")
                    .accessibilityHint("Opens the binding editor")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { editingIndex != nil },
            set: { if !$0 { editingIndex = nil } }
        )) {
            if let index = editingIndex, let binding = bindings[index] {
                ButtonBindingEditor(index: index, original: binding, dpiMax: dpiMax) {
                    editingIndex = nil
                }
            }
        }
    }

    private func buttonName(_ index: Int) -> String {
        let names = [1: "Left Button", 2: "Right Button", 3: "Middle Button", 4: "Back Button", 5: "Forward Button"]
        return names[index] ?? "Button \(index)"
    }
}

private enum BindingKind: String, CaseIterable, Identifiable {
    case disabled = "Disabled"
    case mouse = "Mouse Button"
    case keyboard = "Keyboard Key"
    case media = "Media"
    case dpiCycle = "DPI Cycle"
    case dpiLock = "DPI Lock"
    case profile = "Profile Switch"
    case polling = "Polling Rate Switch"
    case lod = "LOD Switch"

    var id: String { rawValue }
}

private struct ButtonBindingEditor: View {
    @EnvironmentObject private var manager: DeviceManager
    let index: Int
    let original: ButtonBinding
    let dpiMax: Int
    let dismiss: () -> Void
    @State private var kind: BindingKind
    @State private var mouseButton: MouseButton = .left
    @State private var keyUsage = 0x04
    @State private var modifier: UInt8 = 0
    @State private var mediaUsage: UInt16 = 0xCD
    @State private var lockDPI = 1_200

    init(index: Int, original: ButtonBinding, dpiMax: Int, dismiss: @escaping () -> Void) {
        self.index = index
        self.original = original
        self.dpiMax = dpiMax
        self.dismiss = dismiss
        _kind = State(initialValue: Self.kind(for: original))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Button \(index)").font(.title2.bold())

            Form {
                Picker("Action", selection: $kind) {
                    ForEach(BindingKind.allCases) { Text($0.rawValue).tag($0) }
                }
                switch kind {
                case .mouse:
                    Picker("Mouse action", selection: $mouseButton) {
                        ForEach(MouseButton.allCases) { Text($0.label).tag($0) }
                    }
                case .keyboard:
                    Picker("Key", selection: $keyUsage) {
                        ForEach(0x04...0x65, id: \.self) { code in
                            Text(KeyCodes.usageName(UInt8(code))).tag(code)
                        }
                    }
                    Picker("Modifier", selection: $modifier) {
                        Text("None").tag(UInt8(0))
                        Text("Shift").tag(UInt8(0x02))
                        Text("Control").tag(UInt8(0x04))
                        Text("Option").tag(UInt8(0x08))
                        Text("Command").tag(UInt8(0x10))
                    }
                case .media:
                    Picker("Media action", selection: $mediaUsage) {
                        Text("Play/Pause").tag(UInt16(0xCD))
                        Text("Volume Up").tag(UInt16(0xE9))
                        Text("Volume Down").tag(UInt16(0xEA))
                        Text("Mute").tag(UInt16(0xE2))
                        Text("Next Track").tag(UInt16(0xB5))
                        Text("Previous Track").tag(UInt16(0xB6))
                    }
                case .dpiLock:
                    Stepper("DPI: \(lockDPI)", value: $lockDPI, in: 50...dpiMax, step: 50)
                default:
                    EmptyView()
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    manager.setBinding(index, binding)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(manager.isLoading || manager.isSaving)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { loadOriginalParameters() }
    }

    private var binding: ButtonBinding {
        switch kind {
        case .disabled: return .disabled
        case .mouse: return .mouse(mouseButton)
        case .keyboard: return .keyboard(modifier: modifier, usage: UInt8(keyUsage))
        case .media: return .media(mediaUsage)
        case .dpiCycle: return .dpiCycle()
        case .dpiLock: return .dpiLock(lockDPI)
        case .profile: return .profileLoop()
        case .polling: return .pollingLoop()
        case .lod: return .lodLoop()
        }
    }

    private func loadOriginalParameters() {
        if original.actionType == 1, let value = original.data.first, let button = MouseButton(rawValue: value) {
            mouseButton = button
        } else if original.actionType == 4 {
            modifier = original.data.first ?? 0
            keyUsage = Int(original.data.count > 1 ? original.data[1] : 0x04)
        } else if original.actionType == 5 {
            mediaUsage = (UInt16(original.data.first ?? 0) << 8) | UInt16(original.data.count > 1 ? original.data[1] : 0)
        } else if original.actionType == 7, original.data.first == 5, original.data.count > 2 {
            lockDPI = min((Int(original.data[1]) << 8) | Int(original.data[2]), dpiMax)
        }
    }

    private static func kind(for binding: ButtonBinding) -> BindingKind {
        switch binding.actionType {
        case 1: return .mouse
        case 4: return .keyboard
        case 5: return .media
        case 7: return binding.data.first == 5 ? .dpiLock : .dpiCycle
        case 8: return .profile
        case 13: return .polling
        case 14: return .lod
        default: return .disabled
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.separator.opacity(0.72), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", action: dismiss)
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
    }
}
