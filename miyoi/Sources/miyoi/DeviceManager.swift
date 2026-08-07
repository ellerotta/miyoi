import Foundation
import MiyoiKit

struct DeviceSnapshot: Sendable {
    var battery: Int
    var pollingHz: Int
    var pollingRates: [Int]
    var activeStage: Int
    var stages: [DPIStage]
    var dpiMax: Int
    var lod: Double
    var sleepSeconds: Int
    var motionSync: Bool
    var angleSnap: Bool
    var ripple: Bool
    var hyper: Bool
    var tracking: Bool
    var bindings: [Int: ButtonBinding]
}

enum DeviceConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool { self == .connected }
}

private enum DeviceServiceError: LocalizedError {
    case notConnected
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "The device is no longer connected"
        case .deviceNotFound:
            return "No supported Attack Shark device was found. Check that the receiver or cable is connected"
        }
    }
}

private struct ConnectedDevice: Sendable {
    let sessionID: UUID
    let model: DeviceModel
    let firmwareVersion: String
    let snapshot: DeviceSnapshot
}

private actor DeviceService {
    private var device: MiyoiDevice?
    private var model: DeviceModel?
    private var sessionID: UUID?

    func connect() throws -> ConnectedDevice {
        device = nil
        model = nil
        sessionID = nil

        for candidate in DeviceRegistry.models {
            do {
                let connected = try MiyoiDevice.open(model: candidate)
                device = connected
                model = candidate
                let connectedSessionID = UUID()
                sessionID = connectedSessionID
                let connectedSnapshot: DeviceSnapshot
                do {
                    connectedSnapshot = try readSnapshot(from: connected, model: candidate)
                } catch {
                    device = nil
                    model = nil
                    sessionID = nil
                    throw error
                }
                return ConnectedDevice(
                    sessionID: connectedSessionID,
                    model: candidate,
                    firmwareVersion: connected.firmwareVersion,
                    snapshot: connectedSnapshot
                )
            } catch HIDTransportError.deviceNotFound {
                continue
            }
        }
        throw DeviceServiceError.deviceNotFound
    }

    func disconnect(sessionID expectedSessionID: UUID?) {
        guard expectedSessionID == nil || sessionID == expectedSessionID else { return }
        device = nil
        model = nil
        sessionID = nil
    }

    func isConnected(sessionID expectedSessionID: UUID) -> Bool {
        guard sessionID == expectedSessionID, let device else { return false }
        return DeviceDiscovery.allHIDDevices().contains {
            $0.info.vid == DeviceRegistry.vendorID &&
                $0.info.pid == device.pid &&
                $0.info.usagePage == 0xFFFF
        }
    }

    func refresh(sessionID: UUID) throws -> DeviceSnapshot {
        let (device, model) = try connectedDevice(sessionID: sessionID)
        return try readSnapshot(from: device, model: model)
    }

    func setPolling(_ hz: Int, sessionID: UUID) throws -> Int {
        let device = try connectedDevice(sessionID: sessionID).0
        try device.setPollingRateHz(hz)
        return try device.pollingRateHz()
    }

    func setActiveStage(_ stage: Int, sessionID: UUID) throws -> Int {
        let device = try connectedDevice(sessionID: sessionID).0
        try device.setActiveDPIStage(stage)
        return try device.activeDPIStage()
    }

    func setStages(
        _ stages: [DPIStage],
        activeStage: Int,
        sessionID: UUID
    ) throws -> (stages: [DPIStage], activeStage: Int) {
        let device = try connectedDevice(sessionID: sessionID).0
        let correctedActiveStage = min(activeStage, stages.count - 1)
        if correctedActiveStage != activeStage {
            try device.setActiveDPIStage(correctedActiveStage)
        }
        try device.setDPIStages(stages)
        return (try device.dpiStages(), try device.activeDPIStage())
    }

    func setLOD(_ millimeters: Double, sessionID: UUID) throws -> Double {
        let device = try connectedDevice(sessionID: sessionID).0
        try device.setLOD(millimeters)
        return try device.lod()
    }

    func setSleep(_ seconds: Int, sessionID: UUID) throws -> Int {
        let device = try connectedDevice(sessionID: sessionID).0
        try device.setSleepSeconds(seconds)
        return try device.sleepSeconds()
    }

    func setMotionSync(_ enabled: Bool, sessionID: UUID) throws -> Bool {
        let device = try connectedDevice(sessionID: sessionID).0
        try device.setMotionSync(enabled)
        return try device.motionSync()
    }

    func setAngleSnap(_ enabled: Bool, sessionID: UUID) throws -> Bool {
        let device = try connectedDevice(sessionID: sessionID).0
        try device.setAngleSnap(enabled)
        return try device.angleSnap()
    }

    func setRipple(_ enabled: Bool, sessionID: UUID) throws -> Bool {
        let device = try connectedDevice(sessionID: sessionID).0
        try device.setRippleControl(enabled)
        return try device.rippleControl()
    }

    func setHyper(_ enabled: Bool, sessionID: UUID) throws -> Bool {
        let device = try connectedDevice(sessionID: sessionID).0
        try device.setHyperMode(enabled)
        return try device.hyperMode()
    }

    func setTracking(_ enabled: Bool, sessionID: UUID) throws -> Bool {
        let device = try connectedDevice(sessionID: sessionID).0
        try device.setTrackingMode(enabled)
        return try device.trackingMode()
    }

    func setBinding(index: Int, binding: ButtonBinding, sessionID: UUID) throws -> ButtonBinding {
        let (device, model) = try connectedDevice(sessionID: sessionID)
        guard let buttonIndex = UInt8(exactly: index), model.buttonIndices.contains(buttonIndex) else {
            throw MiyoiError.invalidInput("invalid button index \(index)")
        }
        try device.setButton(buttonIndex, binding)
        return try device.button(buttonIndex)
    }

    private func connectedDevice(sessionID expectedSessionID: UUID) throws -> (MiyoiDevice, DeviceModel) {
        guard sessionID == expectedSessionID, let device, let model else {
            throw DeviceServiceError.notConnected
        }
        return (device, model)
    }

    private func readSnapshot(from device: MiyoiDevice, model: DeviceModel) throws -> DeviceSnapshot {
        var bindings: [Int: ButtonBinding] = [:]
        for index in model.buttonIndices.sorted() {
            bindings[Int(index)] = try device.button(index)
        }

        return DeviceSnapshot(
            battery: try device.batteryPercent(),
            pollingHz: try device.pollingRateHz(),
            pollingRates: model.pollingRates(forPID: device.pid).sorted(),
            activeStage: try device.activeDPIStage(),
            stages: try device.dpiStages(),
            dpiMax: try device.dpiMax(),
            lod: try device.lod(),
            sleepSeconds: try device.sleepSeconds(),
            motionSync: model.supportsMotionSync ? try device.motionSync() : false,
            angleSnap: model.supportsAngular ? try device.angleSnap() : false,
            ripple: model.supportsRipple ? try device.rippleControl() : false,
            hyper: model.supportsHyper ? try device.hyperMode() : false,
            tracking: model.supportsTracking ? try device.trackingMode() : false,
            bindings: bindings
        )
    }
}

