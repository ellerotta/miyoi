import Foundation

public struct DeviceModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let wiredPID: Int
    public let wirelessPID: Int
    public let hasLCD: Bool
    public let maxDPIX: Int
    public let maxDPIY: Int
    public let maxStageCount: Int
    public let supportsAngular: Bool
    public let supportsMotionSync: Bool
    public let supportsRipple: Bool
    public let supportsHyper: Bool
    public let supportsTracking: Bool
    public let supportsDPIXY: Bool
    public let supportsButtonCombine: Bool
    public let hasLighting: Bool
    public let lodValues: [Double]
    public let wiredPollingRates: Set<Int>
    public let wirelessPollingRates: Set<Int>
    public let buttonIndices: Set<UInt8>

    public var pidList: [Int] { [wiredPID, wirelessPID] }
    public var pollingRates: Set<Int> { wiredPollingRates.union(wirelessPollingRates) }

    public func pollingRates(forPID pid: Int) -> Set<Int> {
        pid == wiredPID ? wiredPollingRates : wirelessPollingRates
    }
}

public enum DeviceRegistry {

    public static let vendorID = 0x373E

    public static let models: [DeviceModel] = [
        DeviceModel(
            id: "r6", name: "R6",
            wiredPID: 0x0021, wirelessPID: 0x0022,
            hasLCD: false, maxDPIX: 42000, maxDPIY: 42000, maxStageCount: 6,
            supportsAngular: true, supportsMotionSync: true, supportsRipple: true,
            supportsHyper: false, supportsTracking: true, supportsDPIXY: false,
            supportsButtonCombine: false, hasLighting: false, lodValues: [0.7, 1, 2],
            wiredPollingRates: [125, 250, 500, 1000],
            wirelessPollingRates: [125, 250, 500, 1000, 2000, 4000, 8000],
            buttonIndices: [1, 2, 3, 4, 5]
        ),
        DeviceModel(
            id: "r5u", name: "R5 Ultra",
            wiredPID: 0x0046, wirelessPID: 0x0047,
            hasLCD: false, maxDPIX: 42000, maxDPIY: 42000, maxStageCount: 6,
            supportsAngular: true, supportsMotionSync: true, supportsRipple: true,
            supportsHyper: false, supportsTracking: true, supportsDPIXY: false,
            supportsButtonCombine: false, hasLighting: false, lodValues: [0.7, 1, 2],
            wiredPollingRates: [125, 250, 500, 1000],
            wirelessPollingRates: [125, 250, 500, 1000, 2000, 4000, 8000],
            buttonIndices: [1, 2, 3, 4, 5]
        ),
        DeviceModel(
            id: "m5u", name: "M5 Ultra",
            wiredPID: 0x0051, wirelessPID: 0x0050,
            hasLCD: false, maxDPIX: 42000, maxDPIY: 42000, maxStageCount: 6,
            supportsAngular: true, supportsMotionSync: true, supportsRipple: true,
            supportsHyper: false, supportsTracking: true, supportsDPIXY: false,
            supportsButtonCombine: false, hasLighting: false, lodValues: [0.7, 1, 2],
            wiredPollingRates: [125, 250, 500, 1000],
            wirelessPollingRates: [125, 250, 500, 1000, 2000, 4000, 8000],
            buttonIndices: [1, 2, 3, 4, 5]
        ),
    ]

    public static func model(forPID pid: Int) -> DeviceModel? {
        models.first { $0.pidList.contains(pid) }
    }
}
