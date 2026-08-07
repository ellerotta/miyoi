import Foundation
import os

let debugLog = Logger(subsystem: "com.miyoi.debug", category: "hid")

public enum MiyoiError: Error, LocalizedError, Equatable {
    case deviceNotFound
    case noResponse
    case protocolMismatch
    case invalidInput(String)
    case unsupportedFeature(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "Device not found"
        case .noResponse: return "Device did not respond"
        case .protocolMismatch: return "Unexpected protocol response"
        case .invalidInput(let message): return "Invalid input: \(message)"
        case .unsupportedFeature(let feature): return "\(feature) is not supported by this device"
        }
    }
}

public struct DPIStage: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct RGB: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
    public var hex: String { String(format: "%02X%02X%02X", r, g, b) }
}

func frame(payload: [UInt8] = [], target: UInt8 = 0, cmd: UInt8, address: UInt8 = 2) throws -> [UInt8] {
    guard payload.count <= 57 else {
        throw MiyoiError.invalidInput("frame payload exceeds 57 bytes")
    }
    var b = [UInt8](repeating: 0, count: 64)
    b[2] = address
    b[3] = UInt8(payload.count)
    b[4] = target
    b[5] = cmd
    for (i, v) in payload.enumerated() { b[6 + i] = v }
    return b
}

public final class MiyoiDevice {

    public let model: DeviceModel
    let transport: HIDTransport
    public let pid: Int
    public private(set) var hidIndex = 0
    public private(set) var firmwareVersion = "0.0.0.0"
    public let profile: UInt8 = 1

    public static func open(model: DeviceModel, pid: Int? = nil) throws -> MiyoiDevice {
        if let pid {
            guard model.pidList.contains(pid) else {
                throw MiyoiError.invalidInput("PID does not belong to \(model.name)")
            }
            return try MiyoiDevice(model: model, pids: [pid])
        }
        return try MiyoiDevice(model: model, pids: model.pidList)
    }

    private init(model: DeviceModel, pids: [Int]) throws {
        self.model = model
        transport = try HIDTransport(matchingVID: DeviceRegistry.vendorID, pids: pids)
        pid = transport.info.pid
        firmwareVersion = try probeFirmware()
    }

