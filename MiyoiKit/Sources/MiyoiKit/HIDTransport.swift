import Foundation
import IOKit.hid
import Darwin

public struct HIDInfo: Identifiable, Hashable, Sendable {
    public let id: UInt64
    public let vid: Int
    public let pid: Int
    public let product: String
    public let usagePage: UInt32
    public let usage: UInt32
}

public enum HIDTransportError: Error, LocalizedError, Equatable {
    case deviceNotFound
    case invalidReportLength(Int)
    case ioFailure(operation: String, code: IOReturn)
    case systemFailure(operation: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "HID device not found"
        case .invalidReportLength(let length):
            return "HID feature reports must be exactly 64 bytes (received \(length))"
        case .ioFailure(let operation, let code):
            return "HID \(operation) failed (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16)))"
        case .systemFailure(let operation, let code):
            return "HID \(operation) failed (errno \(code): \(String(cString: strerror(code))))"
        }
    }
}

extension IOHIDDevice {
    fileprivate var vid: Int {
        (IOHIDDeviceGetProperty(self, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
    }
    fileprivate var pidValue: Int {
        (IOHIDDeviceGetProperty(self, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
    }
    fileprivate var usagePageValue: UInt32 {
        (IOHIDDeviceGetProperty(self, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.uint32Value ?? 0
    }
    fileprivate var productName: String {
        if let data = IOHIDDeviceGetProperty(self, kIOHIDProductKey as CFString) as? Data {
            return String(decoding: data, as: UTF8.self)
        }
        return IOHIDDeviceGetProperty(self, kIOHIDProductKey as CFString) as? String ?? ""
    }
}

public enum DeviceDiscovery {

    public static func allHIDDevices() -> [(device: IOHIDDevice, info: HIDInfo)] {
        guard let matcher = IOServiceMatching("AppleUserHIDDevice") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matcher, &iterator) == kIOReturnSuccess else { return [] }
        var result: [(IOHIDDevice, HIDInfo)] = []
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            if let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) {
                let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.uint64Value ?? 0
                var registryID: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &registryID) != kIOReturnSuccess {
                    registryID = location
                }
                let info = HIDInfo(
                    id: registryID,
                    vid: device.vid,
                    pid: device.pidValue,
                    product: device.productName,
                    usagePage: device.usagePageValue,
                    usage: (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.uint32Value ?? 0
                )
                result.append((device, info))
            }
        }
        return result
    }
}

public final class HIDTransport {
    private static let reportLength = 64

    public let device: IOHIDDevice
    public let info: HIDInfo
    private let queue = DispatchQueue(label: "miyoi.transport")
    private let lockFileDescriptor: Int32

    public convenience init(matchingVID vid: Int, pid: Int, usagePage: UInt32 = 0xFFFF) throws {
        guard let entry = DeviceDiscovery.allHIDDevices().first(where: {
            $0.info.vid == vid && $0.info.usagePage == usagePage && $0.info.pid == pid
        }) else { throw HIDTransportError.deviceNotFound }
        try self.init(entry: entry)
    }

    public convenience init(matchingVID vid: Int, pids: [Int], usagePage: UInt32 = 0xFFFF) throws {
        guard let entry = DeviceDiscovery.allHIDDevices().first(where: {
            $0.info.vid == vid && $0.info.usagePage == usagePage && pids.contains($0.info.pid)
        }) else { throw HIDTransportError.deviceNotFound }
        try self.init(entry: entry)
    }

    private init(entry: (device: IOHIDDevice, info: HIDInfo)) throws {
        device = entry.device
        info = entry.info
        let lockPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("miyoi-\(entry.info.vid)-\(entry.info.pid)-\(entry.info.id).lock")
        lockFileDescriptor = open(
            lockPath,
            O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard lockFileDescriptor >= 0 else {
            throw HIDTransportError.systemFailure(operation: "lock file open", code: errno)
        }
        var lockStatus = stat()
        guard fstat(lockFileDescriptor, &lockStatus) == 0,
              lockStatus.st_uid == getuid(),
              lockStatus.st_mode & S_IFMT == S_IFREG else {
            let code = errno == 0 ? EPERM : errno
            close(lockFileDescriptor)
            throw HIDTransportError.systemFailure(operation: "lock file validation", code: code)
        }
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            close(lockFileDescriptor)
            throw HIDTransportError.ioFailure(operation: "open", code: openResult)
        }
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        close(lockFileDescriptor)
    }

    public func sendReport(_ bytes: [UInt8]) throws -> [UInt8] {
        try exchange(bytes, readAttempts: 1) { _ in true }
    }

    public func exchange(
        _ bytes: [UInt8],
        readAttempts: Int,
        acceptingResponse: ([UInt8]) -> Bool
    ) throws -> [UInt8] {
        guard bytes.count == Self.reportLength else {
            throw HIDTransportError.invalidReportLength(bytes.count)
        }
        return try queue.sync {
            guard flock(lockFileDescriptor, LOCK_EX) == 0 else {
                throw HIDTransportError.systemFailure(operation: "lock", code: errno)
            }
            defer { flock(lockFileDescriptor, LOCK_UN) }
            var request = bytes
            let writeResult = IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeFeature,
                0,
                &request,
                request.count
            )
            guard writeResult == kIOReturnSuccess else {
                throw HIDTransportError.ioFailure(operation: "write", code: writeResult)
            }

            var lastReadError: Error?
            for attempt in 0..<max(1, readAttempts) {
                usleep(attempt == 0 ? 120_000 : 90_000)
                do {
                    let response = try readReport()
                    if acceptingResponse(response) { return response }
                } catch {
                    lastReadError = error
                }
            }
            if let lastReadError { throw lastReadError }
            return []
        }
    }

    private func readReport() throws -> [UInt8] {
        var response = [UInt8](repeating: 0, count: Self.reportLength)
        var length = response.count
        let readResult = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            0,
            &response,
            &length
        )
        guard readResult == kIOReturnSuccess else {
            throw HIDTransportError.ioFailure(operation: "read", code: readResult)
        }
        guard length >= 0, length <= response.count else {
            throw HIDTransportError.invalidReportLength(length)
        }
        return Array(response.prefix(length))
    }
}