@MainActor
final class DeviceManager: ObservableObject {
    @Published private(set) var connectionState: DeviceConnectionState = .disconnected
    @Published private(set) var model: DeviceModel?
    @Published private(set) var firmwareVersion: String?
    @Published private(set) var snapshot: DeviceSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var lastError: String?

    private let service = DeviceService()
    private var requestGeneration = 0
    private var activeSessionID: UUID?
    private var pendingOperationIDs: Set<UUID> = []
    private var connectionMonitor: Task<Void, Never>?

    func connect() {
        requestGeneration += 1
        let generation = requestGeneration
        connectionState = .connecting
        isLoading = true
        lastError = nil

        Task {
            do {
                let connected = try await service.connect()
                guard generation == requestGeneration else { return }
                model = connected.model
                activeSessionID = connected.sessionID
                firmwareVersion = connected.firmwareVersion
                snapshot = connected.snapshot
                connectionState = .connected
                startConnectionMonitor(generation: generation, sessionID: connected.sessionID)
            } catch {
                guard generation == requestGeneration else { return }
                model = nil
                activeSessionID = nil
                firmwareVersion = nil
                snapshot = nil
                let message = error.localizedDescription
                lastError = message
                connectionState = .error(message)
            }
            if generation == requestGeneration { isLoading = false }
        }
    }

    func disconnect() {
        requestGeneration += 1
        let disconnectedSessionID = activeSessionID
        activeSessionID = nil
        connectionMonitor?.cancel()
        connectionMonitor = nil
        connectionState = .disconnected
        model = nil
        firmwareVersion = nil
        snapshot = nil
        isLoading = false
        isSaving = false
        pendingOperationIDs.removeAll()
        lastError = nil
        Task { await service.disconnect(sessionID: disconnectedSessionID) }
    }

    func refresh() {
        guard connectionState.isConnected, let sessionID = activeSessionID else { return }
        requestGeneration += 1
        let generation = requestGeneration
        isLoading = true
        lastError = nil

        Task {
            do {
                let refreshed = try await service.refresh(sessionID: sessionID)
                guard generation == requestGeneration else { return }
                snapshot = refreshed
                startConnectionMonitor(generation: generation, sessionID: sessionID)
            } catch {
                guard generation == requestGeneration else { return }
                lastError = error.localizedDescription
            }
            if generation == requestGeneration { isLoading = false }
        }
    }