    private func probeFirmware() throws -> String {
        let r = try transport.exchange(try frame(cmd: 0x81, address: 2), readAttempts: 5) {
            guard $0.indices.contains(10), $0[2] == 2, $0[4] == 0 else { return false }
            return (($0[1] == 0xA1 || $0[1] == 0x02) && $0[6] == 0x81) ||
                (($0[0] == 0xA1 || $0[0] == 0x02) && $0[5] == 0x81)
        }
        debugLog.debug("FW RX: \(r.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
        guard !r.isEmpty else { throw MiyoiError.noResponse }
        var version = "0.0.0.0"
        if r.indices.contains(10), r[6] == 0x81, r[1] == 0xA1 || r[1] == 0x02 {
            hidIndex = 0
            try validateResponse(r, command: 0x81)
            version = "\(r[7]).\(r[8]).\(r[9]).\(r[10])"
        } else if r.indices.contains(9), r[5] == 0x81, r[0] == 0xA1 || r[0] == 0x02 {
            hidIndex = 1
            try validateResponse(r, command: 0x81)
            version = "\(r[6]).\(r[7]).\(r[8]).\(r[9])"
        } else {
            throw MiyoiError.protocolMismatch
        }
        return version
    }

    private func exchange(_ request: [UInt8]) throws -> [UInt8] {
        guard request.indices.contains(5) else { throw MiyoiError.protocolMismatch }
        let command = request[5]
        let address = request[2]
        let target = request[4]
        debugLog.debug("TX: \(request.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
        let response = try transport.exchange(request, readAttempts: 5) { [hidIndex] response in
            let markerIndex = 1 - hidIndex
            let echoIndex = 6 - hidIndex
            guard response.indices.contains(markerIndex), response.indices.contains(echoIndex) else { return false }
            let marker = response[markerIndex]
            return (marker == 0xA1 || marker == 0x02) &&
                response[echoIndex] == command &&
                response.indices.contains(4) &&
                response[2] == address &&
                response[4] == target
        }
        let capturedHIDIndex = hidIndex
        debugLog.debug("RX: \(response.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public) hidIndex:\(capturedHIDIndex)")
        guard !response.isEmpty else { throw MiyoiError.noResponse }
        try validateResponse(response, command: command, address: address, target: target)
        return response
    }

    private func validateResponse(
        _ response: [UInt8],
        command: UInt8,
        address: UInt8 = 2,
        target: UInt8 = 0
    ) throws {
        let markerIndex = 1 - hidIndex
        let echoIndex = 6 - hidIndex
        guard response.indices.contains(3),
              response.indices.contains(markerIndex),
              response.indices.contains(echoIndex),
              response[markerIndex] == 0xA1 || response[markerIndex] == 0x02,
              response[echoIndex] == command,
              response[2] == address,
              response[4] == target else {
            throw MiyoiError.protocolMismatch
        }
        let declaredLength = Int(response[3])
        let dataStart = 7 - hidIndex
        guard declaredLength > 0, response.count >= dataStart + declaredLength else {
            throw MiyoiError.protocolMismatch
        }
    }

    private func byte(_ response: [UInt8], at index: Int) throws -> UInt8 {
        let payloadEnd = (7 - hidIndex) + Int(response[3])
        guard index >= 0, index < payloadEnd, response.indices.contains(index) else {
            throw MiyoiError.protocolMismatch
        }
        return response[index]
    }

    private func bytes(_ response: [UInt8], in range: Range<Int>) throws -> [UInt8] {
        let payloadEnd = (7 - hidIndex) + Int(response[3])
        guard range.lowerBound >= 0,
              range.upperBound <= payloadEnd,
              range.upperBound <= response.count else {
            throw MiyoiError.protocolMismatch
        }
        return Array(response[range])
    }

    private func reportBytes(_ response: [UInt8], in range: Range<Int>) throws -> [UInt8] {
        guard range.lowerBound >= 0, range.upperBound <= response.count else {
            throw MiyoiError.protocolMismatch
        }
        return Array(response[range])
    }

    private func valueByte(_ response: [UInt8]) throws -> Int {
        Int(try byte(response, at: 8 - hidIndex))
    }

    private func require(_ supported: Bool, feature: String) throws {
        guard supported else { throw MiyoiError.unsupportedFeature(feature) }
    }

    public func batteryPercent() throws -> Int {
        let r = try exchange(try frame(payload: [0, 0], cmd: 0x83))
        return try valueByte(r)
    }

    public func sensorModel() throws -> Int {
        let r = try exchange(try frame(target: 1, cmd: 0x8F))
        return Int(try byte(r, at: 7 - hidIndex))
    }

    public func profileID() throws -> Int {
        let r = try exchange(try frame(cmd: 0x85))
        return Int(try byte(r, at: 7 - hidIndex))
    }

    public func profileMask() throws -> Int {
        let r = try exchange(try frame(cmd: 0x86))
        return Int(try byte(r, at: 7 - hidIndex))
    }

    public func resetProfile() throws {
        _ = try exchange(try frame(payload: [profile], cmd: 0x0D))
    }

    static let pollingHzToByte: [Int: UInt8] = [125: 0x08, 250: 0x04, 500: 0x02, 1000: 0x01, 2000: 0x20, 4000: 0x40, 8000: 0x80]

    public func pollingRateHz() throws -> Int {
        let r = try exchange(try frame(payload: [profile], target: 1, cmd: 0x80))
        var byte = try byte(r, at: 8 - hidIndex)
        if byte == 0x10 { byte = 0x01 }
        guard let rate = Self.pollingHzToByte.first(where: { $0.value == byte })?.key else {
            throw MiyoiError.protocolMismatch
        }
        return rate
    }

    public func setPollingRateHz(_ hz: Int) throws {
        guard let value = Self.pollingHzToByte[hz], model.pollingRates(forPID: transport.info.pid).contains(hz) else {
            throw MiyoiError.invalidInput("unsupported polling rate \(hz) Hz")
        }
        _ = try exchange(try frame(payload: [profile, value], target: 1, cmd: 0x00))
    }

    public func dpiMax() throws -> Int {
        min(model.maxDPIX, model.maxDPIY)
    }

    public func activeDPIStage() throws -> Int {
        let r = try exchange(try frame(payload: [profile], target: 1, cmd: 0x82))
        return try valueByte(r) - 1
    }

    public func setActiveDPIStage(_ stage: Int) throws {
        guard (0..<model.maxStageCount).contains(stage) else {
            throw MiyoiError.invalidInput("DPI stage must be between 0 and \(model.maxStageCount - 1)")
        }
        _ = try exchange(try frame(payload: [profile, UInt8(stage + 1)], target: 1, cmd: 0x02))
    }

    public func dpiStages() throws -> [DPIStage] {
        let r = try exchange(try frame(payload: [profile, UInt8(model.maxStageCount)], target: 1, cmd: 0x81))
        let count = Int(try byte(r, at: 8 - hidIndex))
        guard count <= model.maxStageCount else { throw MiyoiError.protocolMismatch }
        var result: [DPIStage] = []
        for i in 0..<count {
            let base = 9 + 4 * i - hidIndex
            let x = (Int(try byte(r, at: base)) << 8) | Int(try byte(r, at: base + 1))
            let y = (Int(try byte(r, at: base + 2)) << 8) | Int(try byte(r, at: base + 3))
            result.append(DPIStage(x: x, y: y))
        }
        return result
    }

    public func setDPIStages(_ stages: [DPIStage]) throws {
        guard !stages.isEmpty, stages.count <= model.maxStageCount else {
            throw MiyoiError.invalidInput("DPI stage count must be between 1 and \(model.maxStageCount)")
        }
        guard stages.allSatisfy({ (1...model.maxDPIX).contains($0.x) && (1...model.maxDPIY).contains($0.y) }) else {
            throw MiyoiError.invalidInput("DPI values exceed the model limits")
        }
        var payload = [profile, UInt8(stages.count)]
        for s in stages {
            payload.append(UInt8((s.x >> 8) & 0xFF))
            payload.append(UInt8(s.x & 0xFF))
            payload.append(UInt8((s.y >> 8) & 0xFF))
            payload.append(UInt8(s.y & 0xFF))
        }
        _ = try exchange(try frame(payload: payload, target: 1, cmd: 0x01))
    }

    public func dpiColors() throws -> [RGB] {
        let r = try exchange(try frame(payload: [profile], target: 2, cmd: 0x81))
        var colors: [RGB] = []
        for i in 0..<model.maxStageCount {
            let base = 8 + i * 3
            colors.append(RGB(
                r: try byte(r, at: base - hidIndex),
                g: try byte(r, at: base + 1 - hidIndex),
                b: try byte(r, at: base + 2 - hidIndex)
            ))
        }
        return colors
    }

    public func setDPIColors(_ colors: [RGB]) throws {
        guard colors.count == model.maxStageCount else {
            throw MiyoiError.invalidInput("exactly \(model.maxStageCount) DPI colors are required")
        }
        var payload = [profile]
        for color in colors { payload.append(contentsOf: [color.r, color.g, color.b]) }
        _ = try exchange(try frame(payload: payload, target: 2, cmd: 0x01))
    }

    public func lod() throws -> Double {
        let r = try exchange(try frame(payload: [profile], target: 1, cmd: 0x88))
        let value = try byte(r, at: 8 - hidIndex)
        return value >= 0x80 ? Double(value - 0x80) / 10.0 : Double(value)
    }

    public func setLOD(_ mm: Double) throws {
        guard mm.isFinite, model.lodValues.contains(where: { abs($0 - mm) < 0.001 }) else {
            throw MiyoiError.invalidInput("unsupported lift-off distance \(mm) mm")
        }
        let value: UInt8 = mm < 1 ? UInt8(Int((mm * 10).rounded())) | 0x80 : UInt8(mm)
        _ = try exchange(try frame(payload: [profile, value], target: 1, cmd: 0x08))
    }

    public func debounceTime() throws -> Int {
        let r = try exchange(try frame(payload: [profile], cmd: 0x88))
        return try valueByte(r)
    }

    public func setDebounce(_ ms: Int) throws {
        guard (0...255).contains(ms) else {
            throw MiyoiError.invalidInput("debounce must be between 0 and 255 ms")
        }
        _ = try exchange(try frame(payload: [profile, UInt8(ms)], cmd: 0x08))
    }

    public func sleepSeconds() throws -> Int {
        let r = try exchange(try frame(payload: [profile], cmd: 0x87))
        let v = (Int(try byte(r, at: 8 - hidIndex)) << 8) | Int(try byte(r, at: 9 - hidIndex))
        return (v == 0xFFFF || v == 0xFF00 || v == 0) ? 0 : v
    }

    public func setSleepSeconds(_ seconds: Int) throws {
        guard seconds == 0 || (1...0xFFFE).contains(seconds) else {
            throw MiyoiError.invalidInput("sleep time must be 0 or between 1 and 65534 seconds")
        }
        let s = seconds < 1 ? 0xFFFF : seconds
        let hi = UInt8((s >> 8) & 0xFF), lo = UInt8(s & 0xFF)
        _ = try exchange(try frame(payload: [profile, hi, lo], cmd: 0x07))
    }

    private func toggle(_ cmd: UInt8, value: UInt8?) throws -> Bool {
        let payload: [UInt8] = value.map { [profile, $0] } ?? [profile]
        let r = try exchange(try frame(payload: payload, target: 1, cmd: cmd))
        let result = try byte(r, at: 8 - hidIndex)
        guard result <= 1 else { throw MiyoiError.protocolMismatch }
        return result == 1
    }

    public func motionSync() throws -> Bool { try require(model.supportsMotionSync, feature: "Motion sync"); return try toggle(0x89, value: nil) }
    public func setMotionSync(_ on: Bool) throws { try require(model.supportsMotionSync, feature: "Motion sync"); _ = try toggle(0x09, value: on ? 1 : 0) }
    public func angleSnap() throws -> Bool { try require(model.supportsAngular, feature: "Angle snapping"); return try toggle(0x84, value: nil) }
    public func setAngleSnap(_ on: Bool) throws { try require(model.supportsAngular, feature: "Angle snapping"); _ = try toggle(0x04, value: on ? 1 : 0) }
    public func rippleControl() throws -> Bool { try require(model.supportsRipple, feature: "Ripple control"); return try toggle(0x8A, value: nil) }
    public func setRippleControl(_ on: Bool) throws { try require(model.supportsRipple, feature: "Ripple control"); _ = try toggle(0x0A, value: on ? 1 : 0) }
    public func trackingMode() throws -> Bool { try require(model.supportsTracking, feature: "Tracking mode"); return try toggle(0x93, value: nil) }
    public func setTrackingMode(_ on: Bool) throws { try require(model.supportsTracking, feature: "Tracking mode"); _ = try toggle(0x13, value: on ? 1 : 0) }
    public func hyperMode() throws -> Bool { try require(model.supportsHyper, feature: "Hyper mode"); return try toggle(0x8B, value: nil) }
    public func setHyperMode(_ on: Bool) throws { try require(model.supportsHyper, feature: "Hyper mode"); _ = try toggle(0x0B, value: on ? 1 : 0) }
    public func dpiXYEnabled() throws -> Bool { try require(model.supportsDPIXY, feature: "Independent X/Y DPI"); return try toggle(0x8D, value: nil) }
    public func setDPIxy(_ on: Bool) throws { try require(model.supportsDPIXY, feature: "Independent X/Y DPI"); _ = try toggle(0x0D, value: on ? 1 : 0) }

    public func button(_ index: UInt8) throws -> ButtonBinding {
        guard model.buttonIndices.contains(index) else { throw MiyoiError.invalidInput("invalid button index \(index)") }
        let r = try exchange(try frame(payload: [profile, index, 0, 0xFF, 10], target: 3, cmd: 0x80))
        let action = try byte(r, at: 10 - hidIndex)
        let payloadLength = Int(try byte(r, at: 11 - hidIndex))
        guard payloadLength <= 10 else { throw MiyoiError.protocolMismatch }
        let payloadStart = 12 - hidIndex
        let payload = try reportBytes(r, in: payloadStart..<(payloadStart + payloadLength))
        return ButtonBinding(actionType: action, data: payload)
    }

    public func setButton(_ index: UInt8, _ binding: ButtonBinding) throws {
        guard model.buttonIndices.contains(index) else { throw MiyoiError.invalidInput("invalid button index \(index)") }
        guard binding.isValid else {
            throw MiyoiError.invalidInput("invalid button binding")
        }
        if binding.actionType == ButtonActionType.dpi.rawValue, binding.data.first == 5 {
            let dpi = (Int(binding.data[1]) << 8) | Int(binding.data[2])
            guard (1...min(model.maxDPIX, model.maxDPIY)).contains(dpi) else {
                throw MiyoiError.invalidInput("DPI lock exceeds the model limits")
            }
        }
        var payload = [profile, index, 0, binding.actionType, UInt8(binding.data.count)]
        payload.append(contentsOf: binding.data)
        _ = try exchange(try frame(payload: payload, target: 3, cmd: 0x00))
    }

    public func buttonCombine() throws -> Bool {
        try require(model.supportsButtonCombine, feature: "Button combine")
        let r = try exchange(try frame(payload: [profile], target: 3, cmd: 0x81))
        return try byte(r, at: 8 - hidIndex) == 1
    }

    public func setButtonCombine(_ on: Bool) throws {
        try require(model.supportsButtonCombine, feature: "Button combine")
        _ = try exchange(try frame(payload: [profile, on ? 1 : 0], target: 3, cmd: 0x01))
    }

    public func lightness() throws -> Int {
        try require(model.hasLighting, feature: "Lighting")
        let r = try exchange(try frame(payload: [profile, 0], target: 2, cmd: 0x82))
        return Int(try byte(r, at: 9 - hidIndex))
    }

    public func setLightness(_ value: Int) throws {
        try require(model.hasLighting, feature: "Lighting")
        guard (0...100).contains(value) else { throw MiyoiError.invalidInput("lightness must be between 0 and 100") }
        _ = try exchange(try frame(payload: [profile, 0, UInt8(value)], target: 2, cmd: 0x02))
    }
}

public enum MouseButton: UInt8, CaseIterable, Identifiable, Sendable {
    case defaultAction = 0
    case left = 1
    case right = 2
    case middle = 3
    case backward = 4
    case forward = 5
    case button6 = 6
    case button7 = 7
    case button8 = 8
    case scrollUp = 16
    case scrollDown = 17
    case dpiUp = 18
    case dpiDown = 19
    case dpiLoopUp = 20
    case dpiLoopDown = 21
    case prLoopUp = 28
    case prLoopDown = 29
    case prUp = 30
    case prDown = 31
    case lodUp = 33
    case lodDown = 34
    case lodLoopUp = 35
    case lodLoopDown = 36

    public var id: UInt8 { rawValue }
    public var label: String {
        switch self {
        case .defaultAction: return "Default Action"
        case .left: return "Left Click"
        case .right: return "Right Click"
        case .middle: return "Middle Click"
        case .backward: return "Backward"
        case .forward: return "Forward"
        case .button6, .button7, .button8: return "Button \(rawValue - 3)"
        case .scrollUp: return "Scroll Up"
        case .scrollDown: return "Scroll Down"
        case .dpiUp: return "DPI Up"
        case .dpiDown: return "DPI Down"
        case .dpiLoopUp: return "DPI Cycle Up"
        case .dpiLoopDown: return "DPI Cycle Down"
        case .prLoopUp: return "Polling Cycle Up"
        case .prLoopDown: return "Polling Cycle Down"
        case .prUp: return "Polling Up"
        case .prDown: return "Polling Down"
        case .lodUp: return "LOD Up"
        case .lodDown: return "LOD Down"
        case .lodLoopUp: return "LOD Cycle Up"
        case .lodLoopDown: return "LOD Cycle Down"
        }
    }
}

public enum ButtonActionType: UInt8, CaseIterable, Identifiable, Sendable {
    case off = 0
    case button = 1
    case xclick = 2
    case keyboard = 4
    case media = 5
    case dpi = 7
    case profile = 8
    case polling = 13
    case lod = 14
    case macro1 = 16
    case macro2 = 17
    case macro3 = 18

    public var id: UInt8 { rawValue }
    public var label: String {
        switch self {
        case .off: return "Disabled"
        case .button: return "Mouse Button"
        case .xclick: return "Double Click"
        case .keyboard: return "Key"
        case .media: return "Media"
        case .dpi: return "DPI"
        case .profile: return "Profile Switch"
        case .polling: return "Polling Rate"
        case .lod: return "LOD"
        case .macro1: return "Macro 1"
        case .macro2: return "Macro 2"
        case .macro3: return "Macro 3"
        }
    }
}

public struct ButtonBinding: Equatable, Hashable, Sendable {
    public var actionType: UInt8
    public var data: [UInt8]

    public init(actionType: UInt8, data: [UInt8]) {
        self.actionType = actionType
        self.data = data
    }

    public static let disabled = ButtonBinding(actionType: 0, data: [])

    fileprivate var isValid: Bool {
        guard data.count <= 10, let type = ButtonActionType(rawValue: actionType) else { return false }
        switch type {
        case .off: return data.isEmpty
        case .button: return data.count == 1 && MouseButton(rawValue: data[0]) != nil
        case .xclick: return data.count == 5 && MouseButton(rawValue: data[0]) != nil
        case .keyboard, .media: return data.count == 2
        case .dpi:
            guard let mode = data.first else { return false }
            return mode == 5 ? data.count == 5 : [1, 2, 6, 7].contains(mode) && data.count == 1
        case .profile, .polling, .lod: return data.count == 1
        case .macro1, .macro2, .macro3:
            guard data.count == 3 else { return false }
            let identifier = (Int(data[0]) << 8) | Int(data[1])
            return identifier == Int(actionType) - 15
        }
    }

    public static func mouse(_ button: MouseButton) -> ButtonBinding {
        ButtonBinding(actionType: 1, data: [button.rawValue])
    }

    public static func xclick(target: MouseButton = .left) -> ButtonBinding {
        ButtonBinding(actionType: 2, data: [target.rawValue, 1, 2, 0, 100])
    }

    public static func keyboard(modifier: UInt8 = 0, usage: UInt8) -> ButtonBinding {
        ButtonBinding(actionType: 4, data: [modifier, usage])
    }

    public static func media(_ usage: UInt16) -> ButtonBinding {
        ButtonBinding(actionType: 5, data: [UInt8((usage >> 8) & 0xFF), UInt8(usage & 0xFF)])
    }

    public static func dpiCycle() -> ButtonBinding {
        ButtonBinding(actionType: 7, data: [6])
    }

    public static func dpiLock(_ dpi: Int) -> ButtonBinding {
        guard (1...0xFFFF).contains(dpi) else {
            return ButtonBinding(actionType: 0xFF, data: [])
        }
        let hi = UInt8((dpi >> 8) & 0xFF), lo = UInt8(dpi & 0xFF)
        return ButtonBinding(actionType: 7, data: [5, hi, lo, hi, lo])
    }

    public static func profileLoop() -> ButtonBinding {
        ButtonBinding(actionType: 8, data: [3])
    }

    public static func pollingLoop() -> ButtonBinding {
        ButtonBinding(actionType: 13, data: [3])
    }

    public static func lodLoop() -> ButtonBinding {
        ButtonBinding(actionType: 14, data: [3])
    }

    public static func macro(id: Int, runTimes: Int = 0) -> ButtonBinding {
        guard (1...3).contains(id), (0...255).contains(runTimes) else {
            return ButtonBinding(actionType: 0xFF, data: [])
        }
        return ButtonBinding(actionType: UInt8(16 + (id - 1)), data: [UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF), UInt8(runTimes)])
    }

    public func describe() -> String {
        switch actionType {
        case 0: return "—"
        case 1:
            let b = Int(data.first ?? 0)
            return MouseButton(rawValue: UInt8(b))?.label ?? "Button \(b)"
        case 2: return "Double Click"
        case 4:
            let mods = KeyCodes.modifierNames(data.first ?? 0)
            let key = KeyCodes.usageName(data.count > 1 ? data[1] : 0)
            return mods.isEmpty ? key : mods.joined(separator: "+") + "+" + key
        case 5:
            let v = (UInt16(data.first ?? 0) << 8) | UInt16(data.count > 1 ? data[1] : 0)
            return KeyCodes.mediaName(v) ?? "Media"
        case 7:
            switch data.first ?? 0 {
            case 1: return "DPI Up"
            case 2: return "DPI Down"
            case 5:
                guard data.count >= 3 else { return "DPI lock" }
                let dpi = (Int(data[1]) << 8) | Int(data[2])
                return "DPI lock \(dpi)"
            case 6: return "DPI Cycle Up"
            case 7: return "DPI Cycle Down"
            default: return "DPI"
            }
        case 8: return "Profile Switch"
        case 13: return "Polling Rate Switch"
        case 14: return "LOD Switch"
        case 16...18:
            let id = Int((UInt16(data.first ?? 0) << 8) | UInt16(data.count > 1 ? data[1] : 0))
            let runs = data.count > 2 ? data[2] : 0
            return "Macro \(id)" + (runs > 0 ? " ×\(runs)" : "")
        default: return "Action \(actionType)"
        }
    }
}