    func setPolling(_ hz: Int) {
        performWrite { sessionID in try await self.service.setPolling(hz, sessionID: sessionID) } apply: { value, snapshot in
            snapshot.pollingHz = value
        }
    }

    func setActiveStage(_ stage: Int) {
        performWrite { sessionID in try await self.service.setActiveStage(stage, sessionID: sessionID) } apply: { value, snapshot in
            snapshot.activeStage = value
        }
    }

    func setStages(_ stages: [DPIStage]) {
        guard connectionState.isConnected,
              let sessionID = activeSessionID,
              let activeStage = snapshot?.activeStage else { return }
        let generation = requestGeneration
        let operationID = UUID()
        pendingOperationIDs.insert(operationID)
        isSaving = true
        lastError = nil

        Task {
            defer {
                pendingOperationIDs.remove(operationID)
                isSaving = !pendingOperationIDs.isEmpty
            }
            do {
                let value = try await service.setStages(
                    stages,
                    activeStage: activeStage,
                    sessionID: sessionID
                )
                guard generation == requestGeneration,
                      connectionState.isConnected,
                      var updated = snapshot else { return }
                updated.stages = value.stages
                updated.activeStage = value.activeStage
                snapshot = updated
            } catch {
                guard generation == requestGeneration else { return }
                if let reconciled = try? await service.refresh(sessionID: sessionID) {
                    snapshot = reconciled
                }
                lastError = error.localizedDescription
            }
        }
    }

    func setLOD(_ millimeters: Double) {
        performWrite { sessionID in try await self.service.setLOD(millimeters, sessionID: sessionID) } apply: { value, snapshot in
            snapshot.lod = value
        }
    }

    func setSleep(_ seconds: Int) {
        performWrite { sessionID in try await self.service.setSleep(seconds, sessionID: sessionID) } apply: { value, snapshot in
            snapshot.sleepSeconds = value
        }
    }

    func setMotionSync(_ enabled: Bool) {
        performWrite { sessionID in try await self.service.setMotionSync(enabled, sessionID: sessionID) } apply: { value, snapshot in
            snapshot.motionSync = value
        }
    }

    func setAngleSnap(_ enabled: Bool) {
        performWrite { sessionID in try await self.service.setAngleSnap(enabled, sessionID: sessionID) } apply: { value, snapshot in
            snapshot.angleSnap = value
        }
    }

    func setRipple(_ enabled: Bool) {
        performWrite { sessionID in try await self.service.setRipple(enabled, sessionID: sessionID) } apply: { value, snapshot in
            snapshot.ripple = value
        }
    }

    func setHyper(_ enabled: Bool) {
        performWrite { sessionID in try await self.service.setHyper(enabled, sessionID: sessionID) } apply: { value, snapshot in
            snapshot.hyper = value
        }
    }

    func setTracking(_ enabled: Bool) {
        performWrite { sessionID in try await self.service.setTracking(enabled, sessionID: sessionID) } apply: { value, snapshot in
            snapshot.tracking = value
        }
    }

    func setBinding(_ index: Int, _ binding: ButtonBinding) {
        performWrite { sessionID in try await self.service.setBinding(index: index, binding: binding, sessionID: sessionID) } apply: { value, snapshot in
            snapshot.bindings[index] = value
        }
    }

    private func performWrite<Value: Sendable>(
        operation: @escaping (UUID) async throws -> Value,
        apply: @escaping (Value, inout DeviceSnapshot) -> Void
    ) {
        guard connectionState.isConnected, let sessionID = activeSessionID else { return }
        let generation = requestGeneration
        let operationID = UUID()
        pendingOperationIDs.insert(operationID)
        isSaving = true
        lastError = nil

        Task {
            defer {
                pendingOperationIDs.remove(operationID)
                isSaving = !pendingOperationIDs.isEmpty
            }
            do {
                let confirmedValue = try await operation(sessionID)
                guard generation == requestGeneration, connectionState.isConnected else { return }
                guard var updated = snapshot else { return }
                apply(confirmedValue, &updated)
                snapshot = updated
            } catch {
                if generation == requestGeneration { lastError = error.localizedDescription }
            }
        }
    }

    private func startConnectionMonitor(generation: Int, sessionID: UUID) {
        connectionMonitor?.cancel()
        connectionMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    return
                }
                guard let self,
                      generation == self.requestGeneration,
                      self.activeSessionID == sessionID else { return }
                guard await self.service.isConnected(sessionID: sessionID) else {
                    self.requestGeneration += 1
                    self.model = nil
                    self.activeSessionID = nil
                    self.firmwareVersion = nil
                    self.snapshot = nil
                    self.isLoading = false
                    self.isSaving = false
                    self.pendingOperationIDs.removeAll()
                    let message = "The mouse was disconnected"
                    self.lastError = message
                    self.connectionState = .error(message)
                    await self.service.disconnect(sessionID: sessionID)
                    return
                }
            }
        }
    }
}
